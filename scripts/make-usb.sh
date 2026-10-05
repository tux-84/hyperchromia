#!/bin/bash
set -euo pipefail

HYPERCHROMIA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS_NAME="$(uname -s)"
HY_VERBOSE=0
case "${1:-}" in
  -v|--verbose) HY_VERBOSE=1 ;;
esac

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\e[1;31m'
  C_GREEN=$'\e[1;32m'
  C_YELLOW=$'\e[1;33m'
  C_WHITE=$'\e[1;37m'
  C_DIM=$'\e[2m'
  C_RESET=$'\e[0m'
else
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_WHITE=""
  C_DIM=""
  C_RESET=""
fi

hy_step() {
  echo "${C_RED}==>${C_RESET} ${C_WHITE}$*${C_RESET}"
}

hy_ok() {
  echo "${C_GREEN}==> $*${C_RESET}"
}

hy_warn() {
  echo "${C_YELLOW}$*${C_RESET}" >&2
}

hy_err() {
  echo "${C_RED}ERROR: $*${C_RESET}" >&2
}

hy_clear() {
  printf '\033[2J\033[3J\033[H'
}

hy_run_quiet() {
  local label="$1" logfile
  shift
  if [ "$HY_VERBOSE" = "1" ]; then
    "$@"
    return $?
  fi
  logfile="$(mktemp)"
  "$@" > "$logfile" 2>&1 &
  local pid=$! elapsed=0
  trap 'kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rm -f "$logfile"; exit 130' INT TERM
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r    %s (%ds)" "$label" "$elapsed"
    sleep 1
    elapsed=$((elapsed + 1))
  done
  local result=0
  wait "$pid" || result=$?
  trap - INT TERM
  printf "\r    ${C_GREEN}%s done${C_RESET} (%ds)\n" "$label" "$elapsed"
  if [ "$result" -ne 0 ]; then
    hy_err "$label failed. Last 30 lines:"
    tail -30 "$logfile" >&2
  fi
  rm -f "$logfile"
  return "$result"
}

hy_sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

hy_sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

hy_verify_write() {
  local src="$1" dst="$2" size blocks src_sum dst_sum
  hy_step "Verifying write (reading back $dst)"
  size=$(wc -c < "$src" | tr -d ' ')
  blocks=$(((size + 4 * 1024 * 1024 - 1) / (4 * 1024 * 1024)))
  src_sum=$(hy_sha256_file "$src")
  dst_sum=$(sudo dd if="$dst" bs=4M count="$blocks" 2>/dev/null | head -c "$size" | hy_sha256_stdin)
  if [ "$src_sum" != "$dst_sum" ]; then
    hy_err "Verification failed: the data read back from $dst does not match $src."
    hy_warn "       The write to this USB device did not complete correctly -- this points"
    hy_warn "       to the stick or the USB port, not the image. Try a different USB stick"
    hy_warn "       and/or a different USB port, then re-run this script."
    return 1
  fi
  hy_ok "Write verified OK -- byte-for-byte match."
}

hy_dd_with_bar() {
  local src="$1" dst="$2"
  sudo -v
  hy_run_quiet "Writing $src to $dst" sudo dd if="$src" of="$dst" bs=4M conv=fsync
}

HY_DIALOG_BIN=""
if command -v dialog >/dev/null 2>&1; then
  HY_DIALOG_BIN="dialog"
elif command -v whiptail >/dev/null 2>&1; then
  HY_DIALOG_BIN="whiptail"
fi
if [ -n "$HY_DIALOG_BIN" ]; then
  exec 3>&1
fi

HY_REPLY=""

# Sets HY_REPLY. Called plain (not via $()) so dialog keeps a real subshell-free
# path to the terminal -- see hy_ask_menu for why that matters.
hy_ask_input() {
  local prompt="$1" default="${2:-}" rc
  if [ -n "$HY_DIALOG_BIN" ]; then
    HY_REPLY=$("$HY_DIALOG_BIN" --backtitle "HyperChromia" --title "HyperChromia setup" \
      --inputbox "$prompt" 12 70 "$default" \
      2>&1 1>&3)
    rc=$?
    hy_clear
    [ "$rc" -eq 0 ] || { hy_warn "Cancelled."; exit 1; }
  else
    read -r -p "$prompt [$default]: " HY_REPLY
    HY_REPLY="${HY_REPLY:-$default}"
  fi
}

hy_ask_password() {
  local prompt="$1" rc
  if [ -n "$HY_DIALOG_BIN" ]; then
    HY_REPLY=$("$HY_DIALOG_BIN" --backtitle "HyperChromia" --title "HyperChromia setup" \
      --insecure --passwordbox "$prompt" 12 70 \
      2>&1 1>&3)
    rc=$?
    hy_clear
    [ "$rc" -eq 0 ] || { hy_warn "Cancelled."; exit 1; }
  else
    read -r -s -p "$prompt: " HY_REPLY
    echo >&2
  fi
}

hy_ask_yesno() {
  local prompt="$1" rc
  if [ -n "$HY_DIALOG_BIN" ]; then
    "$HY_DIALOG_BIN" --backtitle "HyperChromia" --title "HyperChromia setup" \
      --defaultno --yesno "$prompt" 10 70 \
      1>&3 2>&3
    rc=$?
    hy_clear
    return "$rc"
  else
    local reply
    read -r -p "$prompt [y/N]: " reply
    case "$reply" in y|Y|yes|Yes) return 0 ;; *) return 1 ;; esac
  fi
}

