
#!/bin/bash
# remove_dhcp_leases_dnsmasq.sh
# Remove DHCP leases from dnsmasq and restart service
# Usage: ./remove_dhcp_leases_dnsmasq.sh <mac1> [mac2] [mac3] ...

set -e

LEASE_FILE="/var/lib/misc/dnsmasq.leases"
BACKUP_DIR="/var/backups/dhcp"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Backup current lease file
BACKUP_FILE="${BACKUP_DIR}/dnsmasq.leases.backup.$(date +%Y%m%d_%H%M%S)"
cp "$LEASE_FILE" "$BACKUP_FILE"
echo "Backed up leases to: $BACKUP_FILE"

# Remove leases for each MAC address
for mac in "$@"; do
    # Normalize to lowercase
    mac_lower=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
    
    # Count matching leases before removal
    count=$(grep -ci "$mac_lower" "$LEASE_FILE" || true)
    
    if [ "$count" -gt 0 ]; then
        # Remove matching lines (case-insensitive)
        sed -i "/${mac_lower}/Id" "$LEASE_FILE"
        echo "Removed $count lease(s) for MAC: $mac_lower"
    else
        echo "No lease found for MAC: $mac_lower"
    fi
done

# Restart dnsmasq service
echo "Restarting dnsmasq service..."
if [ -f /etc/init.d/dnsmasq ]; then
    /etc/init.d/dnsmasq restart
elif systemctl list-units --type=service | grep -q dnsmasq; then
    systemctl restart dnsmasq
else
    echo "Warning: Could not find dnsmasq service to restart"
    exit 1
fi

echo "DHCP lease removal completed successfully"
