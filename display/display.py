#!/usr/bin/env python

import serial, time


SERIALPORT = "/dev/ttyS1"
BAUDRATE = 115200

ser = serial.Serial(SERIALPORT, BAUDRATE)

ser.bytesize = serial.EIGHTBITS #number of bits per bytes
ser.parity = serial.PARITY_NONE #set parity check: no parity
ser.stopbits = serial.STOPBITS_ONE #number of stop bits
#ser.timeout = None          #block read
#ser.timeout = 0             #non-block read
ser.timeout = 2              #timeout block read
ser.xonxoff = False     #disable software flow control
ser.rtscts = False     #disable hardware (RTS/CTS) flow control
ser.dsrdtr = False       #disable hardware (DSR/DTR) flow control
ser.writeTimeout = 0     #timeout for write

print('Starting Up...')

try:
    ser.close()
    ser.open()

except Exception as e:
    print ("Error open serial port: " + str(e))
    exit()

if ser.isOpen():

    try:
        ser.flushInput() #flush input buffer, discarding all its contents
        ser.flushOutput() #flush output buffer, aborting current output

        while True:
            print("Insert command (page 1, page 2, ...) for Elegoo Display: (Ctrl-C for exit)")
            data = input()
            padding = [0xFF, 0xFF, 0xFF]
            ser.write(str.encode(data))
            ser.write(serial.to_bytes(padding))
            print("Write data: " + data)
            time.sleep(0.1)

            print("Waiting for user interaction from Display (Ctrl-C for skip)")
            readData = []
            try:
                while True:
                    response = ser.read()
                    if response is not None and len(response) > 0:
                        readData.append(response.hex())
                    if len(readData) == 6:
                        print("Data read from Display: ")
                        print(readData)
                        break
                    else:
                        time.sleep(0.2)
            except KeyboardInterrupt:
                print("\n")

    except Exception as e:
        print("Error communicating...: " + str(e))
    finally:
        ser.close()

else:
    print("Cannot open serial port!")
