import serial
import time
import moonrakerpy as moonpy
import re

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

    def move_axis(self, axis, distance):
        self.printer.send_gcode('G91')  # Set to relative positioning
        self.printer.send_gcode(f'G1 {axis}{distance}')  # Move axis
        self.printer.send_gcode('G90')  # Set back to absolute positioning

    def execute_action(self, action):
        if action.startswith("move_"):
            axis = action.split('_')[1].upper()  # 'X', 'Y', or 'Z'
            distance = action.split('_')[2]  # e.g., '1mm', '-10mm'
            self.move_axis(axis, distance)
        elif action == "toggle_part_light":
            self._toggle_light("Part_Light", self.part_light_state)
            self.part_light_state = not self.part_light_state
        elif action == "toggle_frame_light":
            self._toggle_light("Frame_Light", self.frame_light_state)
            self.frame_light_state = not self.frame_light_state
        elif action == "toggle_filament_sensor":
            self._toggle_filament_sensor()
        elif action.startswith("printer.send_gcode"):
            self._send_gcode(action)
        elif action == "go_back":
            self._go_back()
        else:
            self._navigate_to_page(action)

    def _toggle_light(self, light_name, current_state):
        gcode = f"{light_name}_{'OFF' if current_state else 'ON'}"
        self.printer.send_gcode(gcode)

    def _toggle_filament_sensor(self):
        gcode = f"SET_FILAMENT_SENSOR SENSOR=fila ENABLE={'0' if self.filament_sensor_state else '1'}"
        self.printer.send_gcode(gcode)
        self.filament_sensor_state = not self.filament_sensor_state

    def _send_gcode(self, action):
        gcode = action.split("'")[1]
        self.printer.send_gcode(gcode)

    def _go_back(self):
        if len(self.history) > 1:
            self.history.pop()
            back_page = self.history[-1]
            self._change_display(back_page)
        else:
            print("Already at the main page.")

    def _navigate_to_page(self, page):
        if self.history[-1] != page:
            self.history.append(page)
        self._change_display(page)

    def _change_display(self, page):
        padding = [0xFF, 0xFF, 0xFF]
        self.serial_device.write(str.encode(page))
        self.serial_device.write(serial.to_bytes(padding))
        print(f"Navigating to {page}")


def generate_key(readData):
    return ''.join(readData)

def match_key(pattern, key):
    pattern_regex = pattern.replace('??', '..')
    return re.match(pattern_regex, key) is not None

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

print('Starting Up...')

try:
    ser.close()
    ser.open()
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
