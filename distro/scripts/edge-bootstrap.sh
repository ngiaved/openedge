#!/bin/bash -eux

# Values below come from the preconfigure menu via the packer user variables
# (see preconfigure/preconfigure.sh and the "variables" block of ubuntu1804.json).
EDGE_COMPOSE_SOURCE="${EDGE_COMPOSE_SOURCE:-http}"

mkdir -p /opt/openedge

# Bootstrap configuration read by /opt/openedge/openedge-bootstrap.sh at boot.
cat > /opt/openedge/bootstrap.conf <<EOF
EDGE_COMPOSE_SOURCE="${EDGE_COMPOSE_SOURCE:-http}"
EDGE_COMPOSE_URL="${EDGE_COMPOSE_URL:-}"
EDGE_COMPOSE_BUCKET="${EDGE_COMPOSE_BUCKET:-}"
EDGE_COMPOSE_OBJECT="${EDGE_COMPOSE_OBJECT:-}"
EDGE_COMPOSE_PROJECT="${EDGE_COMPOSE_PROJECT:-}"
EDGE_COMPOSE_SERVICES="${EDGE_COMPOSE_SERVICES:-}"
EDGE_FETCH_RETRIES="${EDGE_FETCH_RETRIES:-5}"
EDGE_FETCH_DELAY="${EDGE_FETCH_DELAY:-15}"
EDGE_S3_REGION="${EDGE_S3_REGION:-}"
EDGE_NET_MODE="${EDGE_NET_MODE:-dhcp}"
EDGE_BOOT_SCRIPT_URL="${EDGE_BOOT_SCRIPT_URL:-}"
EDGE_LOGIN_URL="${EDGE_LOGIN_URL:-}"
EOF
chmod 0600 /opt/openedge/bootstrap.conf

# Container environment overrides; docker compose interpolates this .env file.
if [ -n "${EDGE_COMPOSE_ENV_B64:-}" ]; then
  echo "${EDGE_COMPOSE_ENV_B64}" | base64 -d > /opt/openedge/.env
  chmod 0600 /opt/openedge/.env
fi

# Cloud credentials: S3 "ACCESS_KEY:SECRET" or a GCS service-account JSON.
if [ -n "${EDGE_CLOUD_CREDENTIALS_B64:-}" ]; then
  echo "${EDGE_CLOUD_CREDENTIALS_B64}" | base64 -d > /opt/openedge/cloud-creds.conf
  chmod 0600 /opt/openedge/cloud-creds.conf
fi

# Install only the fetch tool the configured source needs.
case "$EDGE_COMPOSE_SOURCE" in
  s3)
    apt-get -y install awscli
    ;;
  gcs)
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
      > /etc/apt/sources.list.d/google-cloud-sdk.list
    apt-get -y update
    apt-get -y install google-cloud-sdk
    ;;
  http)
    # curl is already installed as part of the Docker provisioning step.
    ;;
  *)
    echo "unknown EDGE_COMPOSE_SOURCE: $EDGE_COMPOSE_SOURCE" >&2
    exit 1
    ;;
esac

# Install the boot-time bootstrap script and systemd unit.
install -m 0755 /tmp/openedge-bootstrap.sh /opt/openedge/openedge-bootstrap.sh
install -m 0644 /tmp/openedge-bootstrap.service /etc/systemd/system/openedge-bootstrap.service
systemctl daemon-reload

# --- static network configuration -------------------------------------------
# When a static configuration was chosen, bake a netplan for the first ethernet
# interface and install the unit that applies it early at boot. The netmask is
# converted to an equivalent CIDR prefix; DNS is a space-separated list.
netmask_to_cidr() {
  local mask="$1" n=0 o1 o2 o3 o4 oct
  IFS=. read -r o1 o2 o3 o4 <<< "$mask"
  for oct in "$o1" "$o2" "$o3" "$o4"; do
    case "$oct" in
      255) n=$((n + 8)) ;;
      254) n=$((n + 7)) ;;
      252) n=$((n + 6)) ;;
      248) n=$((n + 5)) ;;
      240) n=$((n + 4)) ;;
      224) n=$((n + 3)) ;;
      192) n=$((n + 2)) ;;
      128) n=$((n + 1)) ;;
      0) ;;
      *) return 1 ;;
    esac
  done
  echo "$n"
}

if [ "${EDGE_NET_MODE:-dhcp}" = "static" ]; then
  if [ -n "${EDGE_NET_ADDRESS:-}" ] && [ -n "${EDGE_NET_NETMASK:-}" ]; then
    CIDR="$(netmask_to_cidr "$EDGE_NET_NETMASK")" || {
      echo "openedge: invalid netmask '$EDGE_NET_NETMASK'; keeping DHCP" >&2
      EDGE_NET_MODE=dhcp
    }
  else
    echo "openedge: static mode but address/netmask missing; keeping DHCP" >&2
    EDGE_NET_MODE=dhcp
  fi
fi

if [ "$EDGE_NET_MODE" = "static" ]; then
  IFACE="$(ls /sys/class/net | grep -E '^(en|eth)' | head -n1 | tr -d '\n')"
  [ -n "$IFACE" ] || IFACE="ens3"
  {
    echo "network:"
    echo "  version: 2"
    echo "  renderer: networkd"
    echo "  ethernets:"
    echo "    ${IFACE}:"
    echo "      dhcp4: false"
    echo "      addresses:"
    echo "        - ${EDGE_NET_ADDRESS}/${CIDR}"
    if [ -n "${EDGE_NET_GATEWAY:-}" ]; then
      echo "      gateway4: ${EDGE_NET_GATEWAY}"
    fi
    if [ -n "${EDGE_NET_DNS:-}" ]; then
      echo "      nameservers:"
      echo "        addresses:"
      for d in $EDGE_NET_DNS; do
        echo "          - ${d}"
      done
    fi
  } > /etc/netplan/50-openedge.yaml
  chmod 0600 /etc/netplan/50-openedge.yaml
  netplan generate
  install -m 0755 /tmp/configure-network.sh /opt/openedge/configure-network.sh
  install -m 0644 /tmp/configure-network.service /etc/systemd/system/configure-network.service
  systemctl daemon-reload
  systemctl enable configure-network.service
  echo "openedge: static network configured on ${IFACE} (${EDGE_NET_ADDRESS}/${CIDR})"
else
  echo "openedge: keeping docker default (DHCP) network"
fi

# Only enable the boot service when something was actually configured.
EDGE_CONFIGURED=false
case "$EDGE_COMPOSE_SOURCE" in
  http)
    [ -n "${EDGE_COMPOSE_URL:-}" ] && EDGE_CONFIGURED=true
    ;;
  s3 | gcs)
    [ -n "${EDGE_COMPOSE_BUCKET:-}" ] && [ -n "${EDGE_COMPOSE_OBJECT:-}" ] && EDGE_CONFIGURED=true
    ;;
esac
[ -n "${EDGE_BOOT_SCRIPT_URL:-}" ] && EDGE_CONFIGURED=true
[ -n "${EDGE_LOGIN_URL:-}" ] && EDGE_CONFIGURED=true

if [ "$EDGE_CONFIGURED" = true ]; then
  systemctl enable openedge-bootstrap.service
else
  echo "openedge: no compose source, boot script or login URL configured; boot service left disabled"
fi

sync
