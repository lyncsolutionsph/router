#!/bin/bash
# remove_device_complete.sh
# Remove DHCP lease AND block device with timer-based unblock
# Usage: ./remove_device_complete.sh <mac_address>

set -e

MAC="$1"
BLOCK_DURATION=120  # 10 seconds for testing (change to 86400 for 24 hours)
BLOCK_REGISTRY="/var/lib/dhcp-blocks"

if [ -z "$MAC" ]; then
    echo "Error: MAC address required"
    echo "Usage: $0 <mac_address>"
    echo "Device will be blocked for 10 seconds (testing mode)"
    echo "Edit BLOCK_DURATION=86400 in script for 24 hours"
    exit 1
fi

# Create block registry directory
mkdir -p "$BLOCK_REGISTRY"

# Normalize MAC to lowercase with colons
MAC_LOWER=$(echo "$MAC" | tr '[:upper:]' '[:lower:]' | tr '-' ':')

# SAFETY CHECK: Don't block yourself!
if [ -n "$SSH_CLIENT" ]; then
    MY_IP=$(echo "$SSH_CLIENT" | awk '{print $1}')
    
    # Check if we're about to block our own IP
    TEST_IP=$(grep -i "$MAC_LOWER" /var/lib/misc/dnsmasq.leases 2>/dev/null | awk '{print $3}' | head -1)
    
    if [ "$TEST_IP" = "$MY_IP" ]; then
        echo "========================================"
        echo "⚠️  ERROR: SELF-BLOCK PREVENTED"
        echo "========================================"
        echo ""
        echo "You are trying to block your own device!"
        echo "  Your IP: $MY_IP"
        echo "  Target MAC: $MAC_LOWER resolves to $TEST_IP"
        echo ""
        echo "This would disconnect you from the Pi."
        echo "If you really want to do this, use physical access."
        echo ""
        exit 1
    fi
fi

echo "========================================"
echo "Removing device: $MAC_LOWER"
echo "========================================"

# Configuration
LEASE_FILE="/var/lib/misc/dnsmasq.leases"
BACKUP_DIR="/var/backups/dhcp"

# Step 1: Find current IP address (before removing lease)
echo ""
echo "[1/4] Finding device IP address..."
DEVICE_IP=$(grep -i "$MAC_LOWER" "$LEASE_FILE" 2>/dev/null | awk '{print $3}' | head -1)

if [ -n "$DEVICE_IP" ]; then
    echo "✓ Found IP: $DEVICE_IP"
else
    echo "! No active lease found in DHCP"
    DEVICE_IP=""
fi

# Step 2: Block device using iptables with timer-based unblock
echo ""
echo "[2/4] Blocking device traffic..."

# Calculate unblock timestamp
UNBLOCK_TIMESTAMP=$(($(date +%s) + BLOCK_DURATION))

# Block by MAC address
iptables -C FORWARD -m mac --mac-source "$MAC_LOWER" -j DROP 2>/dev/null || \
    iptables -I FORWARD -m mac --mac-source "$MAC_LOWER" -j DROP
iptables -C INPUT -m mac --mac-source "$MAC_LOWER" -j DROP 2>/dev/null || \
    iptables -I INPUT -m mac --mac-source "$MAC_LOWER" -j DROP

echo "✓ Blocked MAC: $MAC_LOWER"

# Capture hostname BEFORE removing lease (must do this before Step 4 removes the lease!)
DEVICE_HOSTNAME=$(grep -i "$MAC_LOWER" "$LEASE_FILE" 2>/dev/null | awk '{print $4}' | head -1)
[ -z "$DEVICE_HOSTNAME" ] && DEVICE_HOSTNAME="Unknown"
[ "$DEVICE_HOSTNAME" = "*" ] && DEVICE_HOSTNAME="Unknown"

echo "✓ Captured hostname: $DEVICE_HOSTNAME"

# Register block with unblock time and hostname
# Registry format: timestamp|mac|ip|hostname
echo "$UNBLOCK_TIMESTAMP|$MAC_LOWER|$DEVICE_IP|$DEVICE_HOSTNAME" > "$BLOCK_REGISTRY/$MAC_LOWER"

# Block by IP if we found one
if [ -n "$DEVICE_IP" ]; then
    iptables -C FORWARD -s "$DEVICE_IP" -j DROP 2>/dev/null || \
        iptables -I FORWARD -s "$DEVICE_IP" -j DROP
    iptables -C INPUT -s "$DEVICE_IP" -j DROP 2>/dev/null || \
        iptables -I INPUT -s "$DEVICE_IP" -j DROP
    echo "✓ Blocked IP: $DEVICE_IP"
fi

# Schedule automatic unblock. Try `at` first; if unavailable or fails, fall back
# to a background sleep to run the unblock script after $BLOCK_DURATION seconds.
# The background-sleep approach is used for quick testing (short durations).

# Resolve the unblock command path (prefer /usr/local/bin, then scripts/)
UNBLOCK_CMD="/usr/local/bin/unblock_device_auto.sh"
if [ ! -x "$UNBLOCK_CMD" ]; then
    if [ -x "$(dirname "$0")/unblock_device_auto.sh" ]; then
        UNBLOCK_CMD="$(dirname "$0")/unblock_device_auto.sh"
    elif [ -x "$(dirname "$0")/../scripts/unblock_device_auto.sh" ]; then
        UNBLOCK_CMD="$(dirname "$0")/../scripts/unblock_device_auto.sh"
    elif command -v unblock_device_auto.sh >/dev/null 2>&1; then
        UNBLOCK_CMD="$(command -v unblock_device_auto.sh)"
    fi
