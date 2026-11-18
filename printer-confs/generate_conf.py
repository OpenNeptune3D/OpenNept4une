#!/usr/bin/env python3
"""
Generate a model-specific Klipper printer.cfg from base.cfg + per-model and
per-toolhead profile files.

Usage:
    generate_conf.py <printer_model> [<current>] [--toolhead ribbon|usb-c]
                     [--probe stock|cartographer|beacon|eddy]
    generate_conf.py <printer_model> --probe cartographer|beacon|eddy
                     --seed-probe-cfg --probe-offset X,Y [--probe-serial PATH]
                     [--probe-accel v3|v4|none] [--toolhead ribbon|usb-c]
    generate_conf.py --check-edits <current printer.cfg> <new output.cfg> [--probe ...]
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
    # [include <probe>.cfg] for scanning probes; absent for the stock probe
    'probe_include',
})

# Z probe variants. 'stock' is the [probe] block in base.cfg. The others are
# Klipper plugins that register their own 'probe' object, so [probe] must be
# removed and a user-owned ~/printer_data/config/<probe>.cfg included last
# (Klipper merges repeated sections, so that file can override anything).
PROBES = ('stock', 'cartographer', 'beacon', 'eddy')

PROBE_SERIAL_GLOBS = {
    'cartographer': '/dev/serial/by-id/usb-Cartographer_*',
    'beacon': '/dev/serial/by-id/usb-Beacon_Beacon_*',
    # BTT Eddy USB runs Klipper on an RP2040; so does a Pico used as an
    # accelerometer, hence --probe-serial when both are plugged in.
    'eddy': '/dev/serial/by-id/usb-Klipper_rp2040_*',
}

# Distance (mm) kept from the bed edge when seeding mesh_min / mesh_max.
PROBE_MESH_MARGIN = 15.0
# Target distance (mm) between scanned mesh points when seeding probe_count.
PROBE_MESH_SPACING = 10.8

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


# Keys a toolhead profile is expected to override in the model profiles; replacing
# these is not reported as a collision.
TOOLHEAD_OVERRIDES = frozenset({
    'frame_light_pin',
    'part_light_pin',
})


def collect_values(printer_model, current, toolhead):
    """
    Build the placeholder -> value map. Toolhead values are applied first and
    win on collision (they describe hardware pinout, which is the more
    specific layer). Collisions are reported, except for TOOLHEAD_OVERRIDES.
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
                if merged[key] != value and key not in TOOLHEAD_OVERRIDES:
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


def drop_section(conf, name):
    """
    Remove the [name] section: its header and every line up to the next
    section header. Trailing blank/column-0 comment lines are kept, because
    those are the banner of the section that follows.
    """
    lines = conf.split('\n')
    start = None
    for i, line in enumerate(lines):
        m = SECTION_HEADER_RE.match(line.strip())
        if m and m.group(1).strip() == name:
            start = i
            break
    if start is None:
        raise GenerationError(f"cannot remove [{name}]: no such section in base.cfg")

    end = start + 1
    while end < len(lines) and not SECTION_HEADER_RE.match(lines[end].strip()):
        end += 1
    keep_from = end
    while keep_from > start + 1 and (not lines[keep_from - 1].strip()
                                     or lines[keep_from - 1].startswith('#')):
        keep_from -= 1
    # keep a single separating blank line, not the whole run
    while keep_from < end and not lines[keep_from].strip():
        keep_from += 1
    return '\n'.join(lines[:start] + lines[keep_from:])


def render(printer_model, current, toolhead, probe='stock'):
    """Render base.cfg for one model/current/toolhead/probe combination."""
    if probe not in PROBES:
        raise GenerationError(
            f"unknown probe '{probe}' (expected one of: {', '.join(PROBES)})")
    base_path = os.path.join(script_dir, 'base.cfg')
    if not os.path.isfile(base_path):
        raise GenerationError(f"base.cfg not found in {script_dir}")
    with open(base_path, 'r') as f:
        conf = f.read()

    declared = set(VARIABLE_RE.findall(conf))
    values, origin = collect_values(printer_model, current, toolhead)
    sections = collect_sections(printer_model, toolhead)
    if probe != 'stock':
        values['probe_include'] = f"[include {probe}.cfg]"
        origin['probe_include'] = f"--probe {probe}"

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

    if probe != 'stock':
        # The probe plugin registers its own 'probe' object; a [probe]
        # section next to it fails at Klipper startup.
        conf = drop_section(conf, 'probe')

    check_sections(conf, printer_model, toolhead)
    return conf


