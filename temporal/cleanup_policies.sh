
echo "[$(date)] Cleaning up temporal policies..."
# Get all policies
POLICIES=$(curl -s http://127.0.0.1:1889 | python3 -c "import sys, json; data = json.load(sys.stdin); print(' '.join([p['destination'] for p in data.get('policies', [])]))" 2>/dev/null)

# Unblock each one
for domain in $POLICIES; do
    echo "Unblocking $domain..."
    curl -X POST http://127.0.0.1:1889 \
      -H "Content-Type: application/json" \
      -d "{\"action\":\"unblock\",\"domain\":\"$domain\"}" \
      -s > /dev/null
done

# Also clean /etc/hosts directly
sed -i '/SEER Policy/d' /etc/hosts
sed -i '/# SEER Policy/d' /etc/hosts

# Remove any blocked domains
sed -i '/facebook.com/d' /etc/hosts
sed -i '/youtube.com/d' /etc/hosts
sed -i '/spotify.com/d' /etc/hosts

echo "[$(date)] Cleanup complete"
