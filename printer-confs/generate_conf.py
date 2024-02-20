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
            base_conf = base_conf.replace('{{ ' + split[0] + ' }}', split[1].strip())

    section_files = os.listdir(os.path.join(script_dir, printer_model))  # Use script_dir to list section files
    for section_file in section_files:
        if section_file.startswith('section_') and section_file.endswith('.cfg'):
            section_name = section_file.replace('section_', '').replace('.cfg', '')
            section_conf = open(os.path.join(script_dir, printer_model, section_file), 'r').read()
            base_conf = base_conf.replace('{{ ' + section_name + ' }}', section_conf.strip())

    result = re.findall(variable_regex, base_conf)
    if len(result) > 0:
        print("ERROR: Some variables were not replaced")
        for group in result:
            print("    " + group)
        return
    with open(os.path.join(script_dir, 'output.cfg'), 'w') as output:  # Save output.cfg in the script's directory
        output.write(base_conf)
    print("Config generated at " + os.path.join(script_dir, 'output.cfg'))

if __name__ == '__main__':
    script_dir = os.path.dirname(os.path.abspath(__file__))  # Get the directory where the script is located
    printer_model = argv[1]
    current = argv[2] if len(argv) > 2 else None
    generate_conf(printer_model, current)