# Called plain (e.g. `hy_ask_menu ...; CHOICE="$HY_REPLY"`), never as `x=$(hy_ask_menu ...)`.
# Wrapping a dialog call in a function that's itself inside $() forks an extra
# subshell around the whole call, and dialog's fd3->terminal link does not
# reliably survive that extra layer in every environment -- setting a global
# instead keeps dialog's invocation at the same shell level as the script.
hy_ask_menu() {
  local prompt="$1" n rc
  shift
  if [ -n "$HY_DIALOG_BIN" ]; then
    n=$(( $# / 2 ))
    HY_REPLY=$("$HY_DIALOG_BIN" --backtitle "HyperChromia" --title "HyperChromia setup" \
      --menu "$prompt" 16 76 "$n" "$@" \
      2>&1 1>&3)
    rc=$?
    hy_clear
    [ "$rc" -eq 0 ] || { hy_warn "Cancelled."; exit 1; }
  else
    echo "${C_WHITE}$prompt${C_RESET}" >&2
    while [ $# -gt 0 ]; do
      echo "  ${C_GREEN}$1)${C_RESET} $2" >&2
      shift 2
    done
    read -r -p "Select: " HY_REPLY
  fi
}

hy_step "Preflight checks"
if ! command -v docker >/dev/null 2>&1; then
  hy_err "docker is not installed. Install Docker Desktop (or Docker Engine on Linux) and re-run."
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  hy_err "docker is installed but the daemon isn't running. Start it and re-run."
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  hy_err "git is not installed."
  exit 1
fi

case "$OS_NAME" in
  Darwin|Linux) ;;
  *)
    hy_err "unsupported OS '$OS_NAME' -- this script supports macOS and Linux only."
    exit 1
    ;;
esac

HYPERCHROMIA_VERSION="$(cd "$HYPERCHROMIA_DIR" && git describe --tags --exact-match HEAD 2>/dev/null || true)"
if [ -z "$HYPERCHROMIA_VERSION" ]; then
  HYPERCHROMIA_VERSION="v$(cat "$HYPERCHROMIA_DIR/VERSION" 2>/dev/null || echo 0.0.0)-dev"
fi
hy_step "HyperChromia $HYPERCHROMIA_VERSION"

HY_CONTAINER_CHOICE=""
HY_BUILDROOT_TAG="$(grep -m1 '^BUILDROOT_TAG=' "$HYPERCHROMIA_DIR/scripts/build.sh" | cut -d= -f2)"
HY_BUILD_CONTAINER="hyperchromia-build-$HY_BUILDROOT_TAG-$HYPERCHROMIA_VERSION"
if docker ps -a --format '{{.Names}}' | grep -qx "$HY_BUILD_CONTAINER"; then
  hy_ask_menu "Found an existing build container for this version:" \
    resume "Resume it (reuse cached toolchain/build state)" \
    scratch "Start from scratch (removes it and its data first)"
  HY_CONTAINER_CHOICE="$HY_REPLY"
fi
export HY_CONTAINER_CHOICE

hy_ask_menu "What kind of USB stick do you want to make?" \
  1 "Factory/installer stick (install onto internal disk)" \
  2 "Update stick (apply an update to a running device)"
HY_MODE_CHOICE="$HY_REPLY"

case "$HY_MODE_CHOICE" in
  1) HY_MODE="factory" ;;
  2) HY_MODE="update" ;;
  *)
    hy_warn "Cancelled."
    exit 1
    ;;
esac

PRESEED_FILE=""

