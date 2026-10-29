#!/usr/bin/env python3
"""
Generate a model-specific Klipper printer.cfg from base.cfg + per-model and
per-toolhead profile files.

Usage:
    generate_conf.py <printer_model> [<current>] [--toolhead ribbon|usb-c]
    generate_conf.py --write-mcu-id
    generate_conf.py --validate-all [--toolhead ribbon|usb-c]

Substitution model
------------------
base.cfg contains {{ placeholder }} tokens. Values come from, in order of
application (first definition wins, collisions are reported):

    toolheads/<toolhead>.cfg      key=value   (pin mapping, toolhead sections)
    <model>/<model>.cfg           key=value   (geometry, PID, shapers, ...)
    <model>/<current>.cfg         key=value   (motor current variant)
    <model>/section_<name>.cfg    whole file -> {{ name }}
    toolheads/section_*_<v>_*.cfg whole file -> {{ name }}  (variant override)

Anything still unresolved after that is an ERROR unless it is listed in
OPTIONAL_PLACEHOLDERS, in which case its line is removed. This is the main
behavioural difference from earlier revisions, which removed the line for
*every* unresolved placeholder. That was silent for options Klipper defaults
(position_min -> 0, homing_retract_dist -> 5.0) and catastrophic for whole
sections (a missing {{ fans }} yields a config with no [fan] and no
[controller_fan] that still loads).
"""

import argparse
import glob
import logging
import os
import re
import sys
from datetime import datetime

script_dir = os.path.dirname(os.path.abspath(__file__))

VARIABLE_RE = re.compile(r'{{\s*(\w+)\s*}}')
SECTION_HEADER_RE = re.compile(r'^\[([^\]]+)\]\s*$')
# Klipper options live at column 0; anything indented is macro/template body.
OPTION_EQ_RE = re.compile(r'^([A-Za-z_][\w.]*)\s*=\s*(.*?)\s*$')

def discover_toolheads():
    """Toolhead variants are toolheads/<name>.cfg, excluding section_* snippets."""
    out = []
    for path in sorted(glob.glob(os.path.join(script_dir, 'toolheads', '*.cfg'))):
        name = os.path.basename(path)[:-len('.cfg')]
        if not name.startswith('section_'):
            out.append(name)
    return out


def discover_models():
    """A model is any directory containing <name>/<name>.cfg."""
    out = []
    for entry in sorted(os.listdir(script_dir)):
        d = os.path.join(script_dir, entry)
        if entry != 'toolheads' and os.path.isdir(d) \
                and os.path.isfile(os.path.join(d, f'{entry}.cfg')):
            out.append(entry)
    return out

USB_TOOLHEAD_SERIAL_GLOB = "/dev/serial/by-id/usb-Klipper_stm32f103xe_*"

# Placeholders that are legitimately absent for some model/toolhead
# combinations. Their line is dropped when unresolved. Everything else in
# base.cfg must be supplied by some profile file or generation fails.
OPTIONAL_PLACEHOLDERS = frozenset({
    # dual-zone bed: n4pro only
    'extra_heating',
    'extra_pid_macro',
    'start_bed_setup',
    'variable_small_print',
    'variable_force_outer_bed_heater',
    'variable_outer_bed_force_activation_temp',
    # per-model extras
    'extra_macros',
    'extra_stepper_x',
    'extra_stepper_y',
    # toolhead extras (empty for ribbon)
    'toolhead_mcu_include',
    'toolhead_extra_sections',
    # TMC hold currents: optional, Klipper defaults to run_current
    'x_hold_current',
    'y_hold_current',
    'z_hold_current',
    'e_hold_current',
})

# section_*.cfg name -> toolhead-specific replacement filename, relative to
# the toolheads/ folder, keyed by printer model.
USB_C_FAN_SECTION_BY_MODEL = {
    'n4': 'section_fans_usb-c_n4.cfg',
    'n4pro': 'section_fans_usb-c_n4.cfg',
    'n4plus': 'section_fans_usb-c_n4plus.cfg',
    'n4max': 'section_fans_usb-c_n4plus.cfg',
}

