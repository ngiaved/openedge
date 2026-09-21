#!/usr/bin/env bash
# openedge preconfigure
#
# Terminal menu that bakes deployment settings into the appliance image before
# it is built. It runs entirely offline and writes the Packer variable file
# distro/openedge.auto.pkrvars.json, which is picked up automatically by
# `packer build ubuntu1804.json`.
#
# Usage:
#   ./preconfigure.sh                        interactive menu
#   ./preconfigure.sh --set url=https://...   apply values non-interactively
#   ./preconfigure.sh --save                 write state + variable file
#   ./preconfigure.sh --dump                 print the variable file to stdout
#
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISTRO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VARS_FILE="$DISTRO_DIR/openedge.auto.pkrvars.json"
STATE_FILE="$SCRIPT_DIR/.state"

# --- configuration state -----------------------------------------------------

edge_compose_source="http"
edge_compose_url=""
edge_compose_bucket=""
edge_compose_object=""
edge_compose_project=""
edge_compose_services=""
edge_fetch_retries="5"
edge_fetch_delay="15"
edge_s3_region=""
edge_compose_env=""
edge_cloud_credentials=""
edge_net_mode="dhcp"
edge_net_address=""
edge_net_netmask=""
edge_net_gateway=""
edge_net_dns=""
edge_boot_script_url=""
edge_login_url=""

defaults() {
  edge_compose_source="http"
  edge_compose_url=""
  edge_compose_bucket=""
  edge_compose_object=""
  edge_compose_project=""
  edge_compose_services=""
  edge_fetch_retries="5"
  edge_fetch_delay="15"
  edge_s3_region=""
  edge_compose_env=""
  edge_cloud_credentials=""
  edge_net_mode="dhcp"
  edge_net_address=""
  edge_net_netmask=""
  edge_net_gateway=""
  edge_net_dns=""
  edge_boot_script_url=""
  edge_login_url=""
}

b64() {
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "$1" | openssl base64 -A
  else
    printf '%s' "$1" | base64 | tr -d '\n'
  fi
}

# Load previously saved state, if any. Multiline values are stored base64-encoded.
load_state() {
  [ -f "$STATE_FILE" ] || return 0
  local line key value
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      edge_compose_source) edge_compose_source="$value" ;;
      edge_compose_url) edge_compose_url="$value" ;;
      edge_compose_bucket) edge_compose_bucket="$value" ;;
      edge_compose_object) edge_compose_object="$value" ;;
      edge_compose_project) edge_compose_project="$value" ;;
      edge_compose_services) edge_compose_services="$value" ;;
      edge_fetch_retries) edge_fetch_retries="$value" ;;
      edge_fetch_delay) edge_fetch_delay="$value" ;;
      edge_s3_region) edge_s3_region="$value" ;;
      edge_compose_env_b64) edge_compose_env="$(printf '%s' "$value" | base64 -d 2>/dev/null || true)" ;;
      edge_cloud_credentials_b64) edge_cloud_credentials="$(printf '%s' "$value" | base64 -d 2>/dev/null || true)" ;;
      edge_net_mode) edge_net_mode="$value" ;;
      edge_net_address) edge_net_address="$value" ;;
      edge_net_netmask) edge_net_netmask="$value" ;;
      edge_net_gateway) edge_net_gateway="$value" ;;
      edge_net_dns) edge_net_dns="$value" ;;
      edge_boot_script_url) edge_boot_script_url="$value" ;;
      edge_login_url) edge_login_url="$value" ;;
    esac
  done < "$STATE_FILE"
}

save_state() {
  cat > "$STATE_FILE" <<EOF
edge_compose_source=$edge_compose_source
edge_compose_url=$edge_compose_url
edge_compose_bucket=$edge_compose_bucket
edge_compose_object=$edge_compose_object
edge_compose_project=$edge_compose_project
edge_compose_services=$edge_compose_services
edge_fetch_retries=$edge_fetch_retries
edge_fetch_delay=$edge_fetch_delay
edge_s3_region=$edge_s3_region
edge_compose_env_b64=$(b64 "$edge_compose_env")
edge_cloud_credentials_b64=$(b64 "$edge_cloud_credentials")
edge_net_mode=$edge_net_mode
edge_net_address=$edge_net_address
edge_net_netmask=$edge_net_netmask
edge_net_gateway=$edge_net_gateway
edge_net_dns=$edge_net_dns
edge_boot_script_url=$edge_boot_script_url
edge_login_url=$edge_login_url
EOF
}

# --- output ------------------------------------------------------------------

json_str() {
  local out="$1"
  out="${out//\\/\\\\}"
  out="${out//\"/\\\"}"
  out="${out//$'\t'/\\t}"
  out="${out//$'\n'/\\n}"
  printf '%s' "$out"
}

