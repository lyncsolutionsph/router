#!/bin/bash

echo "Importing blocked sites from /etc/hosts to backend..."

# Get list of blocked domains from /etc/hosts
DOMAINS=$(sudo grep "127.0.0.1" /etc/hosts | grep -v "localhost" | grep -v "^#" | awk '{print $2}' | grep -v "^www\." | sort -u)

for domain in $DOMAINS; do
    # Skip if empty
    [ -z "$domain" ] && continue
    
    echo "Adding $domain to backend..."
    
    # Send to backend
    curl -X POST http://127.0.0.1:1889 \
      -H "Content-Type: application/json" \
      -d "{\"action\":\"block\",\"domain\":\"$domain\",\"schedule\":{\"start\":\"00:00\",\"end\":\"23:59\"}}" \
      -s > /dev/null
done

echo "Done! Checking policies..."
curl http://127.0.0.1:1889 | python3 -m json.tool