fi

if command -v at >/dev/null 2>&1; then
    # Try scheduling with `at`. Note: some `at` implementations don't accept "seconds",
    # so wrap in a fallback if it fails.
    AT_JOB="/bin/sh -c '$UNBLOCK_CMD $MAC_LOWER $DEVICE_IP'"
    AT_OUTPUT=$(echo "$AT_JOB" | at now + $BLOCK_DURATION seconds 2>&1) || AT_OUTPUT="$AT_OUTPUT"
    if echo "$AT_OUTPUT" | grep -qi "job" >/dev/null 2>&1; then
        echo "✓ Scheduled auto-unblock in $BLOCK_DURATION seconds (via 'at')"
    else
        # `at` failed (maybe no seconds support) — fall back to sleep background
        echo "! 'at' scheduling failed or not supported for seconds: falling back to background sleep"
        ( sleep "$BLOCK_DURATION"; "$UNBLOCK_CMD" "$MAC_LOWER" "$DEVICE_IP" ) >/dev/null 2>&1 &
        echo "✓ Scheduled auto-unblock in $BLOCK_DURATION seconds (via background sleep)"
    fi
else
    # No `at` installed — use a background sleep (suitable for short test durations)
    echo "! 'at' command not available - using background sleep to schedule unblock"
    ( sleep "$BLOCK_DURATION"; "$UNBLOCK_CMD" "$MAC_LOWER" "$DEVICE_IP" ) >/dev/null 2>&1 &
    echo "✓ Scheduled auto-unblock in $BLOCK_DURATION seconds (via background sleep)"
fi

# Also log for debugging
echo "[$(date)] Blocked $MAC_LOWER until $(date -d "@$UNBLOCK_TIMESTAMP")" >> /var/log/dhcp-blocks.log

# Step 3: Kill existing connections
echo ""
echo "[3/4] Killing existing connections..."

if [ -n "$DEVICE_IP" ]; then
    # Find and kill all connections from this IP
    CONNECTION_COUNT=$(conntrack -L 2>/dev/null | grep -c "$DEVICE_IP" || echo "0")
    
    if [ "$CONNECTION_COUNT" -gt 0 ]; then
        conntrack -D -s "$DEVICE_IP" 2>/dev/null || echo "! conntrack not available (install conntrack-tools)"
        echo "✓ Killed $CONNECTION_COUNT active connections"
    else
        echo "○ No active connections found"
    fi
else
    echo "○ Skipped (no IP found)"
fi

# Step 4: Remove DHCP lease
echo ""
echo "[4/4] Removing DHCP lease..."

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup current lease file
BACKUP_FILE="${BACKUP_DIR}/dnsmasq.leases.backup.$(date +%Y%m%d_%H%M%S)"
cp "$LEASE_FILE" "$BACKUP_FILE"
echo "✓ Backed up to: $BACKUP_FILE"

# Remove lease entries
count=$(grep -ci "$MAC_LOWER" "$LEASE_FILE" 2>/dev/null || echo "0")

if [ "$count" -gt 0 ]; then
    sed -i "/${MAC_LOWER}/Id" "$LEASE_FILE"
    echo "✓ Removed $count lease entry(s)"
else
    echo "○ No lease entries to remove"
fi

# Restart dnsmasq
echo "✓ Restarting dnsmasq..."
if [ -f /etc/init.d/dnsmasq ]; then
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
elif systemctl list-units --type=service | grep -q dnsmasq 2>/dev/null; then
    systemctl restart dnsmasq >/dev/null 2>&1
else
    echo "! Warning: Could not restart dnsmasq"
fi

# Step 5: Calculate unblock time
UNBLOCK_TIME=$(date -d "@$UNBLOCK_TIMESTAMP" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "$UNBLOCK_TIMESTAMP" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "in $BLOCK_DURATION seconds")

echo ""
echo "========================================"
echo "✓ COMPLETE - Device blocked"
echo "========================================"
echo "MAC Address:      $MAC_LOWER"
[ -n "$DEVICE_IP" ] && echo "IP Address:       $DEVICE_IP"
echo "Status:           Connection terminated immediately"
echo "Block duration:   $BLOCK_DURATION seconds"
echo "Block expires:    $UNBLOCK_TIME"
echo "Auto-unblock:     Yes (scheduled)"
echo ""
echo "The device:"
echo "  • Cannot access network (blocked by firewall)"
echo "  • Cannot renew DHCP lease (removed from server)"
echo "  • Will automatically reconnect after $BLOCK_DURATION seconds"
echo ""
echo "To check blocked devices:"
echo "  ls -lh $BLOCK_REGISTRY/"
echo "  cat $BLOCK_REGISTRY/$MAC_LOWER"
echo ""
echo "To unblock immediately:"
echo "  /usr/local/bin/unblock_device_auto.sh $MAC_LOWER $DEVICE_IP"
echo ""