# Each model has its own dual lis2dw (THR) + adxl345 (rpi) accelerometer
# layout for usb-c, so this is keyed per-model rather than grouped.
USB_C_ACCEL_SECTION_BY_MODEL = {
    'n4': 'section_accel_usb-c_n4.cfg',
    'n4pro': 'section_accel_usb-c_n4pro.cfg',
    'n4plus': 'section_accel_usb-c_n4plus.cfg',
    'n4max': 'section_accel_usb-c_n4max.cfg',
}


class GenerationError(Exception):
    """Fatal problem with the profile set or the generated config."""


def warn(msg):
    print(f"WARNING: {msg}", file=sys.stderr)


# ---------------------------------------------------------------------------
# Profile parsing
# ---------------------------------------------------------------------------

def parse_kv_file(path):
    """
    Parse a key=value profile file. Comments (# or ;) and blank lines are
    skipped. Returns {key: value}; duplicate keys within one file are an error
    because the silent last-wins behaviour hides typos.
    """
    values = {}
    with open(path, 'r') as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith('#') or line.startswith(';'):
                continue
            if '=' not in line:
                continue
            key, value = (part.strip() for part in line.split('=', 1))
            if not key.isidentifier():
                warn(f"{path}:{lineno}: '{key}' is not a valid placeholder name, ignoring")
                continue
            if key in values:
                raise GenerationError(f"{path}:{lineno}: duplicate key '{key}'")
            # Literal "\n" in a value becomes a real newline.
            values[key] = value.replace(r'\n', '\n')
    return values


def collect_values(printer_model, current, toolhead):
    """
    Build the placeholder -> value map. Toolhead values are applied first and
    win on collision (they describe hardware pinout, which is the more
    specific layer), but every collision is reported.
    """
    toolhead_path = os.path.join(script_dir, 'toolheads', f"{toolhead}.cfg")
    if not os.path.isfile(toolhead_path):
        raise GenerationError(
            f"unknown toolhead variant '{toolhead}' ({toolhead_path} does not exist)")

    model_dir = os.path.join(script_dir, printer_model)
    model_path = os.path.join(model_dir, f"{printer_model}.cfg")
    if not os.path.isfile(model_path):
        raise GenerationError(f"{model_path} does not exist")

    sources = [(toolhead_path, parse_kv_file(toolhead_path)),
               (model_path, parse_kv_file(model_path))]

    if current:
        current_path = os.path.join(model_dir, f"{current}.cfg")
        if not os.path.isfile(current_path):
            raise GenerationError(f"{current_path} does not exist")
        sources.append((current_path, parse_kv_file(current_path)))

    merged = {}
    origin = {}
    for path, values in sources:
        for key, value in values.items():
            if key in merged:
                if merged[key] != value:
                    warn(f"'{key}' defined in both {origin[key]} and {path}; "
                         f"keeping the value from {origin[key]}")
                continue
            merged[key] = value
            origin[key] = path
    return merged, origin


def collect_sections(printer_model, toolhead):
    """
    Map placeholder name -> section snippet text. Per-model section_*.cfg files
    are used unless a toolhead variant overrides that section.
    """
    overrides = {}
    if toolhead == 'usb-c':
        for name, table in (('fans', USB_C_FAN_SECTION_BY_MODEL),
                            ('accelerometer', USB_C_ACCEL_SECTION_BY_MODEL)):
            fname = table.get(printer_model)
            if fname is None:
                raise GenerationError(
                    f"no usb-c '{name}' section mapped for model '{printer_model}'; "
                    f"the ribbon-toolhead pinout would be used instead")
            path = os.path.join(script_dir, 'toolheads', fname)
            if not os.path.isfile(path):
                raise GenerationError(f"{path} does not exist (usb-c '{name}' override)")
            overrides[name] = path

    sections = {}
    model_dir = os.path.join(script_dir, printer_model)
    for path in sorted(glob.glob(os.path.join(model_dir, 'section_*.cfg'))):
        name = os.path.basename(path)[len('section_'):-len('.cfg')]
        if name in overrides:
            continue  # replaced by the toolhead-specific snippet
        with open(path, 'r') as f:
            sections[name] = f.read().strip()

    for name, path in overrides.items():
        with open(path, 'r') as f:
            sections[name] = f.read().strip()

    return sections


