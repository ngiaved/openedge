#!/bin/bash
# Runs inside the appliance at boot:
#   1. edge-login.sh    - register/log in the device with its management platform
#   2. runmeonboot      - user-provided script run on every boot
#   3. docker-compose   - fetch docker-compose.yml from the preconfigured source and start the stack
# No remote access required. All artifacts land in /opt/openedge with standard names.
set -eu

ROOT="${OPENEDGE_ROOT:-/opt/openedge}"
cd "$ROOT"

. "$ROOT/bootstrap.conf"

EDGE_FETCH_RETRIES="${EDGE_FETCH_RETRIES:-5}"
EDGE_FETCH_DELAY="${EDGE_FETCH_DELAY:-15}"

await_docker() {
  for _ in $(seq 1 20); do
    docker info >/dev/null 2>&1 && return 0
    sleep 5
  done
  echo "docker did not become ready" >&2
  return 1
}

# Fetch a URL into a temp file; caller moves it into place.
fetch_url() {
  local url="$1"
  [ -n "$url" ] || { echo "empty URL" >&2; return 1; }
  curl -fsSL --connect-timeout 20 "$url" -o "/tmp/openedge-fetch.$$"
}

# Download a remote script to a standard path and execute it. Non-fatal: a bad
# script must not stop the compose bring-up.
run_remote_script() {
  local url="$1" dest="$2" label="$3"
  if fetch_url "$url"; then
    mv -f "/tmp/openedge-fetch.$$" "$dest"
    chmod 0755 "$dest"
    echo "openedge: running $label"
    "$dest"
  else
    echo "openedge: failed to fetch $label from $url" >&2
    return 1
  fi
}

await_docker

# Device registration / login. Runs first so the platform knows this edge.
if [ -n "${EDGE_LOGIN_URL:-}" ]; then
  run_remote_script "$EDGE_LOGIN_URL" "$ROOT/edge-login.sh" "edge-login" \
    || echo "openedge: edge-login step failed; continuing" >&2
fi

# User boot script (standard name runmeonboot).
if [ -n "${EDGE_BOOT_SCRIPT_URL:-}" ]; then
  run_remote_script "$EDGE_BOOT_SCRIPT_URL" "$ROOT/runmeonboot" "runmeonboot" \
    || echo "openedge: runmeonboot step failed; continuing" >&2
fi

# Nothing to do if no compose source was configured at build time.
compose_configured=false
case "$EDGE_COMPOSE_SOURCE" in
  http)
    [ -n "$EDGE_COMPOSE_URL" ] && compose_configured=true
    ;;
  s3 | gcs)
    [ -n "$EDGE_COMPOSE_BUCKET" ] && [ -n "$EDGE_COMPOSE_OBJECT" ] && compose_configured=true
    ;;
esac

if [ "$compose_configured" = true ]; then
  fetch_compose() {
    case "$EDGE_COMPOSE_SOURCE" in
      http)
        [ -n "$EDGE_COMPOSE_URL" ] || { echo "EDGE_COMPOSE_URL is empty" >&2; return 1; }
        curl -fsSL --connect-timeout 20 "$EDGE_COMPOSE_URL" -o docker-compose.yml
        ;;
      s3)
        [ -n "$EDGE_COMPOSE_BUCKET" ] && [ -n "$EDGE_COMPOSE_OBJECT" ] || { echo "bucket/object is empty" >&2; return 1; }
        if [ -f "$ROOT/cloud-creds.conf" ]; then
          AWS_ACCESS_KEY_ID="$(awk -F: 'NR==1{print $1}' "$ROOT/cloud-creds.conf")"
          AWS_SECRET_ACCESS_KEY="$(awk -F: 'NR==1{print $2}' "$ROOT/cloud-creds.conf")"
          export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
        fi
        [ -n "$EDGE_S3_REGION" ] && export AWS_DEFAULT_REGION="$EDGE_S3_REGION"
        aws s3 cp "s3://$EDGE_COMPOSE_BUCKET/$EDGE_COMPOSE_OBJECT" docker-compose.yml
        ;;
      gcs)
        [ -n "$EDGE_COMPOSE_BUCKET" ] && [ -n "$EDGE_COMPOSE_OBJECT" ] || { echo "bucket/object is empty" >&2; return 1; }
        [ -f "$ROOT/cloud-creds.conf" ] && export GOOGLE_APPLICATION_CREDENTIALS="$ROOT/cloud-creds.conf"
        gsutil -q cp "gs://$EDGE_COMPOSE_BUCKET/$EDGE_COMPOSE_OBJECT" docker-compose.yml
        ;;
      *)
        echo "unknown EDGE_COMPOSE_SOURCE: $EDGE_COMPOSE_SOURCE" >&2
        return 1
        ;;
    esac
  }

  i=1
  while [ "$i" -le "$EDGE_FETCH_RETRIES" ]; do
    if fetch_compose; then
      break
    fi
    echo "compose fetch attempt $i/$EDGE_FETCH_RETRIES failed" >&2
    [ "$i" -lt "$EDGE_FETCH_RETRIES" ] && sleep "$EDGE_FETCH_DELAY"
    i=$((i + 1))
  done

  [ -s docker-compose.yml ] || { echo "no docker-compose.yml available; aborting" >&2; exit 1; }

  # Space-separated list of services; empty means "all services".
  services=()
  if [ -n "${EDGE_COMPOSE_SERVICES:-}" ]; then
    read -r -a services <<< "$EDGE_COMPOSE_SERVICES"
  fi
  project_args=()
  if [ -n "${EDGE_COMPOSE_PROJECT:-}" ]; then
    project_args=(-p "$EDGE_COMPOSE_PROJECT")
  fi

  docker compose "${project_args[@]+"${project_args[@]}"}" up -d --remove-orphans \
    "${services[@]+"${services[@]}"}"
  echo "openedge stack is up"
else
  echo "openedge: no compose source configured; boot scripts completed"
fi