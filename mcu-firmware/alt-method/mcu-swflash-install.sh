#!/bin/bash

# Path of the script to be created
SCRIPT_PATH="/usr/local/bin/gpio_set.sh"

# Create and write the GPIO command to the script
echo -e "#!/bin/bash\n/usr/bin/gpioset -t0 -c gpiochip1 14=0; /usr/bin/gpioset -t0 -c gpiochip1 15=0; sleep 0.5; /usr/bin/gpioset -t0 -c gpiochip1 15=1" | sudo tee "$SCRIPT_PATH" >/dev/null

# Make the script executable
sudo chmod +x "$SCRIPT_PATH"

# Check if /etc/rc.local exists
RC_LOCAL="/etc/rc.local"
if [ ! -f "$RC_LOCAL" ]; then
    # Create /etc/rc.local if it doesn't exist
    echo "#!/bin/bash" | sudo tee "$RC_LOCAL" >/dev/null
    echo "exit 0" | sudo tee -a "$RC_LOCAL" >/dev/null
    sudo chmod +x "$RC_LOCAL"
fi

# Insert the script path before 'exit 0' in /etc/rc.local
sudo sed -i "/^exit 0/i $SCRIPT_PATH" "$RC_LOCAL"

echo "Setup complete."

# Prompt user for reboot
read -p "Do you want to reboot now? (y/n): " answer
case $answer in
    [Yy]* ) sudo reboot;;
    [Nn]* ) echo "Reboot cancelled.";;
    * ) echo "Please answer yes or no.";;
esac
