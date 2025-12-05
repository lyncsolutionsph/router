
#!/bin/bash
# cleanup_expired_blocks.sh
# Check for expired blocks and unblock them
# Run this via cron every minute: * * * * * /usr/local/bin/cleanup_expired_blocks.sh

BLOCK_REGISTRY="/var/lib/dhcp-blocks"
LOG_FILE="/var/log/dhcp-blocks.log"
NOW=$(date +%s)

# Check if registry exists
if [ ! -d "$BLOCK_REGISTRY" ]; then
    exit 0
fi

# Process each block file
for BLOCK_FILE in "$BLOCK_REGISTRY"/*; do
    # Skip if no files
    [ -e "$BLOCK_FILE" ] || continue
    
    # Get just the filename (MAC address)
    FILENAME=$(basename "$BLOCK_FILE")
    
    # Read block info
    BLOCK_INFO=$(cat "$BLOCK_FILE" 2>/dev/null)
    
    if [ -n "$BLOCK_INFO" ]; then
        UNBLOCK_TIME=$(echo "$BLOCK_INFO" | cut -d'|' -f1)
        MAC=$(echo "$BLOCK_INFO" | cut -d'|' -f2)
        IP=$(echo "$BLOCK_INFO" | cut -d'|' -f3)
        
        # Debug logging
        echo "[$(date)] Checking $MAC: expires at $(date -d "@$UNBLOCK_TIME" 2>/dev/null || echo $UNBLOCK_TIME), now is $NOW" >> "$LOG_FILE"
        
        # Check if expired
        if [ "$NOW" -ge "$UNBLOCK_TIME" ]; then
            echo "[$(date)] Unblocking expired block: $MAC (IP: $IP)" | tee -a "$LOG_FILE"
            /usr/local/bin/unblock_device_auto.sh "$MAC" "$IP" >> "$LOG_FILE" 2>&1
        else
            REMAINING=$((UNBLOCK_TIME - NOW))
            echo "[$(date)] $MAC still blocked for $REMAINING more seconds" >> "$LOG_FILE"
        fi
    fi
done