# ---------------------------------------------------------------------------
# Substitution
# ---------------------------------------------------------------------------

def substitute(text, key, value):
    """
    Replace every {{ key }} with value.

    The replacement is supplied as a callable so backslash sequences in the
    value (\\1, \\g, \\\\) are inserted literally instead of being interpreted
    as re.sub replacement-template escapes. Section snippets are arbitrary
    user-authored config, so this is not hypothetical.
    """
    pattern = r'{{\s*' + re.escape(key) + r'\s*}}'
    if value == '':
        # Drop the line entirely if the placeholder is alone on it, so an empty
        # value does not leave a stray blank line.
        text = re.sub(r'^[ \t]*' + pattern + r'[ \t]*\r?\n', '', text, flags=re.MULTILINE)
    return re.sub(pattern, lambda _m: value, text)


def render(printer_model, current, toolhead):
    """Render base.cfg for one model/current/toolhead combination."""
    base_path = os.path.join(script_dir, 'base.cfg')
    if not os.path.isfile(base_path):
        raise GenerationError(f"base.cfg not found in {script_dir}")
    with open(base_path, 'r') as f:
        conf = f.read()

    declared = set(VARIABLE_RE.findall(conf))
    values, origin = collect_values(printer_model, current, toolhead)
    sections = collect_sections(printer_model, toolhead)

    for key, value in values.items():
        conf = substitute(conf, key, value)
    for name, snippet in sections.items():
        conf = substitute(conf, name, snippet)

    # Profile keys that match no placeholder are dead config or typos.
    supplied = set(values) | set(sections)
    for key in sorted(supplied - declared):
        warn(f"'{key}' is defined in {origin.get(key, 'a section file')} "
             f"but no {{{{ {key} }}}} placeholder exists in base.cfg")

    # Anything still unresolved is fatal unless explicitly optional.
    unresolved = set(VARIABLE_RE.findall(conf))
    missing = sorted(unresolved - OPTIONAL_PLACEHOLDERS)
    if missing:
        raise GenerationError(
            f"{printer_model} (toolhead: {toolhead}): no value supplied for "
            f"placeholder(s): {', '.join(missing)}")

    for name in sorted(unresolved & OPTIONAL_PLACEHOLDERS):
        conf = re.sub(rf'^.*{{{{\s*{re.escape(name)}\s*}}}}.*\r?\n?', '',
                      conf, flags=re.MULTILINE)

    check_sections(conf, printer_model, toolhead)
    return conf


def check_sections(conf, printer_model, toolhead):
    """
    Catch duplicate [section] headers before Klipper does. Section snippet
    injection makes it easy to end up with two [fan] or two [controller_fan]
    blocks, and Klipper's own error for that is not obviously about the
    generator.
    """
    seen = {}
    for lineno, line in enumerate(conf.split('\n'), 1):
        m = SECTION_HEADER_RE.match(line.strip())
        if not m:
            continue
        name = m.group(1).strip()
        if name in seen:
            raise GenerationError(
                f"{printer_model} (toolhead: {toolhead}): duplicate section "
                f"[{name}] at generated lines {seen[name]} and {lineno}")
        seen[name] = lineno
    return seen


# ---------------------------------------------------------------------------
# SAVE_CONFIG handling
# ---------------------------------------------------------------------------

SAVE_CONFIG_HEADER = "#*# <---------------------- SAVE_CONFIG ---------------------->"


def extract_save_config(printer_cfg_path):
    """
    Return the last contiguous block of '#*#' lines from the user's printer.cfg,
    as a list of lines. Empty list if there is none.
    """
    if not os.path.isfile(printer_cfg_path):
        print(f"No printer.cfg found at '{printer_cfg_path}'. Skipping append.")
        return []

    with open(printer_cfg_path, 'r') as f:
        lines = f.readlines()

    block = []
    for line in reversed(lines):
        if line.startswith('#*#'):
            block.insert(0, line.rstrip('\r\n'))
        elif block:
            break
    if not block:
        print("No lines starting with '#*#' found in printer.cfg. Skipping append.")
    return block


