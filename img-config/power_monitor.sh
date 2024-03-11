#!/bin/bash

# Enable / Charge SuperCapacitor
gpioset gpiochip1 21=1

# Monitor GPIO line 10 for changes
gpiomon --num-events=1 --rising-edge gpiochip1 10
echo "POWER-CUT!"

# Then, initiate a safe shutdown
sudo poweroff