# ---------------------------------------------------------------------------
# Scanning probe include file (cartographer.cfg / beacon.cfg / eddy.cfg)
# ---------------------------------------------------------------------------

def probe_cfg_path(probe):
    return os.path.join(os.path.expanduser('~/printer_data/config'), f"{probe}.cfg")


def section_names(path):
    """[section] names in a config file, or an empty set if it is unreadable."""
    names = set()
    try:
        with open(path, 'r') as f:
            for line in f:
                m = SECTION_HEADER_RE.match(line.strip())
                if m:
                    names.add(m.group(1).strip())
    except OSError:
        pass
    return names


def stock_probe_offset():
    """x_offset / y_offset of the stock [probe] block in base.cfg."""
    with open(os.path.join(script_dir, 'base.cfg'), 'r') as f:
        conf = f.read()
    m = re.search(r'^\[probe\]\s*\n(.*?)(?=^\[)', conf, flags=re.MULTILINE | re.DOTALL)
    if not m:
        raise GenerationError("no [probe] section in base.cfg")
    offsets = {}
    for key in ('x_offset', 'y_offset'):
        km = re.search(rf'^{key}\s*[:=]\s*(-?[\d.]+)', m.group(1), flags=re.MULTILINE)
        if not km:
            raise GenerationError(f"no {key} in base.cfg [probe]")
        offsets[key] = float(km.group(1))
    return offsets['x_offset'], offsets['y_offset']


def stock_option(section, option):
    """A column-0 option value from a section of base.cfg (comments stripped)."""
    with open(os.path.join(script_dir, 'base.cfg'), 'r') as f:
        conf = f.read()
    m = re.search(rf'^\[{re.escape(section)}\]\s*\n(.*?)(?=^\[)', conf,
                  flags=re.MULTILINE | re.DOTALL)
    if m:
        om = re.search(rf'^{re.escape(option)}\s*[:=]\s*([^#;\n]*)', m.group(1),
                       flags=re.MULTILINE)
        if om:
            return om.group(1).strip()
    raise GenerationError(f"no {option} in base.cfg [{section}]")


def parse_xy(text, what):
    try:
        x, y = (float(p) for p in text.split(','))
    except ValueError:
        raise GenerationError(f"{what}: expected 'X,Y', got '{text}'")
    return x, y


def parse_offset(text):
    """'X,Y' -> (float, float)."""
    try:
        x, y = (float(p) for p in text.split(','))
    except (ValueError, AttributeError):
        raise GenerationError(f"probe offset must be 'X,Y' in mm, got '{text}'")
    return x, y


def detect_probe_serial(probe):
    pattern = PROBE_SERIAL_GLOBS[probe]
    matches = sorted(glob.glob(pattern))
    if not matches:
        raise GenerationError(
            f"no {probe} probe found matching {pattern}. Plug it in via USB and "
            f"check it shows up in /dev/serial/by-id/. CAN-connected probes are "
            f"not seeded automatically: write ~/printer_data/config/{probe}.cfg "
            f"by hand with canbus_uuid.")
    if len(matches) > 1:
        listing = '\n'.join(f"  {m}" for m in matches)
        raise GenerationError(
            f"multiple devices match {pattern}:\n{listing}\n"
            f"Pass the probe's one with --probe-serial (OpenNept4une.sh: --probe_serial).")
    return matches[0]


def fmt(n):
    """Format mm values without trailing noise: 117.5, 32.5, 15."""
    return f"{round(n, 2):g}"


