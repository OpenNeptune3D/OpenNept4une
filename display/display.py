import serial
import time
import moonrakerpy as moonpy
import re
import threading

from response_actions import response_actions

class NavigationController:
    def __init__(self, printer, serial_device):
        self.history = ["page 1"]
        self.printer = printer
        self.serial_device = serial_device
        self.part_light_state = False
        self.frame_light_state = False
        self.fan_state = False
        self.filament_sensor_state = False

    def start_continuous_update(self):
        def update_loop():
            time.sleep(3)
            while True:
                if self.history[-1] == "page 1":
                    self.update_if_page1(print_to_terminal=False)
                time.sleep(0.5)

        self.update_thread = threading.Thread(target=update_loop)
        self.update_thread.daemon = True
        self.update_thread.start()

    def update_if_page1(self, print_to_terminal=False):
        temps = self.printer.query_temperatures()
        extruder = temps['extruder']['temperature']
        bed = temps['heater_bed']['temperature']
        outbed = temps.get('heater_generic heater_bed_outer', {}).get('temperature', 'N/A')
        toolhead = self.printer.query_status('toolhead')
        x_pos = toolhead['position'][0]
        y_pos = toolhead['position'][1]
        z_pos = toolhead['position'][2]
        self._write(f'nozzletemp.txt="{extruder}°C"', print_to_terminal)
        self._write(f'bedtemp.txt="{bed}°C"', print_to_terminal)
        self._write(f'out_bedtemp.txt="{outbed}°C"', print_to_terminal)
        self._write(f'x_pos.txt="{x_pos}"', print_to_terminal)
        self._write(f'y_pos.txt="{y_pos}"', print_to_terminal)
        self._write(f'z_pos.txt="{z_pos}"', print_to_terminal)

    def _navigate_to_page(self, page):
        if self.history[-1] != page:
            self.history.append(page)
            self._change_display(page)
            print(f"Navigate to {page}. Current history: {self.history}")

    def printer_status(self):
        self.update_if_page1()

    def move_axis(self, axis, distance):
        self.printer.send_gcode('G91')  # Set to relative positioning
        self.printer.send_gcode(f'G1 {axis}{distance}')  # Move axis
        self.printer.send_gcode('G90')  # Set back to absolute positioning

    def execute_action(self, action):
        if action.startswith("move_"):
            parts = action.split('_')
            axis = parts[1].upper()
            distance = parts[2]
            self.move_axis(axis, distance)
        elif action == "toggle_part_light":
            self._toggle_light("Part_Light", self.part_light_state)
            self.part_light_state = not self.part_light_state
        elif action == "toggle_frame_light":
            self._toggle_light("Frame_Light", self.frame_light_state)
            self.frame_light_state = not self.frame_light_state
        elif action == "toggle_filament_sensor":
            self._toggle_filament_sensor()
        elif action == "toggle_fan_ON":
            self._toggle_fan(True)
        elif action == "toggle_fan_OFF":
            self._toggle_fan(False)
        elif action.startswith("printer.send_gcode"):
            gcode = action.split("'")[1]
            self.printer.send_gcode(gcode)
        elif action == "go_back":
            self._go_back()
        elif action.startswith("page"):
            self._navigate_to_page(action)

    def _toggle_light(self, light_name, current_state):
        new_state = not current_state
        gcode = f"{light_name}_{'ON' if new_state else 'OFF'}"
        self.printer.send_gcode(gcode)
        self._update_light_visual(light_name, new_state)

    def _update_light_visual(self, light_name, state):
        pic_value = '77' if state else '76'
        if light_name == "Part_Light":
            self._write(f'led.led1.pic={pic_value}')
        elif light_name == "Frame_Light":
            self._write(f'led.led2.pic={pic_value}')

    def _toggle_filament_sensor(self):
        new_state = not self.filament_sensor_state
        gcode = f"SET_FILAMENT_SENSOR SENSOR=fila ENABLE={'0' if new_state else '1'}"
        self.printer.send_gcode(gcode)
        self.filament_sensor_state = new_state
        self._update_filament_visual(new_state)

    def _update_filament_visual(self, state):
        filament_value = '76' if state else '77'
        self._write(f'filamentdec.pic={filament_value}')

    def _toggle_fan(self, state):
        gcode = f"M106 S{'255' if state else '0'}"
        self.printer.send_gcode(gcode)
        self.fan_state = state
        self._write(f"fanstatue.pic={'77' if state else '76'}")

    def _go_back(self):
        if len(self.history) > 1:
            self.history.pop()
            back_page = self.history[-1]
            self._change_display(back_page)
        else:
            print("Already at the main page.")

    def _change_display(self, page):
        self._write(page)

    def _write(self, data, print_to_terminal=True):
        if print_to_terminal:
            print(f"Write {data}")
        padding = [0xFF, 0xFF, 0xFF]
        self.serial_device.write(str.encode(data))
        self.serial_device.write(serial.to_bytes(padding))

def generate_key(readData):
    return ''.join(readData)

def match_key(pattern, key):
    return re.match(pattern.replace('??', '..'), key) is not None

def handle_response(readData, nav_controller):
    action_key = generate_key(readData)
    for key in response_actions.keys():
        if match_key(key, action_key):
            nav_controller.execute_action(response_actions[key])
            break
    else:
        print("No action for response:", readData)

printer = moonpy.MoonrakerPrinter('http://127.0.0.1')
ser = serial.Serial("/dev/ttyS1", 115200, timeout=2, writeTimeout=0)

nav_controller = NavigationController(printer, ser)
nav_controller.start_continuous_update()

print('Starting Up...')

try:
    ser.close()
    ser.open()

    nav_controller.execute_action("page 109")
    nav_controller.printer_status()
    nav_controller.execute_action("page 1")

    while True:
        print("Waiting for user interaction from Display (Ctrl-C to navigate)")
        readData = []
        try:
            while True:
                response = ser.read()
                if response:
                    readData.append(response.hex())
                    if len(readData) >= 6:
                        print("Data read from Display: " + ''.join(readData))
                        handle_response(readData, nav_controller)
                        break
                else:
                    time.sleep(0.2)
        except KeyboardInterrupt:
            print("\nEnter page number to navigate to (e.g., 'page 1', 'page 2', etc.): ")
            page = input().strip()
            nav_controller.execute_action(page)
except Exception as e:
    print("Error communicating...: " + str(e))
finally:
    ser.close()
