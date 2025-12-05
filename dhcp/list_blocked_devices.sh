
#!/bin/bash
# list_blocked_devices.sh
# Returns JSON array of blocked devices for Node-RED

BLOCK_REGISTRY="/var/lib/dhcp-blocks"
LEASE_FILE="/var/lib/misc/dnsmasq.leases"

echo "["

first=true
for file in "$BLOCK_REGISTRY"/*; do
    [ -f "$file" ] || continue
    
    # Read registry file - supports both old format (timestamp|mac|ip) and new format (timestamp|mac|ip|hostname)
    line=$(cat "$file")
    IFS='|' read -r expires mac ip hostname <<< "$line"
    
    # Check if expired
    now=$(date +%s)
    if [ "$expires" -le "$now" ]; then
        rm -f "$file"
        continue
    fi
    
    # If hostname wasn't in registry (old format), try to get from leases as fallback
    if [ -z "$hostname" ] || [ "$hostname" = "" ]; then
        hostname=$(grep -i "$mac" "$LEASE_FILE" 2>/dev/null | awk '{print $4}' | head -1)
    fi
    
    # Default to Unknown if still empty
    [ -z "$hostname" ] && hostname="Unknown"
    [ "$hostname" = "*" ] && hostname="Unknown"
    
    # Output JSON
    [ "$first" = false ] && echo ","
    first=false
    
    echo "  {"
    echo "    \"mac\": \"$mac\","
    echo "    \"ip\": \"${ip:-—}\","
    echo "    \"hostname\": \"$hostname\","
    echo "    \"expires\": $expires"
    echo "  }"
done

echo ""
echo "]"