def probe_geometry(printer_model, offset):
    """
    Bed-size and probe-offset dependent positions for one model, all derived
    from that model's stock profile so n4 / n4pro / n4plus / n4max each get
    their own values:

      home spot   the bed point the stock probe homes Z on (stock
                  safe_z_home + stock probe offset); the new probe is put
                  over the same spot, so upstream's per-model choice holds
      bed centre  half the X/Y travel (117.5 / 165 / 215)
      mesh        everywhere the new probe can reach inside the bed area the
                  stock mesh bounds imply, at PROBE_MESH_SPACING between points
      screws      stock screw points shifted so the new probe lands on the
                  same screw the stock probe did
    """
    model_path = os.path.join(script_dir, printer_model, f"{printer_model}.cfg")
    if not os.path.isfile(model_path):
        raise GenerationError(f"{model_path} does not exist")
    model = parse_kv_file(model_path)
    try:
        x_min, x_max = float(model['x_position_min']), float(model['x_position_max'])
        y_min, y_max = float(model['y_position_min']), float(model['y_position_max'])
        hx, hy = (float(v) for v in model['safe_z_home_xy_position'].split(','))
    except KeyError as e:
        raise GenerationError(f"{model_path}: missing {e.args[0]}")

    ox, oy = offset
    sx, sy = stock_probe_offset()
    cx, cy = x_max / 2, y_max / 2
    m = PROBE_MESH_MARGIN

    # Nozzle position that puts the new probe over the stock homing spot.
    home_x, home_y = hx + sx - ox, hy + sy - oy
    if not (x_min <= home_x <= x_max and y_min <= home_y <= y_max):
        raise GenerationError(
            f"{printer_model}: with probe offset {fmt(ox)},{fmt(oy)} the homing "
            f"position {fmt(home_x)},{fmt(home_y)} is outside the printer's travel")

    # Usable bed area per axis. The stock mesh bounds mark the bed edge on
    # each side where the stock probe could have gone further (so upstream
    # stopped for the bed, not for reach); elsewhere fall back to a margin
    # inside the travel. A smaller mesh is safe, probing off the bed is not.
    stock_min = parse_xy(stock_option('bed_mesh', 'mesh_min'), 'base.cfg mesh_min')
    stock_max = parse_xy(model.get('bed_mesh_max', ''), f"{model_path} bed_mesh_max")
    def bed_limits(lo, hi, s_off, s_min, s_max):
        bed_lo = s_min if s_min - (lo + s_off) > 3 else m
        bed_hi = s_max if (hi + s_off) - s_max > 3 else hi - m
        return bed_lo, bed_hi
    bx_lo, bx_hi = bed_limits(x_min, x_max, sx, stock_min[0], stock_max[0])
    by_lo, by_hi = bed_limits(y_min, y_max, sy, stock_min[1], stock_max[1])

    # New probe: inside the bed area and within what travel lets it reach.
    mx_min, mx_max = max(bx_lo, x_min + ox + 1), min(bx_hi, x_max + ox - 1)
    my_min, my_max = max(by_lo, y_min + oy + 1), min(by_hi, y_max + oy - 1)
    if mx_max - mx_min < 50 or my_max - my_min < 50:
        raise GenerationError(
            f"{printer_model}: probe offset {fmt(ox)},{fmt(oy)} leaves almost no "
            f"bed area the probe can reach; check the offset")

    def count(span):
        return max(5, round(span / PROBE_MESH_SPACING) + 1)

    # Axis twist: nozzle X range where nozzle and probe are both over the bed.
    tw_start = max(x_min, bx_lo, bx_lo - ox)
    tw_end = min(x_max, bx_hi, bx_hi - ox)

    screw_path = os.path.join(script_dir, printer_model, 'section_screw_tilt.cfg')
    screws = []
    with open(screw_path, 'r') as f:
        for line in f.read().strip().split('\n'):
            sm = re.match(r'^(screw\d+)\s*:\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*$', line)
            if sm:
                screws.append(f"{sm.group(1)}: {fmt(float(sm.group(2)) + sx - ox)}, "
                              f"{fmt(float(sm.group(3)) + sy - oy)}")
            else:
                screws.append(line.rstrip())

    return {
        'probe_x_offset': fmt(ox),
        'probe_y_offset': fmt(oy),
        'home_xy_position': f"{fmt(home_x)}, {fmt(home_y)}",
        'mesh_min': f"{fmt(mx_min)}, {fmt(my_min)}",
        'mesh_max': f"{fmt(mx_max)}, {fmt(my_max)}",
        'probe_count': f"{count(mx_max - mx_min)}, {count(my_max - my_min)}",
        'axis_twist_start_x': fmt(tw_start),
        'axis_twist_end_x': fmt(tw_end),
        'axis_twist_y': fmt(home_y),
        'resonance_point': f"{fmt(cx)}, {fmt(cy)}, 20",
        'screw_tilt': '\n'.join(screws),
        'printer_model': printer_model,
    }


