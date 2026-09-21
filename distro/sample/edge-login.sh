#!/bin/bash
# Sample edge-login (device registration) script for the openedge appliance.
#
# Runs at every boot, before runmeonboot, so the management platform knows the
# device before the workload starts. Replace the body with your platform's
# registration/login API call (OAuth client credentials, mTLS handshake,
# POST /devices ...). Keep it idempotent - it runs every boot.
set -eu

ID_FILE=/opt/openedge/device.id

if [ ! -f "$ID_FILE" ]; then
  DEVICE_ID="edge-$(cat /etc/machine-id 2>/dev/null || hostname)"
  echo "$DEVICE_ID" > "$ID_FILE"
  chmod 0600 "$ID_FILE"
  echo "[edge-login] registered new device $DEVICE_ID"
else
  echo "[edge-login] device already registered: $(cat "$ID_FILE")"
fi

log_dir=/var/log/openedge
mkdir -p "$log_dir"
echo "$(date -u +%FT%TZ) heartbeat" >> "$log_dir/edge-login.log"