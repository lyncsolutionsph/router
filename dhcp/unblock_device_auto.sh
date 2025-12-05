#!/bin/bash
# unblock_device_auto.sh (HARDENED VERSION)
# Automatically unblock a device (called by timer/cron or Node-RED)
# Usage: ./unblock_device_auto.sh <mac_address> [ip_address]

MAC="$1"
IP="$2"
BLOCK_REGISTRY="/var/lib/dhcp-blocks"
LEASE_FILE="/var/lib/misc/dnsmasq.leases"

if [ -z "$MAC" ]; then
    echo "Error: MAC address required"
    echo "Usage: $0 <mac_address> [ip_address]"
    exit 1
fi

# MUST BE RUN AS ROOT
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 2
fi

# Normalize MAC
MAC_LOWER=$(echo "$MAC" | tr '[:upper:]' '[:lower:]' | tr '-' ':')

echo "========================================"
echo "Auto-unblocking device: $MAC_LOWER"
[ -n "$IP" ] && echo "IP Address: $IP"
echo "========================================"

# Remove iptables rules for MAC (if iptables exists)
if command -v iptables >/dev/null 2>&1; then
    if iptables -C FORWARD -m mac --mac-source "$MAC_LOWER" -j DROP 2>/dev/null; then
        iptables -D FORWARD -m mac --mac-source "$MAC_LOWER" -j DROP
        echo "✓ Removed FORWARD block for MAC: $MAC_LOWER"
    fi

    if iptables -C INPUT -m mac --mac-source "$MAC_LOWER" -j DROP 2>/dev/null; then
        iptables -D INPUT -m mac --mac-source "$MAC_LOWER" -j DROP
        echo "✓ Removed INPUT block for MAC: $MAC_LOWER"
    fi

    # Remove IP blocks if provided
    if [ -n "$IP" ] && [ "$IP" != "" ]; then
        if iptables -C FORWARD -s "$IP" -j DROP 2>/dev/null; then
            iptables -D FORWARD -s "$IP" -j DROP
            echo "✓ Removed FORWARD block for IP: $IP"
        fi
        
        if iptables -C INPUT -s "$IP" -j DROP 2>/dev/null; then
            iptables -D INPUT -s "$IP" -j DROP
            echo "✓ Removed INPUT block for IP: $IP"
        fi
    fi
else
    echo "! Warning: iptables command not found - skipping iptables cleanup"
fi

# Remove from block registry
if [ -f "$BLOCK_REGISTRY/$MAC_LOWER" ]; then
    rm -f "$BLOCK_REGISTRY/$MAC_LOWER"
    echo "✓ Removed from block registry: $BLOCK_REGISTRY/$MAC_LOWER"
fi

# Remove dnsmasq lease entry (forces device to get fresh DHCP lease)
if [ -f "$LEASE_FILE" ]; then
    # Count lines before removal (for logging)
    LEASE_COUNT=$(grep -ci "$MAC_LOWER" "$LEASE_FILE" 2>/dev/null || echo "0")
    
    if [ "$LEASE_COUNT" -gt 0 ]; then
        # Remove any line containing the MAC (case-insensitive)
        sed -i "/${MAC_LOWER}/Id" "$LEASE_FILE"
        echo "✓ Removed $LEASE_COUNT dnsmasq lease entry(s) for $MAC_LOWER"
    else
        echo "○ No dnsmasq lease entries found for $MAC_LOWER"
    fi
else
    echo "! Warning: dnsmasq lease file not found: $LEASE_FILE"
fi

# Clear conntrack entries for IP (if conntrack is available)
if command -v conntrack >/dev/null 2>&1 && [ -n "$IP" ]; then
    # Count existing connections (for logging)
    CONN_COUNT=$(conntrack -L 2>/dev/null | grep -c "$IP" || echo "0")
    
    if [ "$CONN_COUNT" -gt 0 ]; then
        conntrack -D -s "$IP" >/dev/null 2>&1 || true
        conntrack -D -d "$IP" >/dev/null 2>&1 || true
        echo "✓ Cleared $CONN_COUNT conntrack entry(s) for $IP"
    else
        echo "○ No active conntrack entries for $IP"
    fi
elif [ -n "$IP" ]; then
    echo "○ conntrack not available - skipping connection cleanup"
fi

# IMPORTANT: Restart dnsmasq so device can get new DHCP lease
# The lease was removed during blocking, so dnsmasq needs to refresh
echo "✓ Restarting dnsmasq to allow new DHCP leases..."
DNSMASQ_RESTARTED=0

if [ -f /etc/init.d/dnsmasq ]; then
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 && DNSMASQ_RESTARTED=1
elif systemctl list-units --type=service | grep -q dnsmasq 2>/dev/null; then
    systemctl restart dnsmasq >/dev/null 2>&1 && DNSMASQ_RESTARTED=1
fi

if [ "$DNSMASQ_RESTARTED" -eq 1 ]; then
    echo "✓ dnsmasq restarted successfully"
else
    echo "! Warning: Could not restart dnsmasq - device may not get new lease"
fi

# Log to syslog for audit trail
logger -t unblock_device_auto "Unblocked device $MAC_LOWER (IP: ${IP:-unknown}) - manual or scheduled unblock"

echo ""
echo "✓ Device $MAC_LOWER fully unblocked"
echo "✓ Device can now reconnect and get new DHCP lease"
echo ""
echo "On the device:"
echo "  1. Forget/disconnect from Wi-Fi"
echo "  2. Reconnect to Wi-Fi"
echo "  3. Should get new IP and internet access"
echo ""

exit 0