# Cartographer's onboard ADXL345 chip-select pin per hardware version. The
# wrong pin puts the probe in an endless bootloop, so it is only enabled for a
# version the user picked or the USB name identifies.
CARTOGRAPHER_ACCEL_CS = {'v3': 'PA3', 'v4': 'PA0'}
CARTOGRAPHER_ACCEL_CHOICES = ('v3', 'v4', 'none')


def cartographer_version_from_serial(serial):
    """
    'v3' / 'v4' from the MCU in the USB name, or None. Same rule as
    Cartographer's own fw_update.sh: stm32f042 is V3, stm32g431/g474 is V4.
    """
    name = os.path.basename(serial or '').lower()
    if 'stm32f042' in name:
        return 'v3'
    if 'stm32g431' in name or 'stm32g474' in name:
        return 'v4'
    return None


def toolhead_has_resonance_tester(printer_model, toolhead):
    """True if the generated printer.cfg already has an active [resonance_tester]."""
    accel = collect_sections(printer_model, toolhead).get('accelerometer', '')
    return any(SECTION_HEADER_RE.match(line.strip()) and line.strip() == '[resonance_tester]'
               for line in accel.split('\n') if not line.startswith('#'))


def cartographer_accel_section(version, resonance_point, keep_existing_tester):
    """Text for {{ probe_accel_section }} in probes/cartographer.cfg."""
    if version not in CARTOGRAPHER_ACCEL_CS:
        return (
            "# Accelerometer on the probe, not set up. To use it, uncomment and keep\n"
            "# ONLY the cs_pin for your probe: the wrong one causes an endless bootloop.\n"
            "#[adxl345 hotend]\n"
            "#cs_pin: cartographer:PA3  # Cartographer V3\n"
            "#cs_pin: cartographer:PA0  # Cartographer V4\n"
            "#spi_bus: spi1\n"
            "#\n"
            "#[resonance_tester]\n"
            "#accel_chip: adxl345 hotend\n"
            "#probe_points:\n"
            f"#    {resonance_point}  # bed centre")
    other = 'v3' if version == 'v4' else 'v4'
    text = (
        f"# Accelerometer on the probe (Cartographer {version.upper()}). A {other.upper()} needs\n"
        f"# cs_pin: cartographer:{CARTOGRAPHER_ACCEL_CS[other]}; the wrong pin causes an endless bootloop.\n"
        "[adxl345 hotend]\n"
        f"cs_pin: cartographer:{CARTOGRAPHER_ACCEL_CS[version]}\n"
        "spi_bus: spi1\n\n")
    tester = ("[resonance_tester]\n"
              "accel_chip: adxl345 hotend\n"
              "probe_points:\n"
              f"    {resonance_point}  # bed centre")
    if keep_existing_tester:
        text += ("# printer.cfg already has a [resonance_tester] for the toolhead's own\n"
                 "# accelerometer; to measure with the probe instead, uncomment this.\n"
                 + '\n'.join('#' + line for line in tester.split('\n')))
    else:
        text += tester
    return text


def render_probe_cfg(printer_model, probe, offset, serial, accel='none',
                     toolhead='ribbon'):
    """Render printer-confs/probes/<probe>.cfg for one model."""
    template_path = os.path.join(script_dir, 'probes', f"{probe}.cfg")
    if not os.path.isfile(template_path):
        raise GenerationError(f"{template_path} does not exist")
    with open(template_path, 'r') as f:
        text = f.read()

    values = probe_geometry(printer_model, offset)
    values['probe_serial'] = serial
    if probe == 'cartographer':
        values['probe_accel_section'] = cartographer_accel_section(
            accel, values['resonance_point'],
            toolhead_has_resonance_tester(printer_model, toolhead))
    for key, value in values.items():
        text = substitute(text, key, value)
    leftover = sorted(set(VARIABLE_RE.findall(text)))
    if leftover:
        raise GenerationError(
            f"{template_path}: no value for placeholder(s): {', '.join(leftover)}")
    return text


