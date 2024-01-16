#!/bin/bash

sudo apt-get install -y android-sdk-platform-tools-common && sudo cp /lib/udev/rules.d/51-android.rules /etc/udev/rules.d/

echo "udev rule created. You may need to restart your system or reload udev rules."