if [ "$HY_MODE" = "factory" ]; then
  hy_ask_input "Hostname (applied on first boot, no screen needed):" "hyperchromia"
  HY_HOSTNAME="$HY_REPLY"

  hy_ask_menu "Network configuration:" \
    1 "DHCP (default)" \
    2 "Static IP"
  HY_NET_CHOICE="$HY_REPLY"
  HY_NET_MODE="dhcp"
  HY_NET_IP=""
  HY_NET_MASK=""
  HY_NET_GW=""
  if [ "$HY_NET_CHOICE" = "2" ]; then
    HY_NET_MODE="static"
    hy_ask_input "IP address:" ""
    HY_NET_IP="$HY_REPLY"
    hy_ask_input "Netmask:" ""
    HY_NET_MASK="$HY_REPLY"
    hy_ask_input "Gateway:" ""
    HY_NET_GW="$HY_REPLY"
  fi

  hy_ask_password "Root password (leave blank to disable password login, SSH key only):"
  HY_ROOT_PASSWORD="$HY_REPLY"
  if [ -z "$HY_ROOT_PASSWORD" ]; then
    if ! grep -qE '^(ssh-|ecdsa-)' "$HYPERCHROMIA_DIR/authorized_keys" 2>/dev/null; then
      hy_err "root password left blank, but no SSH public key found in $HYPERCHROMIA_DIR/authorized_keys."
      hy_warn "       A device with no password and no key would be unreachable. Either set a"
      hy_warn "       password above, or add your public key to that file and re-run."
      exit 1
    fi
  fi

  hy_ask_input "MQTT broker host (leave blank to skip Home Assistant integration):" ""
  HY_MQTT_HOST="$HY_REPLY"
  HY_MQTT_PORT="1883"
  HY_MQTT_USERNAME=""
  HY_MQTT_PASSWORD=""
  HY_MQTT_TLS="0"
  if [ -n "$HY_MQTT_HOST" ]; then
    hy_ask_input "MQTT port:" "1883"
    HY_MQTT_PORT="$HY_REPLY"
    hy_ask_input "MQTT username:" ""
    HY_MQTT_USERNAME="$HY_REPLY"
    hy_ask_password "MQTT password:"
    HY_MQTT_PASSWORD="$HY_REPLY"
    if hy_ask_yesno "Use TLS for MQTT?"; then
      HY_MQTT_TLS="1"
    fi
  fi

  hy_ask_menu "Console keymap:" \
    us "US English (QWERTY)" \
    uk "UK English" \
    de "German" \
    de-latin1 "German (latin1)" \
    fr "French" \
    fr-latin1 "French (latin1)" \
    fr-ca "French (Canada)" \
    es "Spanish" \
    it "Italian" \
    nl "Dutch" \
    be-latin1 "Belgian (latin1)" \
    pt "Portuguese" \
    pt-br "Portuguese (Brazil)" \
    se-latin1 "Swedish (latin1)" \
    no-latin1 "Norwegian (latin1)" \
    dk-latin1 "Danish (latin1)" \
    fi-latin1 "Finnish (latin1)" \
    ch "Swiss (German)" \
    ch-fr "Swiss (French)" \
    pl "Polish" \
    cz-lat2 "Czech" \
    sk-qwerty "Slovak (QWERTY)" \
    hu "Hungarian" \
    ru "Russian" \
    tr_q-latin5 "Turkish (Q)" \
    gr "Greek" \
    jp106 "Japanese (106-key)" \
    other "Other (type a keymap name)"
  HY_KEYMAP="$HY_REPLY"
  if [ "$HY_KEYMAP" = "other" ]; then
    hy_ask_input "Console keymap name (see /usr/share/keymaps on the target for valid names):" "us"
    HY_KEYMAP="$HY_REPLY"
  fi

  HY_WIFI_ENABLE="0"
  HY_WIFI_SSID=""
  HY_WIFI_PASSWORD=""
  if hy_ask_yesno "Also configure Wi-Fi on the target?"; then
    HY_WIFI_ENABLE="1"
    hy_ask_input "Wi-Fi SSID:" ""
    HY_WIFI_SSID="$HY_REPLY"
    hy_ask_password "Wi-Fi password:"
    HY_WIFI_PASSWORD="$HY_REPLY"
  fi

  PRESEED_FILE="$(mktemp)"
  {
    echo "HY_PRESEED_HOSTNAME=$HY_HOSTNAME"
    echo "HY_PRESEED_NET_MODE=$HY_NET_MODE"
    echo "HY_PRESEED_NET_IP=$HY_NET_IP"
    echo "HY_PRESEED_NET_MASK=$HY_NET_MASK"
    echo "HY_PRESEED_NET_GW=$HY_NET_GW"
    echo "HY_PRESEED_ROOT_PASSWORD=$HY_ROOT_PASSWORD"
    echo "HY_PRESEED_MQTT_HOST=$HY_MQTT_HOST"
    echo "HY_PRESEED_MQTT_PORT=$HY_MQTT_PORT"
    echo "HY_PRESEED_MQTT_USERNAME=$HY_MQTT_USERNAME"
    echo "HY_PRESEED_MQTT_PASSWORD=$HY_MQTT_PASSWORD"
    echo "HY_PRESEED_MQTT_TLS=$HY_MQTT_TLS"
    echo "HY_PRESEED_LOCALE_KEYMAP=$HY_KEYMAP"
    echo "HY_PRESEED_WIFI_ENABLE=$HY_WIFI_ENABLE"
    echo "HY_PRESEED_WIFI_SSID=$HY_WIFI_SSID"
    echo "HY_PRESEED_WIFI_PASSWORD=$HY_WIFI_PASSWORD"
  } > "$PRESEED_FILE"
  chmod 600 "$PRESEED_FILE"
