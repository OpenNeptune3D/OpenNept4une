import os
import re
import sys
import logging
from datetime import datetime

# Ensure script_dir is available whenever functions reference it
script_dir = os.path.dirname(os.path.abspath(__file__))

variable_regex = re.compile(r'{{\s*(\w+)\s*}}')


def get_printer_conf(printer_model, current):
    """
    Read the base printer_model.cfg and optional current.cfg from the printer_model folder.
    Exits with an error if any required file is missing.
    """
    folder = os.path.join(script_dir, printer_model)
    lines = []

    main_path = os.path.join(folder, f"{printer_model}.cfg")
    if not os.path.isfile(main_path):
        print(f"ERROR: {main_path} does not exist.")
        sys.exit(1)
    with open(main_path, 'r') as f:
        lines.extend(f.readlines())

    if current:
        override_path = os.path.join(folder, f"{current}.cfg")
        if not os.path.isfile(override_path):
            print(f"ERROR: {override_path} does not exist.")
            sys.exit(1)
        with open(override_path, 'r') as f:
            lines.extend(f.readlines())

    return lines


def generate_conf(printer_model, current):
    """
    Generate output.cfg by:
      1. Loading base.cfg
      2. Replacing {{ key }} placeholders with values from printer-specific files
      3. Injecting any section_*.cfg snippets
      4. Removing any leftover placeholders (entire lines)
      5. Writing a timestamped header + result to output.cfg
      6. Appending the SAVE_CONFIG section from ~/printer_data/config/printer.cfg
      7. Post-processing output.cfg to comment out mismatched SAVE_CONFIG entries
    """
    print("Generating config for " + printer_model + ("" if not current else " with current " + current))
    base_conf_path = os.path.join(script_dir, 'base.cfg')
    output_cfg_path = os.path.join(script_dir, 'output.cfg')

    if not os.path.isfile(base_conf_path):
        print(f"ERROR: base.cfg not found in {script_dir}")
        sys.exit(1)
    with open(base_conf_path, 'r') as f:
        base_conf = f.read()

    # Read printer-specific files
    printer_conf = get_printer_conf(printer_model, current)

    # Replace placeholders using regex so whitespace variations are accepted
    for line in printer_conf:
        if '=' not in line:
            continue
        key, value = [part.strip() for part in line.split('=', 1)]
        # Convert literal "\n" in the value into a real newline, if present
        value = value.replace(r'\n', '\n')
        pattern = r'{{\s*' + re.escape(key) + r'\s*}}'
        base_conf = re.sub(pattern, value, base_conf)

    # Inject any section_*.cfg snippets from the printer_model folder
    folder = os.path.join(script_dir, printer_model)
    for fname in os.listdir(folder):
        if fname.startswith('section_') and fname.endswith('.cfg'):
            section_name = fname[len('section_'):-len('.cfg')]  # e.g. "electronics"
            section_path = os.path.join(folder, fname)
            try:
                with open(section_path, 'r') as f:
                    section_conf = f.read().strip()
                pattern = r'{{\s*' + re.escape(section_name) + r'\s*}}'
                base_conf = re.sub(pattern, section_conf, base_conf)
            except (FileNotFoundError, IOError):
                print(f"Warning: '{fname}' was not found or unreadable; skipping.")

    # Remove any leftover lines containing unreplaced placeholders
    unreplaced = variable_regex.findall(base_conf)
    for placeholder in unreplaced:
        pattern = rf'^.*{{{{\s*{re.escape(placeholder)}\s*}}}}.*\n?'
        base_conf = re.sub(pattern, '', base_conf, flags=re.MULTILINE)

    # Add a timestamped header comment
    timestamp = datetime.now().isoformat(timespec='seconds')
    header_comment = (
        f"# Auto-generated on {timestamp} | printer_model: {printer_model} | current: {current or 'None'}\n\n"
    )

    # Write header + base_conf to output.cfg
    with open(output_cfg_path, 'w') as output:
        output.write(header_comment)
        output.write(base_conf)

    # Append the SAVE_CONFIG section from the user's main printer.cfg, then post-process
    append_printer_section(
        os.path.expanduser('~/printer_data/config/printer.cfg'),
        output_cfg_path
    )