def parse_save_config(block_lines):
    """Parse '#*# [section]' / '#*# key = value' into {section: {key: value}}."""
    data = {}
    section = None
    for raw in block_lines:
        line = raw.strip()
        if line.startswith("#*# [") and line.endswith("]"):
            section = line[4:].strip().strip('[]').strip()
            data.setdefault(section, {})
        elif section and line.startswith("#*#") and '=' in line:
            key, val = line[3:].strip().split('=', 1)
            data[section][key.strip()] = val.strip()
    return data


def comment_superseded_options(body, save_data):
    """
    Comment out any column-0 'key = value' line in the main body whose value is
    superseded by SAVE_CONFIG. Only '=' lines are considered; base.cfg uses ':'
    for options that must never be overridden by autosave and '=' for those
    that should be (PID gains, probe z_offset). That distinction is load-bearing
    -- do not "normalise" base.cfg to one delimiter.
    """
    out = []
    section = None
    for line in body.split('\n'):
        header = SECTION_HEADER_RE.match(line.strip())
        if header:
            section = header.group(1).strip()
            out.append(line)
            continue
        m = OPTION_EQ_RE.match(line)  # anchored at column 0 by construction
        if section and m:
            saved = save_data.get(section, {}).get(m.group(1))
            if saved is not None and saved != m.group(2):
                out.append('# ' + line.strip())
                continue
        out.append(line)
    return '\n'.join(out)


def warn_orphan_save_config(save_data, body_sections):
    """
    Flag autosave sections with no corresponding section in the generated
    config. This is how a stale '[probe] z_offset' survives forever after a
    user swaps to a scanning probe (Cartographer/Eddy) and the [probe] block
    goes away. Warn rather than prune: sections can legitimately come from
    [include]d files that this script never sees.
    """
    present = {name.split()[0] for name in body_sections}
    for name in save_data:
        if not name:
            continue
        if name.split()[0] not in present:
            warn(f"SAVE_CONFIG contains [{name}] but no such section exists in the "
                 f"generated config. If it comes from an included file "
                 f"(user_settings.cfg, a probe plugin) this is expected; otherwise "
                 f"it is stale and should be deleted from printer.cfg.")


# ---------------------------------------------------------------------------
# MCU_ID.cfg for the USB-C toolhead
# ---------------------------------------------------------------------------

def generate_mcu_id_cfg():
    """
    Detect the USB-C toolhead's Klipper MCU serial-by-id path and write
    ~/printer_data/config/MCU_ID.cfg defining [mcu THR].
    """
    matches = sorted(glob.glob(USB_TOOLHEAD_SERIAL_GLOB))
    if not matches:
        raise GenerationError(
            f"no USB-C toolhead found matching {USB_TOOLHEAD_SERIAL_GLOB}.\n"
            f"Connect the USB-C toolhead and ensure it has Klipper firmware "
            f"flashed, then try again.")
    if len(matches) > 1:
        listing = '\n'.join(f"  {m}" for m in matches)
        raise GenerationError(
            f"multiple USB-C toolhead devices found matching "
            f"{USB_TOOLHEAD_SERIAL_GLOB}:\n{listing}\n"
            f"Disconnect the extra device(s) and try again.")

    mcu_id_dir = os.path.expanduser('~/printer_data/config')
    os.makedirs(mcu_id_dir, exist_ok=True)
    mcu_id_path = os.path.join(mcu_id_dir, 'MCU_ID.cfg')
    write_atomic(mcu_id_path,
                 "[mcu THR]\n"
                 f"serial: {matches[0]}\n"
                 "restart_method: command\n")
    print(f"Wrote {mcu_id_path} (serial: {matches[0]})")


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def write_atomic(path, text):
    """Write via a temp file + os.replace so a crash cannot truncate the target."""
    tmp = f"{path}.tmp.{os.getpid()}"
    try:
        with open(tmp, 'w') as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise


def generate_conf(printer_model, current, toolhead='ribbon', output_path=None):
    print(f"Generating config for {printer_model}"
          f"{'' if not current else ' with current ' + current}"
          f" (toolhead: {toolhead})")

    if output_path is None:
        output_path = os.path.join(script_dir, 'output.cfg')

    if toolhead == 'usb-c':
        generate_mcu_id_cfg()

    body = render(printer_model, current, toolhead)

    timestamp = datetime.now().isoformat(timespec='seconds')
    header = (f"# Auto-generated on {timestamp} | printer_model: {printer_model} | "
              f"current: {current or 'None'} | toolhead: {toolhead}\n\n")

    save_block = extract_save_config(
        os.path.expanduser('~/printer_data/config/printer.cfg'))

    if save_block:
        save_data = parse_save_config(save_block)
        warn_orphan_save_config(save_data, check_sections(body, printer_model, toolhead))
        body = comment_superseded_options(body, save_data)
        text = header + body.rstrip('\n') + '\n\n' + '\n'.join(save_block) + '\n'
        print("SAVE_CONFIG section carried over from printer.cfg.")
    else:
        text = header + body

    write_atomic(output_path, text)
    print(f"Wrote {output_path}")


def validate_all(toolhead=None):
    """
    Render every model x current x toolhead combination and report failures.
    Does not touch hardware or write anything. Intended for CI, so a profile
    that is missing a placeholder is caught before it reaches a printer.
    """
    variants = discover_toolheads() if toolhead is None else [toolhead]
    failures = 0
    for model in discover_models():
        currents = [os.path.basename(p)[:-len('.cfg')]
                    for p in sorted(glob.glob(os.path.join(script_dir, model, '[0-9]*.cfg')))]
        for cur in (currents or [None]):
            for th in variants:
                label = f"{model}/{cur or '-'}/{th}"
                try:
                    render(model, cur, th)
                    print(f"  OK   {label}")
                except GenerationError as e:
                    failures += 1
                    print(f"  FAIL {label}: {e}")
    print(f"\n{failures} failure(s).")
    return 1 if failures else 0


# ---------------------------------------------------------------------------

def main(argv):
    parser = argparse.ArgumentParser(
        prog='generate_conf.py', add_help=True,
        description='Generate a model-specific Klipper printer.cfg from base.cfg.')
    parser.add_argument('printer_model', nargs='?')
    parser.add_argument('current', nargs='?', default=None,
                        help='motor current variant, e.g. 0.8 or 1.2')
    parser.add_argument('--toolhead', default=None)
    parser.add_argument('--out', default=None, help='output path (default: ./output.cfg)')
    parser.add_argument('--write-mcu-id', action='store_true',
                        help='only (re)write ~/printer_data/config/MCU_ID.cfg and exit')
    parser.add_argument('--validate-all', action='store_true',
                        help='render every model/current/toolhead combination and exit')
    args = parser.parse_args(argv)

    try:
        if args.write_mcu_id:
            generate_mcu_id_cfg()
            return 0

        if args.validate_all:
            return validate_all(args.toolhead)

        models = discover_models()
        if not args.printer_model:
            parser.error(f"printer_model is required (one of: {', '.join(models)})")
        if args.printer_model not in models:
            raise GenerationError(
                f"unknown printer model '{args.printer_model}' "
                f"(expected one of: {', '.join(models)})")

        toolhead = args.toolhead or 'ribbon'
        toolheads = discover_toolheads()
        if toolhead not in toolheads:
            raise GenerationError(
                f"unknown toolhead variant '{toolhead}' "
                f"(expected one of: {', '.join(toolheads)})")
        out = args.out or os.path.join(script_dir, 'output.cfg')

        # Remove any stale output before starting, so a failure cannot leave a
        # previous run's file looking current.
        try:
            os.remove(out)
        except OSError:
            pass

        generate_conf(args.printer_model, args.current, toolhead, out)
        return 0

    except GenerationError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    except OSError as e:
        logging.exception("I/O error")
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
