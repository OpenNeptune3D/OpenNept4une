import serial
import time
import moonrakerpy as moonpy

from response_actions import response_actions

class NavigationController:
    def __init__(self, printer):
        self.history = ["page 1"]  # Start with the main page
        self.printer = printer

    def go_to_page(self, action):
        if action.startswith("printer.send_gcode"):
            gcode = action.split("'")[1]  # Extract G-code from the action string
            self.printer.send_gcode(gcode)
        elif action == "go_back":
            self.go_back()
        else:
            self.history.append(action)
            self.change_display(action)

    def go_back(self):
        if len(self.history) > 1:
            self.history.pop()  # Remove current page
            back_page = self.history[-1]
            self.change_display(back_page)  # Go to the previous page
        else:
            print("Already at the main page.")

    def change_display(self, page):
        padding = [0xFF, 0xFF, 0xFF]
        ser.write(str.encode(page))
        ser.write(serial.to_bytes(padding))
        print(f"Navigating to {page}")

def handle_response(readData):
    action = response_actions.get(tuple(readData))
    if action:
        if "printer.send_gcode" in action:
            nav_controller.go_to_page(action)
        else:
            nav_controller.go_to_page(action)
    else:
        # Handle wildcard pattern
        if readData[0] == '65' and readData[2] == '00' and readData[3:] == ['ff', 'ff', 'ff']:
            nav_controller.go_to_page("go_back")
        else:
            print("No action for response:", readData)

printer = moonpy.MoonrakerPrinter('http://127.0.0.1')

SERIALPORT = "/dev/ttyS1"
BAUDRATE = 115200

ser = serial.Serial(SERIALPORT, BAUDRATE)
ser.bytesize = serial.EIGHTBITS  # number of bits per bytes
ser.parity = serial.PARITY_NONE  # set parity check: no parity
ser.stopbits = serial.STOPBITS_ONE  # number of stop bits
ser.timeout = 2  # timeout block read
ser.xonxoff = False  # disable software flow control
ser.rtscts = False  # disable hardware (RTS/CTS) flow control
ser.dsrdtr = False  # disable hardware (DSR/DTR) flow control
ser.writeTimeout = 0  # timeout for write

nav_controller = NavigationController(printer)

print('Starting Up...')

try:
    ser.close()
    ser.open()
except Exception as e:
    print("Error open serial port: " + str(e))
    exit()

if ser.isOpen():
    try:
        ser.flushInput()  # flush input buffer, discarding all its contents
        ser.flushOutput()  # flush output buffer, aborting current output
        nav_controller.go_to_page("page 1")

        while True:
            print("Waiting for user interaction from Display (Ctrl-C for skip)")
            readData = []
            try:
                while True:
                    response = ser.read()
                    if response:
                        readData.append(response.hex())
                    if len(readData) == 6:
                        print("Data read from Display: ")
                        print(readData)
                        handle_response(readData)
                        break
                    else:
                        time.sleep(0.2)

            except KeyboardInterrupt:
                print("\nInsert command (page 1, page 2, ...) for Elegoo Display: (Ctrl-C for exit)")
                data = input()
                nav_controller.go_to_page(data)
    except Exception as e:
        print("Error communicating...: " + str(e))
    finally:
        ser.close()
else:
    print("Cannot open serial port!")
