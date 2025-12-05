#!/bin/bash

# Installation script for router configuration files
# Usage: sudo bash install.sh

set -e  # Exit on error

echo "Starting installation..."

# Get the script directory (where the git repo was cloned)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Step 1: Install version file
echo "Installing version file..."
if [ -f "$SCRIPT_DIR/version.txt" ]; then
    sudo cp "$SCRIPT_DIR/version.txt" /usr/local/bin/
    echo "Version file installed."
fi

# Step 2: Install temporal files
echo "Installing temporal files..."

# Copy temporal files to /tmp
cp -r "$SCRIPT_DIR/temporal/"* /tmp/

# Create temporal directory and move files
sudo mkdir -p /usr/local/bin/temporal

sudo mv /tmp/auto_start_backend.sh \
        /tmp/backend_stub.py \
        /tmp/cleanup_policies.sh \
        /tmp/import_hosts.sh \
        /tmp/net_policies.json \
        /tmp/policies.json \
        /tmp/Policy.py \
        /tmp/requirements.txt \
        /tmp/run_backend.bat \
        /tmp/temporal \
        /tmp/temporal_policy.py \
        /tmp/temporal_policy.state \
        /usr/local/bin/temporal/ 2>/dev/null || true

# Move optional files if they exist
[ -f /tmp/temporal-policy.log ] && sudo mv /tmp/temporal-policy.log /usr/local/bin/temporal/ || true
[ -f /tmp/temporal-policy.pid ] && sudo mv /tmp/temporal-policy.pid /usr/local/bin/temporal/ || true
[ -f /tmp/temporal-policy.service ] && sudo mv /tmp/temporal-policy.service /usr/local/bin/temporal/ || true
[ -d /tmp/__pycache__ ] && sudo mv /tmp/__pycache__ /usr/local/bin/temporal/ || true

# Set permissions
sudo chmod -R 755 /usr/local/bin/temporal/*

echo "Temporal files installed successfully."

# Step 3: Install dhcp files
echo "Installing dhcp files..."

# Copy dhcp files to /tmp
cp "$SCRIPT_DIR/dhcp/"* /tmp/

# Move dhcp files to /usr/local/bin
sudo mv /tmp/cleanup_expired_blocks.sh \
        /tmp/daqtest \
        /tmp/daqtest-static \
        /tmp/list_blocked_devices.sh \
        /tmp/remove_device_complete.sh \
        /tmp/remove_dhcp_leases_dnsmasq.sh \
        /tmp/unblock_device_auto.sh \
        /usr/local/bin/ 2>/dev/null || true

# Move optional files if they exist
[ -f /tmp/seer_leds.py ] && sudo mv /tmp/seer_leds.py /usr/local/bin/ || true
[ -f /tmp/startup-commands.sh ] && sudo mv /tmp/startup-commands.sh /usr/local/bin/ || true

# Set permissions for dhcp files
sudo chmod 755 /usr/local/bin/cleanup_expired_blocks.sh \
               /usr/local/bin/daqtest \
               /usr/local/bin/daqtest-static \
               /usr/local/bin/list_blocked_devices.sh \
               /usr/local/bin/remove_device_complete.sh \
               /usr/local/bin/remove_dhcp_leases_dnsmasq.sh \
               /usr/local/bin/unblock_device_auto.sh

# Set permissions for optional files if they exist
[ -f /usr/local/bin/seer_leds.py ] && sudo chmod 755 /usr/local/bin/seer_leds.py || true
[ -f /usr/local/bin/startup-commands.sh ] && sudo chmod 755 /usr/local/bin/startup-commands.sh || true

echo "DHCP files installed successfully."

# Step 4: Clean up - delete the cloned repository
echo ""
echo "Cleaning up cloned repository..."
cd /
sudo rm -rf "$SCRIPT_DIR"
echo "Repository deleted."

echo ""
echo "Installation completed successfully!"
echo "All files have been installed to /usr/local/bin/"
echo "The cloned repository has been removed."
