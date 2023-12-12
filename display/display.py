#!/usr/bin/env python

import serial
import time
import sys

def open_serial_port(port, baudrate):
    try:
        ser = serial.Serial(port, baudrate, timeout=2, writeTimeout=0)
        ser.bytesize = serial.EIGHTBITS
        ser.parity = serial.PARITY_NONE
        ser.stopbits = serial.STOPBITS_ONE
        ser.xonxoff = False
        ser.rtscts = False
        ser.dsrdtr = False
        return ser
    except serial.SerialException as e:
        print(f"Error opening serial port {port}: {e}")
        sys.exit(1)

def main():
    SERIALPORT = "/dev/ttyS1"
    BAUDRATE = 115200

    with open_serial_port(SERIALPORT, BAUDRATE) as ser:
        print('Starting Up...')
        ser.flushInput()
        ser.flushOutput()

        try:
            while True:
                command = input("Insert command for Elegoo Display (Ctrl-C to exit): ")
                padding = [0xFF, 0xFF, 0xFF]
                ser.write(command.encode() + serial.to_bytes(padding))
                print(f"Write data: {command}")

                time.sleep(0.1)
                print("Waiting for response from Display (Ctrl-C to skip)")
                readData = []

                try:
                    while True:
                        response = ser.read()
                        if response:
                            readData.append(response.hex())
                        if len(readData) == 6:
                            print("Data read from Display: ", readData)
                            break
                        else:
                            time.sleep(0.2)
                except KeyboardInterrupt:
                    print("\n")

        except Exception as e:
            print(f"Error communicating: {e}")
        finally:
            print("Closing serial port.")

if __name__ == "__main__":
    main()
