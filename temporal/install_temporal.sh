#!/usr/bin/env bash
# Install helper for temporal policy when all files are in /usr/local/bin/temporal
# Run as root (sudo)

set -euo pipefail

TEMPDIR=/usr/local/bin/temporal
UNIT_PATH=/etc/systemd/system/temporal-policy.service

echo "1) Ensuring folder exists: $TEMPDIR"
if [ ! -d "$TEMPDIR" ]; then
  echo "ERROR: $TEMPDIR does not exist. Create it and copy files there before running this script."
  exit 2
fi

echo "2) Fix ownership and make scripts executable"
chown -R root:root "$TEMPDIR"
find "$TEMPDIR" -type f -name "*.py" -exec chmod 755 {} \;
find "$TEMPDIR" -type f -name "*.sh" -exec chmod 755 {} \;

echo "3) Writing systemd unit to $UNIT_PATH"
cat > "$UNIT_PATH" <<'UNIT'
[Unit]
Description=SEER Temporal Policy Backend
After=network.target

[Service]
Type=simple
WorkingDirectory=/usr/local/bin/temporal
ExecStart=/usr/bin/python3 /usr/local/bin/temporal/temporal_policy.py
Restart=on-failure
RestartSec=5
User=root
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
UNIT

echo "4) Reloading systemd daemon"
systemctl daemon-reload

echo "5) Enabling and starting the service"
systemctl enable --now temporal-policy.service

echo "6) Status (last few lines)"
systemctl status temporal-policy.service --no-pager

echo "7) Tail logs (press Ctrl-C to stop)"
journalctl -u temporal-policy.service -f