# Where each probe's USB serial lives in its include file.
PROBE_SERIAL_SECTION = {
    'cartographer': 'mcu cartographer',
    'beacon': 'beacon',
    'eddy': 'mcu eddy',
}

SERIAL_LINE_RE = re.compile(r'^serial\s*[:=]\s*(.*?)\s*$')
CANBUS_LINE_RE = re.compile(r'^canbus_uuid\s*[:=]\s*\S')


def ensure_probe_serial(probe, override=None):
    """
    Fill in the probe's serial in ~/printer_data/config/<probe>.cfg when it is
    missing or points at a device that is not there (e.g. a placeholder, or a
    probe that was replaced), using the single matching /dev/serial/by-id
    device. A working serial, or a CAN setup (canbus_uuid), is left alone.
    Problems are warnings: generation still succeeds.
    """
    path = probe_cfg_path(probe)
    section = PROBE_SERIAL_SECTION[probe]
    with open(path, 'r') as f:
        lines = f.read().split('\n')

    header = None
    for i, line in enumerate(lines):
        m = SECTION_HEADER_RE.match(line.split('#')[0].strip())
        if m and m.group(1).strip() == section:
            header = i
            break
    if header is None:
        warn(f"{path} has no [{section}] section; cannot check the probe's serial")
        return

    serial_idx, current = None, ''
    for i in range(header + 1, len(lines)):
        line = lines[i]
        if SECTION_HEADER_RE.match(line.split('#')[0].strip()):
            break
        if CANBUS_LINE_RE.match(line):
            return  # CAN probe, no USB serial
        m = SERIAL_LINE_RE.match(line)
        if m:
            serial_idx = i
            current = re.split(r'\s[#;]', m.group(1))[0].strip()

    if override:
        target = override
    elif current and os.path.exists(current):
        return
    else:
        pattern = PROBE_SERIAL_GLOBS[probe]
        matches = sorted(glob.glob(pattern))
        if len(matches) != 1:
            found = ('no device matches' if not matches else
                     'several devices match (' + ', '.join(matches) + ')')
            warn(f"[{section}] serial in {path} is '{current or 'not set'}', which "
                 f"does not exist, and {found} {pattern}. Klipper will not connect "
                 f"to the probe until this is fixed (or pass --probe-serial).")
            return
        target = matches[0]

    if target == current:
        return
    new_line = f"serial: {target}"
    if serial_idx is None:
        lines.insert(header + 1, new_line)
    else:
        lines[serial_idx] = new_line
    backup = f"{path}.bak"
    with open(path, 'r') as src, open(backup, 'w') as dst:
        dst.write(src.read())
    write_atomic(path, '\n'.join(lines))
    print(f"Set [{section}] serial in {path} to {target} "
          f"(was '{current or 'not set'}'; previous file saved as {backup}).")


