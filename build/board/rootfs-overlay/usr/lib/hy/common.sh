#!/bin/bash
# shellcheck disable=SC2034,SC2013
HY_BIN_DIR="/data/hyperhdr/bin"
HY_DATA_LIB_DIR="/data/hyperhdr/lib"
HY_SHARE_DIR="/data/hyperhdr/share"
HY_CONFIG_DIR="/data/hyperhdr/.config/HyperHDR"
HY_BACKUP_DIR="/data/hyperhdr/backups"
HY_STAGING_DIR="/data/hyperhdr/upgrade-staging"
HY_FACTORY_SEED="/usr/share/hyperchromia/factory-seed/hyperhdr"
HY_GITHUB_API="https://api.github.com/repos/awawa-dev/HyperHDR/releases"
HY_HYPERHDR_LD_LIBRARY_PATH="/data/hyperhdr/lib/hyperhdr:/data/hyperhdr/lib/hyperhdr/external"
HY_OVERLAY_BASE="/data/.overlay"
HY_MQTT_CONF="/etc/hyperchromia/mqtt.conf"
HY_MQTT_PROVISIONED="/etc/hyperchromia/.mqtt-configured"
HY_MQTT_STATE_FILE="/run/hyperchromia-mqtt-state"
HY_OS_STATE_DIR="/data/hyperchromia/state"
HY_OS_UPDATE_STATE="/data/hyperchromia/state/os-update.json"
HY_OS_ROOTA_LABEL="rootA"
HY_OS_ROOTB_LABEL="rootB"
HY_OS_UPDATE_MOUNT="/run/hyperchromia-update"
HY_OS_ESP_LABEL="boot"
HY_OS_ESP_MOUNT="/run/hyperchromia-esp"
HY_OS_GRUBENV="/run/hyperchromia-esp/EFI/debian/grubenv"
HY_FACTORY_FIRSTBOOT_PRESEED="/usr/share/hyperchromia/factory-seed/firstboot.conf"

hy_boot_disk() {
    local arg root_label="" part_dev="" root_pk u

    for arg in $(cat /proc/cmdline); do
        case "$arg" in
            root=PARTLABEL=*) root_label="${arg#root=PARTLABEL=}" ;;
        esac
    done
    [ -n "$root_label" ] || return 1

    for u in /sys/class/block/*/uevent; do
        if grep -q "^PARTNAME=${root_label}$" "$u" 2>/dev/null; then
            part_dev="$(basename "$(dirname "$u")")"
            break
        fi
    done
    [ -n "$part_dev" ] || return 1

    root_pk=$(lsblk -no PKNAME "/dev/$part_dev" 2>/dev/null)
    [ -n "$root_pk" ] || return 1
    echo "$root_pk"
}

hy_booted_from_removable_media() {
    local disk
    disk=$(hy_boot_disk) || return 1
    [ "$(cat "/sys/block/$disk/removable" 2>/dev/null)" = "1" ]
}

hy_wait_for_active() {
    local unit="$1"
    local timeout="${2:-10}"
    local steps=$(( timeout * 2 ))
    local i
    for (( i = 0; i < steps; i++ )); do
        [ "$(systemctl is-active "$unit" 2>/dev/null)" = "active" ] && return 0
        sleep 0.5
    done
    [ "$(systemctl is-active "$unit" 2>/dev/null)" = "active" ]
}

hy_run_timeout() {
    local secs="$1"
    shift
    "$@" &
    local pid=$!
    ( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) &
    local watcher=$!
    wait "$pid" 2>/dev/null
    kill "$watcher" 2>/dev/null
}

hy_confirm_yn() {
    local ans
    read -r -p "$1" ans
    case "$ans" in
        y|Y|yes|Yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

hy_valid_ipv4() {
    local ip="$1"
    local IFS=.
    local -a o
    read -r -a o <<< "$ip"
    [ "${#o[@]}" -eq 4 ] || return 1
    local n
    for n in "${o[@]}"; do
        case "$n" in
            ''|*[!0-9]*) return 1 ;;
        esac
        [ "$n" -le 255 ] || return 1
    done
    return 0
}

hy_valid_hostname() {
    echo "$1" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'
}

hy_connman_active_service() {
    command -v connmanctl >/dev/null 2>&1 || return 1
    connmanctl services 2>/dev/null | sed -n 's/^\*[A-Za-z]* .*[[:space:]]\([^[:space:]]*\)$/\1/p' | head -n1
}

hy_connman_mode() {
    local svc="$1"
    connmanctl services "$svc" 2>/dev/null \
        | grep -o 'IPv4\.Configuration = \[ Method=[a-zA-Z]*' \
        | sed 's/.*Method=//' \
        | head -n1
}

hy_current_version() {
    local bin="$HY_BIN_DIR/hyperhdr"
    [ -x "$bin" ] || return 1
    LD_LIBRARY_PATH="$HY_HYPERHDR_LD_LIBRARY_PATH:$LD_LIBRARY_PATH" \
        "$bin" --version 2>/dev/null | sed -n 's/^[[:space:]]*Version[[:space:]]*: *//p' | awk '{print $1}' | head -n1
}