fi

echo
hy_step "Building HyperChromia"
if [ "$HY_MODE" = "factory" ]; then
  IMAGE_FILE="$HYPERCHROMIA_DIR/factory.img"
  HY_PRESEED_FILE="$PRESEED_FILE" hy_run_quiet "Building" "$HYPERCHROMIA_DIR/scripts/build.sh"
else
  IMAGE_FILE="$HYPERCHROMIA_DIR/update.img"
  hy_run_quiet "Building" "$HYPERCHROMIA_DIR/scripts/build.sh"
fi

if [ -n "$PRESEED_FILE" ]; then
  shred -u "$PRESEED_FILE" 2>/dev/null || rm -f "$PRESEED_FILE"
fi

if [ ! -f "$IMAGE_FILE" ]; then
  hy_err "expected build output '$IMAGE_FILE' not found."
  exit 1
fi
hy_ok "Built $IMAGE_FILE ($(du -h "$IMAGE_FILE" | cut -f1))"

echo
hy_step "Looking for removable USB devices"

DEVICE_LIST_FILE="$(mktemp)"
trap 'rm -f "$DEVICE_LIST_FILE"' EXIT

if [ "$OS_NAME" = "Darwin" ]; then
  for d in $(diskutil list external physical 2>/dev/null | grep -o '^/dev/disk[0-9]*' | sort -u); do
    desc=$(diskutil info "$d" 2>/dev/null | awk -F': *' '/Device \/ Media Name/{print $2}')
    size=$(diskutil info "$d" 2>/dev/null | awk -F': *' '/Disk Size/{print $2; exit}')
    echo "$d|${desc:-unknown device}|${size:-unknown size}" >> "$DEVICE_LIST_FILE"
  done
else
  while read -r name rm type size model; do
    [ "$type" = "disk" ] || continue
    [ "$rm" = "1" ] || continue
    echo "/dev/$name|${model:-unknown device}|${size:-unknown size}" >> "$DEVICE_LIST_FILE"
  done < <(lsblk -dn -o NAME,RM,TYPE,SIZE,MODEL 2>/dev/null)
fi

if [ ! -s "$DEVICE_LIST_FILE" ]; then
  hy_err "No removable USB devices found. Plug one in and re-run this script."
  exit 1
fi

i=0
DEVICE_PATHS=()
if [ -n "$HY_DIALOG_BIN" ]; then
  menu_args=()
  while IFS='|' read -r dpath ddesc dsize; do
    i=$((i + 1))
    DEVICE_PATHS+=("$dpath")
    menu_args+=("$i" "$dpath -- $ddesc ($dsize)")
  done < "$DEVICE_LIST_FILE"

  DEV_CHOICE=$("$HY_DIALOG_BIN" --backtitle "HyperChromia" --title "Select USB device" \
    --menu "Choose the device to flash:" 20 76 "$i" "${menu_args[@]}" \
    2>&1 >/dev/tty)
  dev_rc=$?
  hy_clear
  [ "${HY_DEBUG_DIALOG:-0}" = "1" ] && hy_warn "DEBUG device menu: rc=$dev_rc choice=[$DEV_CHOICE]"
  [ "$dev_rc" -eq 0 ] || { hy_warn "Cancelled."; exit 1; }
  [ -z "$DEV_CHOICE" ] && { hy_warn "Cancelled."; exit 1; }
  TARGET_DEVICE="${DEVICE_PATHS[$((DEV_CHOICE - 1))]}"

  HY_CONFIRMED=0
  if [ "$(basename "$HY_DIALOG_BIN")" = "dialog" ]; then
    red_rc=$(mktemp)
    cat > "$red_rc" <<'EOF'