def seed_probe_cfg(printer_model, probe, offset_text, serial=None, accel=None,
                   toolhead='ribbon'):
    """Write ~/printer_data/config/<probe>.cfg from the template if it is missing."""
    if probe == 'stock':
        raise GenerationError(
            f"--seed-probe-cfg needs --probe {'|'.join(PROBES[1:])}")
    if not offset_text:
        raise GenerationError("--seed-probe-cfg needs --probe-offset X,Y")
    path = probe_cfg_path(probe)
    if os.path.exists(path):
        print(f"{path} already exists, not touching it.")
        return
    if serial:
        if not os.path.exists(serial):
            warn(f"{serial} does not exist right now; using it anyway")
    else:
        serial = detect_probe_serial(probe)

    if probe == 'cartographer':
        detected = cartographer_version_from_serial(serial)
        if accel is None:
            accel = detected or 'none'
            print(f"Cartographer accelerometer: "
                  f"{accel.upper() + ' (from the USB name)' if detected else 'not set up (version unknown)'}")
        elif accel not in CARTOGRAPHER_ACCEL_CHOICES:
            raise GenerationError(
                f"--probe-accel must be one of {', '.join(CARTOGRAPHER_ACCEL_CHOICES)}")
        elif accel != 'none' and detected and accel != detected:
            raise GenerationError(
                f"you chose Cartographer {accel.upper()}, but the probe's USB name "
                f"({os.path.basename(serial)}) says {detected.upper()}. The wrong "
                f"accelerometer pin causes an endless bootloop; choose "
                f"{detected.upper()} or 'none'.")
    text = render_probe_cfg(printer_model, probe, parse_offset(offset_text), serial,
                            accel or 'none', toolhead)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    write_atomic(path, text)
    print(f"Wrote {path}. Review it, then calibrate (Calibrate_Probe_Z_Offset).")


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


def warn_orphan_save_config(save_data, body_sections, included_sections=()):
    """
    Flag autosave sections with no corresponding section in the generated
    config. This is how a stale '[probe] z_offset' survives forever after a
    user swaps to a scanning probe (Cartographer/Eddy) and the [probe] block
    goes away. Warn rather than prune: sections can legitimately come from
    [include]d files that this script never sees.
    """
    present = {name.split()[0] for name in body_sections}
    present |= {name.split()[0] for name in included_sections}
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


def generate_conf(printer_model, current, toolhead='ribbon', output_path=None,
                  probe='stock', probe_serial=None):
    print(f"Generating config for {printer_model}"
          f"{'' if not current else ' with current ' + current}"
          f" (toolhead: {toolhead}, probe: {probe})")

    if output_path is None:
        output_path = os.path.join(script_dir, 'output.cfg')

    included_sections = set()
    if probe != 'stock':
        include_path = probe_cfg_path(probe)
        if not os.path.isfile(include_path):
            raise GenerationError(
                f"{include_path} does not exist, and the generated config includes "
                f"it (Klipper will not start without it). Create it with: "
                f"generate_conf.py {printer_model} --probe {probe} "
                f"--seed-probe-cfg --probe-offset X,Y")
        ensure_probe_serial(probe, probe_serial)
        included_sections = section_names(include_path)

    if toolhead == 'usb-c':
        generate_mcu_id_cfg()

    body = render(printer_model, current, toolhead, probe)

    timestamp = datetime.now().isoformat(timespec='seconds')
    header = (f"# Auto-generated on {timestamp} | printer_model: {printer_model} | "
              f"current: {current or 'None'} | toolhead: {toolhead} | probe: {probe}\n\n")

    save_block = extract_save_config(
        os.path.expanduser('~/printer_data/config/printer.cfg'))

    if save_block:
        save_data = parse_save_config(save_block)
        warn_orphan_save_config(save_data, check_sections(body, printer_model, toolhead),
                                included_sections)
        body = comment_superseded_options(body, save_data)
        text = header + body.rstrip('\n') + '\n\n' + '\n'.join(save_block) + '\n'
        print("SAVE_CONFIG section carried over from printer.cfg.")
    else:
        text = header + body

    write_atomic(output_path, text)
    print(f"Wrote {output_path}")


# ---------------------------------------------------------------------------
# Hand edits in printer.cfg that an update would drop
# ---------------------------------------------------------------------------

# Copy of the printer.cfg as last generated and applied, written by
# OpenNept4une.sh. Comparing printer.cfg against it separates the user's own
# edits from upstream template changes.
BASELINE_PATH = os.path.join(script_dir, 'last_applied.cfg')

# Sections whose tuning belongs in the scanning probe's include file.
PROBE_FILE_SECTIONS = frozenset({
    'bed_mesh', 'safe_z_home', 'screws_tilt_adjust', 'axis_twist_compensation',
    'resonance_tester', 'stepper_z',
})

INLINE_COMMENT_RE = re.compile(r'\s[#;].*$')
OPTION_RE = re.compile(r'^([A-Za-z_][\w.]*)\s*[:=]\s*(.*)$')