emit_vars() {
  cat <<EOF
{
  "edge_compose_source": "$(json_str "$edge_compose_source")",
  "edge_compose_url": "$(json_str "$edge_compose_url")",
  "edge_compose_bucket": "$(json_str "$edge_compose_bucket")",
  "edge_compose_object": "$(json_str "$edge_compose_object")",
  "edge_compose_project": "$(json_str "$edge_compose_project")",
  "edge_compose_services": "$(json_str "$edge_compose_services")",
  "edge_fetch_retries": "$(json_str "$edge_fetch_retries")",
  "edge_fetch_delay": "$(json_str "$edge_fetch_delay")",
  "edge_s3_region": "$(json_str "$edge_s3_region")",
  "edge_compose_env_b64": "$(json_str "$(b64 "$edge_compose_env")")",
  "edge_cloud_credentials_b64": "$(json_str "$(b64 "$edge_cloud_credentials")")",
  "edge_net_mode": "$(json_str "$edge_net_mode")",
  "edge_net_address": "$(json_str "$edge_net_address")",
  "edge_net_netmask": "$(json_str "$edge_net_netmask")",
  "edge_net_gateway": "$(json_str "$edge_net_gateway")",
  "edge_net_dns": "$(json_str "$edge_net_dns")",
  "edge_boot_script_url": "$(json_str "$edge_boot_script_url")",
  "edge_login_url": "$(json_str "$edge_login_url")"
}
EOF
}

write_vars() {
  emit_vars > "$VARS_FILE"
  echo "wrote $VARS_FILE"
  echo "run 'packer build ubuntu1804.json' from distro/ to build with these settings"
}

# --- validation --------------------------------------------------------------

validation_warnings() {
  local warnings=""
  case "$edge_compose_source" in
    http)
      [ -n "$edge_compose_url" ] || warnings="${warnings}compose URL is empty"$'\n'
      ;;
    s3 | gcs)
      [ -n "$edge_compose_bucket" ] || warnings="${warnings}bucket is empty"$'\n'
      [ -n "$edge_compose_object" ] || warnings="${warnings}object path is empty"$'\n'
      ;;
    *)
      warnings="${warnings}unknown source '$edge_compose_source' (expected http, s3 or gcs)"$'\n'
      ;;
  esac
  case "$edge_fetch_retries" in
    '' | *[!0-9]*) warnings="${warnings}retries must be a number"$'\n' ;;
  esac
  case "$edge_fetch_delay" in
    '' | *[!0-9]*) warnings="${warnings}delay must be a number"$'\n' ;;
  esac
  if [ "$edge_net_mode" = "static" ]; then
    [ -n "$edge_net_address" ] || warnings="${warnings}network is static but address is empty"$'\n'
    [ -n "$edge_net_netmask" ] || warnings="${warnings}network is static but netmask is empty"$'\n'
    [ -n "$edge_net_gateway" ] || warnings="${warnings}network is static but gateway is empty"$'\n'
  elif [ "$edge_net_mode" != "dhcp" ]; then
    warnings="${warnings}unknown net mode '$edge_net_mode' (expected dhcp or static)"$'\n'
  fi
  printf '%s' "$warnings"
}

# --- interactive helpers -----------------------------------------------------

prompt_value() {
  local name="$1" label="$2" current input
  eval "current=\${$name}"
  printf '%s\n' "$label"
  [ -n "$current" ] && printf '  current: %s\n' "$current"
  printf "  new value (enter to keep, '-' to clear): "
  IFS= read -r input || true
  if [ "$input" = "-" ]; then
    eval "$name=''"
  elif [ -n "$input" ]; then
    eval "$name=\$input"
  fi
}

show_summary() {
  echo "------------------------------------------------------------"
  echo " compose source ....... $edge_compose_source"
  case "$edge_compose_source" in
    http) echo " compose url .......... ${edge_compose_url:-(unset)}" ;;
    s3)
      echo " bucket ............... ${edge_compose_bucket:-(unset)}"
      echo " object ............... ${edge_compose_object:-(unset)}"
      echo " region ............... ${edge_s3_region:-(default)}"
      ;;
    gcs)
      echo " bucket ............... ${edge_compose_bucket:-(unset)}"
      echo " object ............... ${edge_compose_object:-(unset)}"
      ;;
  esac
  echo " project name ......... ${edge_compose_project:-(default)}"
  echo " service filter ....... ${edge_compose_services:-(all)}"
  if [ -n "$edge_compose_env" ]; then
    echo " environment vars ..... $(printf '%s' "$edge_compose_env" | awk 'NF{n++} END{print n+0}') set"
  else
    echo " environment vars ..... (none)"
  fi
  if [ -n "$edge_cloud_credentials" ]; then
    echo " credentials .......... ***"
  else
    echo " credentials .......... (none)"
  fi
  echo " fetch retries/delay .. ${edge_fetch_retries} x ${edge_fetch_delay}s"
  if [ "$edge_net_mode" = "static" ]; then
    echo " network .............. static"
    echo " static ip/mask ....... ${edge_net_address:-} / ${edge_net_netmask:-}"
    echo " gateway .............. ${edge_net_gateway:-(none)}"
    echo " dns .................. ${edge_net_dns:-(none)}"
  else
    echo " network .............. dhcp"
  fi
  echo " run-on-boot script ... ${edge_boot_script_url:-(none)}"
  echo " edge login script .... ${edge_login_url:-(none)}"
  echo "------------------------------------------------------------"
}

