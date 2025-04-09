#!/usr/bin/env bash

# Verify that ssh config is correct before making any changes
sudo sshd -t
if [[ $? -ne 0 ]]; then
    echo "sshd configuration is found to be incorrect before run, no changes done."
    exit 1
fi

NOW=`date '+%F_%H:%M:%S'`
OLD_DIR="/etc/ssh/keys_$NOW.old"

# Creating the directory to store old keys
sudo mkdir -p $OLD_DIR
# Backup old keys
sudo mv /etc/ssh/ssh_host*_key $OLD_DIR
sudo mv /etc/ssh/ssh_host*_key.pub $OLD_DIR

# This will generate new keys and place them in the default location
sudo ssh-keygen -A
sync

# Check if ssh config is correct before restarting the service
sudo sshd -t
if [[ $? -ne 0 ]]; then
    cp -R $OLD_DIR/* /etc/ssh/

    echo "sshd configuration check failed after key regeneration, we have tried to restore the old keys."
    echo "Please check the sshd configuration before rebooting the system."
    echo "Command to check the sshd configuration: sudo sshd -t"
    echo "You should have no errors."
    echo "You can find the old keys backed up in $OLD_DIR ."
    exit 1
fi

# Restarting the sshd service to apply changes
sudo systemctl restart sshd

echo "sshd key has been regenerated and service restarted, old keys are persisted in $OLD_DIR ."
echo "You may need to run 'ssh-keygen -R <hostname>' on your client machine(s) to remove the old keys from known_hosts file."