title_color = (RED,WHITE,ON)
border_color = (RED,WHITE,ON)
button_active_color = (WHITE,RED,ON)
button_label_active_color = (WHITE,RED,ON)
EOF
    DIALOGRC="$red_rc" "$HY_DIALOG_BIN" --backtitle "HyperChromia" \
      --title "CONFIRM -- THIS WILL ERASE THE DEVICE" --defaultno \
      --yesno "ALL DATA ON $TARGET_DEVICE WILL BE PERMANENTLY ERASED.\n\nAre you sure?" 10 70 \
      </dev/tty >/dev/tty 2>&1 \
      && HY_CONFIRMED=1
    rm -f "$red_rc"
  else
    NEWT_COLORS='
border=red,white
title=red,white
actbutton=white,red
' "$HY_DIALOG_BIN" --backtitle "HyperChromia" \
      --title "CONFIRM -- THIS WILL ERASE THE DEVICE" --defaultno \
      --yesno "ALL DATA ON $TARGET_DEVICE WILL BE PERMANENTLY ERASED.\n\nAre you sure?" 10 70 \
      </dev/tty >/dev/tty 2>&1 \
      && HY_CONFIRMED=1
  fi
  hy_clear
  [ "$HY_CONFIRMED" = "1" ] || { hy_warn "Cancelled."; exit 1; }
else
  echo
  echo "${C_WHITE}Removable devices found:${C_RESET}"
  while IFS='|' read -r dpath ddesc dsize; do
    i=$((i + 1))
    DEVICE_PATHS+=("$dpath")
    echo "  ${C_GREEN}$i)${C_RESET} $dpath -- $ddesc ($dsize)"
  done < "$DEVICE_LIST_FILE"

  echo
  read -r -p "Select a device to flash [1-$i]: " DEV_CHOICE
  if ! [ "$DEV_CHOICE" -ge 1 ] 2>/dev/null || [ "$DEV_CHOICE" -gt "$i" ]; then
    hy_warn "Cancelled."
    exit 1
  fi
  TARGET_DEVICE="${DEVICE_PATHS[$((DEV_CHOICE - 1))]}"

  echo
  echo "${C_RED}!!! ALL DATA ON $TARGET_DEVICE WILL BE PERMANENTLY ERASED !!!${C_RESET}"
  read -r -p "Type yes to confirm: " CONFIRM_DEVICE
  if [ "$CONFIRM_DEVICE" != "yes" ]; then
    hy_warn "Confirmation did not match. Cancelled."
    exit 1
  fi
fi

if [ "$OS_NAME" = "Darwin" ]; then
  diskutil unmountDisk "$TARGET_DEVICE" >/dev/null 2>&1 || true
  RAW_DEVICE="/dev/r${TARGET_DEVICE#/dev/}"
  hy_step "Writing to $RAW_DEVICE"
  hy_dd_with_bar "$IMAGE_FILE" "$RAW_DEVICE"
  sync
  hy_verify_write "$IMAGE_FILE" "$RAW_DEVICE"
  diskutil eject "$TARGET_DEVICE" >/dev/null 2>&1 || true
else
  for part in "${TARGET_DEVICE}"*; do
    [ "$part" = "$TARGET_DEVICE" ] && continue
    umount "$part" >/dev/null 2>&1 || true
  done
  hy_step "Writing to $TARGET_DEVICE"
  hy_dd_with_bar "$IMAGE_FILE" "$TARGET_DEVICE"
  sync
  hy_verify_write "$IMAGE_FILE" "$TARGET_DEVICE"
fi

hy_ok "Done. $TARGET_DEVICE is ready."

echo
read -r -p "Remove the build cache now? [y/N]: " CLEANUP_YN
case "$CLEANUP_YN" in
  y|Y|yes|Yes)
    docker rm -f hyperchromia-build >/dev/null 2>&1 || true
    docker volume rm hyperchromia-work >/dev/null 2>&1 || true
    hy_ok "Build cache removed."
    ;;
  *)
    echo "${C_DIM}Keeping the build cache for faster rebuilds later.${C_RESET}"
    ;;
esac