edit_env() {
  local line n
  while :; do
    echo "Container environment variables (written to /opt/openedge/.env):"
    if [ -z "$edge_compose_env" ]; then
      echo "  (none)"
    else
      n=0
      while IFS= read -r line; do
        n=$((n + 1))
        printf '  %d) %s\n' "$n" "$line"
      done <<< "$edge_compose_env"
    fi
    printf '  [a] add  [d] delete  [c] clear  [b] back\n  choice: '
    local choice
    IFS= read -r choice || true
    case "$choice" in
      a)
        local pair
        printf '  KEY=VALUE: '
        IFS= read -r pair || true
        if [ -n "$pair" ]; then
          if [ -z "$edge_compose_env" ]; then
            edge_compose_env="$pair"
          else
            edge_compose_env="${edge_compose_env}
${pair}"
          fi
        fi
        ;;
      d)
        local target
        printf '  line number to delete: '
        IFS= read -r target || true
        case "$target" in
          '' | *[!0-9]*) continue ;;
        esac
        local rebuilt="" i=0 l
        while IFS= read -r l; do
          i=$((i + 1))
          [ "$i" -eq "$target" ] && continue
          if [ -z "$rebuilt" ]; then rebuilt="$l"; else rebuilt="${rebuilt}
${l}"; fi
        done <<< "$edge_compose_env"
        edge_compose_env="$rebuilt"
        ;;
      c) edge_compose_env="" ;;
      b | '') return ;;
    esac
  done
}

pick_source() {
  printf 'Compose source: [1] http(s) url  [2] s3  [3] gcs  [b] back\n  choice: '
  local choice
  IFS= read -r choice || true
  case "$choice" in
    1) edge_compose_source="http" ;;
    2) edge_compose_source="s3" ;;
    3) edge_compose_source="gcs" ;;
    *) return ;;
  esac
}

edit_location() {
  case "$edge_compose_source" in
    http)
      prompt_value edge_compose_url "URL to the docker-compose file"
      ;;
    s3 | gcs)
      prompt_value edge_compose_bucket "Bucket name"
      prompt_value edge_compose_object "Object key (path to the compose file)"
      [ "$edge_compose_source" = "s3" ] && prompt_value edge_s3_region "S3 region (optional)"
      ;;
    *)
      echo "Select a source first."
      ;;
  esac
}

edit_credentials() {
  case "$edge_compose_source" in
    s3)
      echo "Optional static S3 credentials. Leave blank to use an IAM role."
      local ak sk
      printf '  access key id: '
      IFS= read -r ak || true
      printf '  secret access key: '
      IFS= read -r sk || true
      if [ -n "$ak" ] && [ -n "$sk" ]; then
        edge_cloud_credentials="${ak}:${sk}"
      fi
      ;;
    gcs)
      echo "Optional GCS service-account JSON (minified, single line). Leave blank for ADC."
      local json
      printf '  json: '
      IFS= read -r json || true
      [ -n "$json" ] && edge_cloud_credentials="$json"
      ;;
    *)
      echo "Credentials are only used for s3/gcs sources."
      ;;
  esac
}

edit_services() {
  prompt_value edge_compose_project "Compose project name (optional)"
  prompt_value edge_compose_services "Space-separated services to start (blank = all)"
}

edit_retries() {
  prompt_value edge_fetch_retries "Fetch retries"
  prompt_value edge_fetch_delay "Seconds between retries"
}

edit_network() {
  printf 'Network mode: [1] dhcp  [2] static  [b] back\n  choice: '
  local choice
  IFS= read -r choice || true
  case "$choice" in
    1) edge_net_mode="dhcp" ;;
    2)
      edge_net_mode="static"
      prompt_value edge_net_address "Static IP address"
      prompt_value edge_net_netmask "Netmask (e.g. 255.255.255.0)"
      prompt_value edge_net_gateway "Gateway"
      prompt_value edge_net_dns "DNS servers (space-separated)"
      ;;
  esac
}

edit_boot_script() {
  echo "User script fetched and executed at every boot (saved as /opt/openedge/runmeonboot)."
  prompt_value edge_boot_script_url "URL to the runmeonboot script"
}

