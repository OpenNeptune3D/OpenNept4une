from sys import argv
import re
import os

variable_regex = re.compile(r'{{\s*(\w+)\s*}}')

def get_printer_conf(printer_model, current):
    folder = os.path.join(script_dir, printer_model) + '/'  # Use script_dir to construct the folder path
    if current is not None:
        printer_conf = open(os.path.join(folder, printer_model + '.cfg'), 'r').readlines()
        printer_conf += open(os.path.join(folder, current + '.cfg'), 'r').readlines()
        return printer_conf
    else:
        return open(os.path.join(folder, printer_model + '.cfg'), 'r').readlines()

def generate_conf(printer_model, current):
    print("Generating config for " + printer_model + ("" if current is None else " with current " + current))
    base_conf_path = os.path.join(script_dir, 'base.cfg')  # Construct the path to base.cfg
    base_conf = open(base_conf_path, 'r').read()
    printer_conf = get_printer_conf(printer_model, current)
    for line in printer_conf:
        split = line.split('=')
        if len(split) > 1:
            key, value = split[0].strip(), split[1].strip()
            # Convert "\n" sequence in value to actual newline character
            value = value.replace('\\n', '\n')
            # Replace the placeholder in base_conf with the modified value
            base_conf = base_conf.replace('{{ ' + key + ' }}', value)

    section_files = os.listdir(os.path.join(script_dir, printer_model))  # Use script_dir to list section files
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

    # Remove any unreplaced placeholders
    unreplaced = variable_regex.findall(base_conf)
    for placeholder in unreplaced:
        base_conf = base_conf.replace('{{ ' + placeholder + ' }}', '')

    with open(os.path.join(script_dir, 'output.cfg'), 'w') as output:  # Save output.cfg in the script's directory
        output.write(base_conf)
    print("Config generated at " + os.path.join(script_dir, 'output.cfg'))

if __name__ == '__main__':
    script_dir = os.path.dirname(os.path.abspath(__file__))  # Get the directory where the script is located
    printer_model = argv[1]
    current = argv[2] if len(argv) > 2 else None
    generate_conf(printer_model, current)
