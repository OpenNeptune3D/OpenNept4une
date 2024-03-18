#!/bin/bash

# Enable / Charge SuperCapacitor
gpioset gpiochip1 21=1

# Function to handle power-cut
handle_power_cut() {
    # Then, initiate a safe shutdown
    poweroff
}

# Monitor GPIO line 10 for changes in the background
gpiomon --num-events=1 --rising-edge gpiochip1 10 &
# Monitor GPIO line 19 for changes in the background
gpiomon --num-events=1 --falling-edge gpiochip1 19 &
# Wait for any gpiomon process to exit
wait
# Call the handle function
handle_power_cut
