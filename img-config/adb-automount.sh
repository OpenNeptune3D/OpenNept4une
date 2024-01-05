#!/bin/bash

echo "Please connect your Android device with USB debugging enabled and press Enter."
read -p ""

echo "Listing USB devices..."
lsusb

echo "Please enter the Bus and Device number of your Android device (e.g., 'Bus 002 Device 003')."
read -p "Enter Bus and Device number: " bus device

# Extract vendor and product IDs
vendor_id=$(lsusb -s $bus:$device -v | grep idVendor | awk '{print $2}')
product_id=$(lsusb -s $bus:$device -v | grep idProduct | awk '{print $2}')

echo "Vendor ID: $vendor_id, Product ID: $product_id"

# Create udev rule
rule="SUBSYSTEM==\"usb\", ATTR{idVendor}==\"$vendor_id\", ATTR{idProduct}==\"$product_id\", MODE=\"0666\", GROUP=\"plugdev\""
echo $rule | sudo tee /etc/udev/rules.d/51-android.rules

echo "udev rule created. You may need to restart your system or reload udev rules."