def parse_cfg_options(text):
    """
    {section: {option: normalised value}} for a Klipper config, the way
    Klipper reads it: column-0 options, indented continuation lines, comments
    (full-line and whitespace-prefixed inline) ignored, SAVE_CONFIG skipped.
    Whitespace is normalised so formatting-only changes do not count.
    """
    sections = {}
    section = option = None
    for raw in text.split('\n'):
        if raw.startswith('#*#'):
            continue
        stripped = raw.strip()
        if not stripped or stripped[0] in '#;':
            continue
        header = SECTION_HEADER_RE.match(INLINE_COMMENT_RE.sub('', stripped))
        if header and not raw[0].isspace():
            section = ' '.join(header.group(1).split())
            sections.setdefault(section, {})
            option = None
            continue
        if section is None:
            continue
        line = INLINE_COMMENT_RE.sub('', raw).rstrip()
        if raw[0].isspace():
            if option is not None and line.strip():
                cur = sections[section][option]
                sections[section][option] = (cur + '\n' if cur else '') + ' '.join(line.split())
            continue
        m = OPTION_RE.match(line)
        if m:
            option = m.group(1).lower()
            value = ' '.join(m.group(2).split())
            sections[section][option] = re.sub(r'\s*,\s*', ',', value)
    return sections


def describe(value):
    if '\n' in value:
        return f"{value.count(chr(10)) + 1} lines"
    return value if value else '(empty)'


def find_hand_edits(current_text, new_text, baseline_text=None, probe='stock'):
    """
    Settings in the user's printer.cfg that the new one would not keep.

    With a baseline (the printer.cfg as last generated) only real edits are
    reported: values the user changed, sections or includes they added, and
    options they removed that the update brings back. Without one, every
    value that differs from the update is reported, since a user edit and an
    upstream change cannot be told apart.

    Returns a list of (section, message) tuples.
    """
    cur = parse_cfg_options(current_text)
    new = parse_cfg_options(new_text)
    base = parse_cfg_options(baseline_text) if baseline_text is not None else None
    saved = parse_save_config([l for l in current_text.split('\n') if l.startswith('#*#')])
    dropped_by_design = {'probe'} if probe != 'stock' else set()

    edits = []
    for section, options in cur.items():
        if section in dropped_by_design:
            continue
        in_base = base is None or section in base
        if section not in new:
            if base is None or not in_base:
                what = 'include' if section.startswith('include ') else 'section'
                edits.append((section, f"[{section}] {what} is not in the update"))
            continue
        for option, value in options.items():
            if option in saved.get(section, {}):
                continue  # carried over by SAVE_CONFIG
            new_value = new[section].get(option)
            if new_value == value:
                continue
            if base is not None and base.get(section, {}).get(option) == value:
                continue  # not edited by the user: an upstream change
            if new_value is None:
                edits.append((section, f"[{section}] {option}: {describe(value)}  "
                                       f"(not in the update)"))
            elif '\n' in value or '\n' in new_value:
                edits.append((section, f"[{section}] {option} edited  "
                                       f"(yours {describe(value)}, update {describe(new_value)})"))
            else:
                edits.append((section, f"[{section}] {option}: {value}  "
                                       f"(update has {new_value})"))

    if base is not None:
        for section, options in base.items():
            if section in dropped_by_design or section not in new:
                continue
            if section not in cur:
                edits.append((section, f"[{section}] you removed this section; the update has it"))
                continue
            for option in options:
                if option not in cur[section] and option in new[section] \
                        and option not in saved.get(section, {}):
                    edits.append((section, f"[{section}] {option}: you removed it; "
                                           f"the update sets {describe(new[section][option])}"))
    return edits