def append_printer_section(printer_cfg_path, output_cfg_path):
    """
    Read the user's main printer.cfg and extract the last contiguous block of lines
    prefixed with '#*#'. Append that block to output.cfg, then run ConfigProcessor
    to comment out any keys that no longer match their saved values.
    """
    if not os.path.isfile(printer_cfg_path):
        print(f"No printer.cfg found at '{printer_cfg_path}'. Skipping append.")
        return

    with open(printer_cfg_path, 'r') as f:
        lines = f.readlines()

    # Collect the last contiguous block of lines that start with '#*#'
    section = []
    for line in reversed(lines):
        if line.startswith('#*#'):
            section.insert(0, line.rstrip('\r\n'))
        elif section:
            break  # stop once we've collected a contiguous block

    if not section:
        print("No lines starting with '#*#' found in printer.cfg. Skipping append.")
        return

    # Append that section to output.cfg
    with open(output_cfg_path, 'a') as output:
        output.write('\n' + '\n'.join(section) + '\n')
        print("Printer section appended to " + output_cfg_path)

    # Post-process the combined output.cfg to comment out mismatched SAVE_CONFIG entries
    processor = ConfigProcessor()
    try:
        processed_config = processor.process_config_file(output_cfg_path)
    except RuntimeError as e:
        print(f"ERROR during post-processing: {e}")
        return

    with open(output_cfg_path, 'w') as output:
        output.write(processed_config)
    print("Config file processed and updated.")


class ConfigProcessor:
    """
    Finds the SAVE_CONFIG header in a config file, parses out the saved key=value pairs,
    then comments out any lines in the main config whose values no longer match the saved ones.
    """

    def __init__(self):
        self.SAVE_CONFIG_data = {}
        self.SAVE_CONFIG_HEADER = "#*# <---------------------- SAVE_CONFIG ---------------------->"

    def _read_config_file(self, filename):
        try:
            with open(filename, 'r') as f:
                return f.read().replace('\r\n', '\n')
        except Exception as e:
            msg = f"Unable to open config file {filename}: {e}"
            logging.exception(msg)
            raise RuntimeError(msg) from e

    def _find_SAVE_CONFIG_data(self, data):
        # Only parse if the header is present
        if self.SAVE_CONFIG_HEADER not in data:
            return

        # Grab everything after the header
        SAVE_CONFIG_section = data.split(self.SAVE_CONFIG_HEADER, 1)[1]
        current_section = None

        for raw_line in SAVE_CONFIG_section.split('\n'):
            line = raw_line.strip()
            if line.startswith("#*# [") and line.endswith("]"):
                # Example: "#*# [printer]"
                sec = line[4:].strip()        # -> "[printer]"
                sec = sec.strip('[]').strip() # -> "printer"
                current_section = sec
                self.SAVE_CONFIG_data[current_section] = {}
            elif current_section and line.startswith("#*#") and '=' in line:
                # Example: "#*# foo = bar"
                rest = line[3:].strip()  # -> "foo = bar"
                key, val = rest.split('=', 1)
                self.SAVE_CONFIG_data[current_section][key.strip()] = val.strip()

    def _process_config_data(self, data):
        lines = data.split('\n')
        if self.SAVE_CONFIG_HEADER in lines:
            SAVE_CONFIG_start_index = lines.index(self.SAVE_CONFIG_HEADER)
        else:
            SAVE_CONFIG_start_index = len(lines)

        current_section = None
        for i, raw_line in enumerate(lines[:SAVE_CONFIG_start_index]):
            line = raw_line.strip()
            if line.startswith('[') and line.endswith(']'):
                current_section = line.strip('[]')
            elif current_section and '=' in line:
                key, val = [p.strip() for p in line.split('=', 1)]
                saved_val = self.SAVE_CONFIG_data.get(current_section, {}).get(key)
                if saved_val is not None and saved_val != val:
                    # Comment out any line whose value no longer matches the saved one
                    lines[i] = "# " + line

        # Reassemble everything, including the SAVE_CONFIG block unchanged
        return '\n'.join(lines)

    def process_config_file(self, filename):
        data = self._read_config_file(filename)
        self._find_SAVE_CONFIG_data(data)
        return self._process_config_data(data)


if __name__ == '__main__':
    # Remove old output.cfg if it exists
    try:
        os.remove(os.path.join(script_dir, 'output.cfg'))
    except OSError:
        pass  # nothing to remove

    if len(sys.argv) < 2:
        print("Usage: python generate_printer_cfg.py <printer_model> [<override>]")
        sys.exit(1)

    printer_model = sys.argv[1]
    current = sys.argv[2] if len(sys.argv) > 2 else None
    generate_conf(printer_model, current)
