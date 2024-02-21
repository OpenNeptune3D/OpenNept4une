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
        base_conf = base_conf.replace('{{ ' + placeholder + ' }}', '')

    # Write the base configuration to output.cfg
    with open(os.path.join(script_dir, 'output.cfg'), 'w') as output:
        output.write(base_conf)

    # Now append the printer section
    append_printer_section(os.path.join(os.path.expanduser('~/printer_data/config'), 'printer.cfg'))


def append_printer_section(printer_cfg_path):
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

    # Comment out 'z_offset = ' line in output.cfg
    output_cfg_path = os.path.join(script_dir, 'output.cfg')
    with open(output_cfg_path, 'r') as file:
        output_lines = file.readlines()

    with open(output_cfg_path, 'w') as file:
        for line in output_lines:
            if line.strip().startswith('z_offset ='):
                file.write('#' + line)  # Comment out the line
            else:
                file.write(line)

    # Append the collected section
    with open(output_cfg_path, 'a') as output:
        output.write('\n' + '\n'.join(section))
        print("Printer section appended to " + os.path.join(script_dir, 'output.cfg'))


if __name__ == '__main__':
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    try:
        os.remove(os.path.join(script_dir, 'output.cfg'))
    except OSError:
        pass  # File does not exist, no action is needed

    printer_model = argv[1]
    current = argv[2] if len(argv) > 2 else None
    generate_conf(printer_model, current)