def report_hand_edits(current_path, new_path, baseline_path=BASELINE_PATH, probe='stock'):
    """Print the hand-edit report. Returns the number of findings."""
    if not os.path.isfile(current_path):
        return 0
    with open(current_path, 'r') as f:
        current_text = f.read()
    with open(new_path, 'r') as f:
        new_text = f.read()
    baseline_text = None
    if baseline_path and os.path.isfile(baseline_path):
        with open(baseline_path, 'r') as f:
            baseline_text = f.read()

    edits = find_hand_edits(current_text, new_text, baseline_text, probe)
    if not edits:
        print("No hand edits in printer.cfg would be lost.")
        return 0

    if baseline_text is None:
        print("These printer.cfg settings differ from the update. Some may be "
              "upstream changes rather than your edits (there is no record of the "
              "last generated printer.cfg yet, so they cannot be told apart):")
    else:
        print("Your edits in printer.cfg that this update will not keep:")
    for _section, message in edits:
        print(f"  {message}")

    probe_file = f"{probe}.cfg" if probe != 'stock' else None
    probe_hits = sorted({s for s, _ in edits
                         if probe_file and s.split()[0] in PROBE_FILE_SECTIONS})
    print("To keep a setting, put it in user_settings.cfg (included after the "
          "generated sections, so it wins).")
    if probe_hits:
        print(f"For {', '.join(f'[{s}]' for s in probe_hits)} use {probe_file} "
              f"instead: it is included last and overrides user_settings.cfg too.")
    return len(edits)


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
                for probe in PROBES:
                    label = f"{model}/{cur or '-'}/{th}/{probe}"
                    try:
                        render(model, cur, th, probe)
                        print(f"  OK   {label}")
                    except GenerationError as e:
                        failures += 1
                        print(f"  FAIL {label}: {e}")
        for probe in PROBES[1:]:
            label = f"{model}/probes/{probe}.cfg"
            try:
                for th in variants:
                    for accel in (CARTOGRAPHER_ACCEL_CHOICES if probe == 'cartographer'
                                  else ('none',)):
                        render_probe_cfg(model, probe, (0.0, 20.0),
                                         '/dev/serial/by-id/validate', accel, th)
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
    parser.add_argument('--probe', default='stock', choices=PROBES,
                        help='Z probe: stock [probe], or a scanning probe whose '
                             '~/printer_data/config/<probe>.cfg is included')
    parser.add_argument('--seed-probe-cfg', action='store_true',
                        help='write ~/printer_data/config/<probe>.cfg from the '
                             'template if it does not exist, then exit')
    parser.add_argument('--probe-offset', default=None, metavar='X,Y',
                        help='probe offset from the nozzle in mm (with --seed-probe-cfg)')
    parser.add_argument('--check-edits', nargs=2, metavar=('CURRENT', 'NEW'),
                        help='list hand edits in CURRENT printer.cfg that NEW would '
                             'drop (compared against last_applied.cfg if present), '
                             'then exit; exit status 2 if there are any')
    parser.add_argument('--baseline', default=BASELINE_PATH, metavar='PATH',
                        help='printer.cfg as last generated, for --check-edits '
                             '(default: printer-confs/last_applied.cfg)')
    parser.add_argument('--probe-accel', default=None, choices=CARTOGRAPHER_ACCEL_CHOICES,
                        help='Cartographer hardware version, to set up its '
                             'accelerometer (with --seed-probe-cfg; default: from '
                             'the USB name, else none)')
    parser.add_argument('--probe-serial', default=None, metavar='PATH',
                        help='probe serial path to use instead of auto-detecting '
                             'it, when seeding or fixing <probe>.cfg')
    args = parser.parse_args(argv)

    try:
        if args.write_mcu_id:
            generate_mcu_id_cfg()
            return 0

        if args.validate_all:
            return validate_all(args.toolhead)

        if args.check_edits:
            found = report_hand_edits(args.check_edits[0], args.check_edits[1],
                                      args.baseline, probe=args.probe)
            return 2 if found else 0

        models = discover_models()
        if not args.printer_model:
            parser.error(f"printer_model is required (one of: {', '.join(models)})")
        if args.printer_model not in models:
            raise GenerationError(
                f"unknown printer model '{args.printer_model}' "
                f"(expected one of: {', '.join(models)})")

        if args.seed_probe_cfg:
            seed_probe_cfg(args.printer_model, args.probe, args.probe_offset,
                           args.probe_serial, args.probe_accel,
                           args.toolhead or 'ribbon')
            return 0

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

        generate_conf(args.printer_model, args.current, toolhead, out, args.probe,
                      args.probe_serial)
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