hy_version_cmp() {
    local IFS=.
    local -a v1 v2
    read -r -a v1 <<< "${1#v}"
    read -r -a v2 <<< "${2#v}"
    local i a b c1 c2
    for i in 0 1 2 3; do
        c1="${v1[i]//[!0-9]/}"
        c2="${v2[i]//[!0-9]/}"
        a=$((10#${c1:-0}))
        b=$((10#${c2:-0}))
        if [ "$a" -lt "$b" ]; then echo -1; return; fi
        if [ "$a" -gt "$b" ]; then echo 1; return; fi
    done
    echo 0
}

hy_version_gt() {
    [ "$(hy_version_cmp "$1" "$2")" = "1" ]
}

hy_mqtt_status() {
    local host
    host=$(sed -n 's/^MQTT_HOST=//p' "$HY_MQTT_CONF" 2>/dev/null)
    if [ -z "$host" ]; then
        echo "not configured"
        return 0
    fi
    cat "$HY_MQTT_STATE_FILE" 2>/dev/null || echo "offline"
}

hy_hyperhdr_port() {
    local db config port
    db="$HY_CONFIG_DIR/db/hyperhdr.db"
    if [ -r "$db" ]; then
        config=$(sqlite3 "$db" "SELECT config FROM settings WHERE type='webConfig';" 2>/dev/null)
        port=$(echo "$config" | jq -r '.port // empty' 2>/dev/null)
    fi
    echo "${port:-80}"
}

hy_hyperhdr_status() {
    local json all_state led_state
    json=$(wget -qO- -T 2 --post-data='{"command":"serverinfo","tan":1}' "http://127.0.0.1:$(hy_hyperhdr_port)/json-rpc" 2>/dev/null)
    if [ -z "$json" ]; then
        echo "? ?"
        return 1
    fi
    all_state=$(echo "$json" | jq -r '.info.components[] | select(.name=="ALL") | .enabled' 2>/dev/null)
    led_state=$(echo "$json" | jq -r '.info.components[] | select(.name=="LEDDEVICE") | .enabled' 2>/dev/null)
    echo "${all_state:-?} ${led_state:-?}"
}

hy_hyperhdr_set_component() {
    local component="$1" state="$2"
    wget -qO- -T 2 --post-data="{\"command\":\"componentstate\",\"componentstate\":{\"component\":\"$component\",\"state\":$state}}" \
        "http://127.0.0.1:$(hy_hyperhdr_port)/json-rpc" >/dev/null 2>&1
}

hy_hyperhdr_set_led() {
    hy_hyperhdr_set_component "LEDDEVICE" "$1"
}

hy_cpu_temp() {
    local hwmon name path raw

    for hwmon in /sys/class/hwmon/hwmon*; do
        [ -r "$hwmon/name" ] || continue
        name=$(cat "$hwmon/name" 2>/dev/null)
        case "$name" in
            coretemp|k10temp)
                for path in "$hwmon"/temp*_input; do
                    [ -r "$path" ] || continue
                    raw=$(cat "$path" 2>/dev/null)
                    if [ -n "$raw" ]; then
                        echo $((raw / 1000))
                        return 0
                    fi
                done
                ;;
        esac
    done

    for path in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$path" ] || continue
        raw=$(cat "$path" 2>/dev/null)
        if [ -n "$raw" ]; then
            echo $((raw / 1000))
            return 0
        fi
    done

    echo "?"
    return 1
}
