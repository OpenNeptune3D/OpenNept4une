#!/usr/bin/env python

import serial, time
from response_actions import response_actions

class NavigationController:
    def __init__(self):
        self.history = ["page 1"]  # Start with the main page

    def go_to_page(self, page):
        if page == "go_back":
            self.go_back()
        else:
            self.history.append(page)
            self.change_display(page)

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
        nav_controller.go_to_page(action)
    else:
        # Handle wildcard pattern
        if readData[0] == '65' and readData[2] == '00' and readData[3:] == ['ff', 'ff', 'ff']:
            nav_controller.go_to_page("go_back")
        else:
            print("No action for response:", readData)

SERIALPORT = "/dev/ttyS1"
BAUDRATE = 115200

ser = serial.Serial(SERIALPORT, BAUDRATE)

ser.bytesize = serial.EIGHTBITS # number of bits per bytes
ser.parity = serial.PARITY_NONE # set parity check: no parity
ser.stopbits = serial.STOPBITS_ONE # number of stop bits
ser.timeout = 2              # timeout block read
ser.xonxoff = False     # disable software flow control
ser.rtscts = False     # disable hardware (RTS/CTS) flow control
ser.dsrdtr = False       # disable hardware (DSR/DTR) flow control
ser.writeTimeout = 0     # timeout for write

nav_controller = NavigationController()

print('Starting Up...')

try:
    ser.close()
    ser.open()

except Exception as e:
    print("Error open serial port: " + str(e))
    exit()

if ser.isOpen():
    try:
        ser.flushInput() # flush input buffer, discarding all its contents
        ser.flushOutput() # flush output buffer, aborting current output

        # Send "page 1" command as default at the start
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