edit_login_script() {
  echo "Device registration/login script fetched and run at boot (saved as /opt/openedge/edge-login.sh)."
  prompt_value edge_login_url "URL to the edge-login script"
}

menu() {
  while :; do
    echo
    echo "openedge preconfigure"
    show_summary
    cat <<'MENU'
1) Compose source
   2) Compose location
   3) Container environment variables
   4) Project and services
   5) Fetch retries
   6) Cloud credentials
   7) Network configuration (dhcp/static)
   8) Run-on-boot script
   9) Edge login script
   10) Save configuration
   11) Quit without saving
MENU
    printf '  choice: '
    local choice
    IFS= read -r choice || true
    case "$choice" in
      1) pick_source ;;
      2) edit_location ;;
      3) edit_env ;;
      4) edit_services ;;
      5) edit_retries ;;
      6) edit_credentials ;;
      7) edit_network ;;
      8) edit_boot_script ;;
      9) edit_login_script ;;
      10)
        local warnings answer
        warnings="$(validation_warnings)"
        if [ -n "$warnings" ]; then
          echo "Warnings:"
          printf '%s' "$warnings" | sed 's/^/  - /'
          printf 'Save anyway? [y/N]: '
          IFS= read -r answer || true
          case "$answer" in
            y | Y) ;;
            *) continue ;;
          esac
        fi
        save_state
        write_vars
        return 0
        ;;
      11 | q | '') echo "Nothing written."; return 0 ;;
      *) echo "Invalid choice." ;;
    esac
  done
}

# --- non-interactive mode ----------------------------------------------------

apply_setting() {
  local pair="$1" key value
  key="${pair%%=*}"
  value="${pair#*=}"
  case "$key" in
    source | edge_compose_source) edge_compose_source="$value" ;;
    url | edge_compose_url) edge_compose_url="$value" ;;
    bucket | edge_compose_bucket) edge_compose_bucket="$value" ;;
    object | edge_compose_object) edge_compose_object="$value" ;;
    project | edge_compose_project) edge_compose_project="$value" ;;
    services | edge_compose_services) edge_compose_services="$value" ;;
    retries | edge_fetch_retries) edge_fetch_retries="$value" ;;
    delay | edge_fetch_delay) edge_fetch_delay="$value" ;;
    region | edge_s3_region) edge_s3_region="$value" ;;
    env | edge_compose_env) edge_compose_env="$value" ;;
    credentials | edge_cloud_credentials) edge_cloud_credentials="$value" ;;
    net_mode | edge_net_mode) edge_net_mode="$value" ;;
    net_address | edge_net_address) edge_net_address="$value" ;;
    net_netmask | edge_net_netmask) edge_net_netmask="$value" ;;
    net_gateway | edge_net_gateway) edge_net_gateway="$value" ;;
    net_dns | edge_net_dns) edge_net_dns="$value" ;;
    boot_script_url | edge_boot_script_url) edge_boot_script_url="$value" ;;
    login_url | edge_login_url) edge_login_url="$value" ;;
    *) echo "unknown setting: $key" >&2; exit 2 ;;
  esac
}

usage() {
  cat <<'EOF'
openedge preconfigure

Usage:
  ./preconfigure.sh                        interactive menu
  ./preconfigure.sh --set url=https://...   apply values non-interactively
  ./preconfigure.sh --save                 write state + variable file
  ./preconfigure.sh --dump                 print the variable file to stdout

Settings for --set: source, url, bucket, object, project, services, retries,
delay, region, env, credentials, net_mode, net_address, net_netmask, net_gateway,
net_dns, boot_script_url, login_url
EOF
}

main() {
  local do_dump=0 do_save=0 did_set=0
  local set_args=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --set)
        shift
        [ "$#" -gt 0 ] || { echo "--set needs key=value" >&2; exit 2; }
        set_args[${#set_args[@]}]="$1"
        did_set=1
        ;;
      --dump) do_dump=1 ;;
      --save) do_save=1 ;;
      -h | --help) usage; exit 0 ;;
      *)
        echo "unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
    shift
  done

  load_state

  local s
  for s in "${set_args[@]+"${set_args[@]}"}"; do
    apply_setting "$s"
  done

  if [ "$do_dump" -eq 1 ]; then
    { [ "$do_save" -eq 1 ] || [ "$did_set" -eq 1 ]; } && save_state
    emit_vars
    return 0
  fi

  if [ "$do_save" -eq 1 ] || [ "$did_set" -eq 1 ]; then
    save_state
    write_vars
    return 0
  fi

  # Interactive terminal menu. Reads from stdin, so it can also be driven
  # non-interactively (e.g. `printf '8\n' | ./preconfigure.sh`).
  menu
}

main "$@"
