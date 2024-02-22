from sys import argv
import re
import os

variable_regex = re.compile(r'{{\s*(\w+)\s*}}')

def get_printer_conf(printer_model, current):
    folder = os.path.join(script_dir, printer_model) + '/'
    if current is not None:
        printer_conf = open(os.path.join(folder, printer_model + '.cfg'), 'r').readlines()
        printer_conf += open(os.path.join(folder, current + '.cfg'), 'r').readlines()
        return printer_conf
    else:
        return open(os.path.join(folder, printer_model + '.cfg'), 'r').readlines()

def generate_conf(printer_model, current):
    print("Generating config for " + printer_model + ("" if current is None else " with current " + current))
    base_conf_path = os.path.join(script_dir, 'base.cfg')
    output_cfg_path = os.path.join(script_dir, 'output.cfg')
    with open(base_conf_path, 'r') as file:
        base_conf = file.read()

    printer_conf = get_printer_conf(printer_model, current)
    for line in printer_conf:
        split = line.split('=')
        if len(split) > 1:
            key, value = split[0].strip(), split[1].strip()
            value = value.replace('\\n', '\n')
            base_conf = base_conf.replace('{{ ' + key + ' }}', value)

    section_files = os.listdir(os.path.join(script_dir, printer_model))
    for section_file in section_files:
        if section_file.startswith('section_') and section_file.endswith('.cfg'):
            section_name = section_file.replace('section_', '').replace('.cfg', '')
            section_path = os.path.join(script_dir, printer_model, section_file)
            try:
                with open(section_path, 'r') as file:
                    section_conf = file.read()
                    base_conf = base_conf.replace('{{ ' + section_name + ' }}', section_conf.strip())
            except FileNotFoundError:
                print(f"Warning: '{section_file}' was not found and will be skipped.")

    unreplaced = variable_regex.findall(base_conf)
    for placeholder in unreplaced:
        # Define a pattern to match the entire line containing the placeholder
        pattern = f'^.*{{{{\s*{placeholder}\s*}}}}.*\n?'
        # Replace the entire line containing the placeholder with an empty string
        base_conf = re.sub(pattern, '', base_conf, flags=re.MULTILINE)

    # Write the base configuration to output.cfg
    with open(os.path.join(script_dir, 'output.cfg'), 'w') as output:
        output.write(base_conf)

    # Now append the printer section
    append_printer_section(os.path.join(os.path.expanduser('~/printer_data/config'), 'printer.cfg'), output_cfg_path)

def append_printer_section(printer_cfg_path, output_cfg_path):
    # Check if printer.cfg exists
    if not os.path.exists(printer_cfg_path):
        print("No printer.cfg found. Skipping append.")
        return

    section = []
    with open(printer_cfg_path, 'r') as f:
        lines = f.readlines()
        for line in reversed(lines):
            if line.startswith('#*#'):
                section.insert(0, line.rstrip())
            elif section:
                break  # Stop reading once a line not starting with '#*#' is found after collecting section lines

    if not section:
        print("No lines starting with '#*#' found in printer.cfg. Skipping append.")
        return

    # Append the collected section
    with open(output_cfg_path, 'a') as output:
        output.write('\n' + '\n'.join(section))
        print("Printer section appended to " + output_cfg_path)

    processor = ConfigProcessor()
    processed_config = processor.process_config_file(os.path.join(script_dir, 'output.cfg'))

    with open(os.path.join(script_dir, 'output.cfg'), 'w') as output:
        output.write(processed_config)
    print("Config file processed and updated.")


class ConfigProcessor:
    def __init__(self):
        self.SAVE_CONFIG_data = {}
        # Define SAVE_CONFIG_HEADER here
        self.SAVE_CONFIG_HEADER = "#*# <---------------------- SAVE_CONFIG ---------------------->"

    def _read_config_file(self, filename):
        try:
            with open(filename, 'r') as f:
                data = f.read().replace('\r\n', '\n')
        except Exception as e:
            msg = f"Unable to open config file {filename}: {e}"
            logging.exception(msg)
            raise RuntimeError(msg) from e
        return data

    def _find_SAVE_CONFIG_data(self, data):
        SAVE_CONFIG_section = data.split(self.SAVE_CONFIG_HEADER)[-1]
        current_section = None
        for line in SAVE_CONFIG_section.split('\n'):
            line = line.strip()
            if line.startswith("#*# ["):
                current_section = line[4:].strip('[]')  # Extract the section name
                self.SAVE_CONFIG_data[current_section] = {}
            elif current_section and '=' in line:
                key, value = line[4:].split('=', 1)  # Remove '#*#' and split by '='
                self.SAVE_CONFIG_data[current_section][key.strip()] = value.strip()

    def _process_config_data(self, data):
        lines = data.split('\n')
        SAVE_CONFIG_start_index = lines.index(self.SAVE_CONFIG_HEADER) if self.SAVE_CONFIG_HEADER in lines else len(lines)
        
        current_section = None
        for i, line in enumerate(lines[:SAVE_CONFIG_start_index]):
            line = line.strip()
            if line.startswith("["):
                current_section = line.strip('[]')  # Extract the section name
            elif current_section and '=' in line:
                key, value = line.split('=', 1)
                key = key.strip()
                # Check if the current section and key are in SAVE_CONFIG data
                if (current_section in self.SAVE_CONFIG_data and 
                        key in self.SAVE_CONFIG_data[current_section] and
                        self.SAVE_CONFIG_data[current_section][key] != value.strip()):
                    lines[i] = f"# {line}"  # Comment out the line

        # Reconstruct the config data, including the unchanged SAVE_CONFIG section
        return '\n'.join(lines)

    def process_config_file(self, filename):
        data = self._read_config_file(filename)
        self._find_SAVE_CONFIG_data(data)
        processed_data = self._process_config_data(data)
        return processed_data

if __name__ == '__main__':
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    try:
        os.remove(os.path.join(script_dir, 'output.cfg'))
    except OSError:
        pass  # File does not exist, no action is needed

    printer_model = argv[1]
    current = argv[2] if len(argv) > 2 else None
    generate_conf(printer_model, current)
