#!/bin/bash
# shellcheck disable=SC1091,SC1090
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"
source "$HY_LIB_DIR/netconfig.sh"
source "$HY_LIB_DIR/password.sh"
source "$HY_LIB_DIR/mqtt.sh"
source "$HY_LIB_DIR/locale.sh"

HY_FIRSTBOOT_MARKER="$HY_OS_STATE_DIR/firstboot-done"
HY_FIRSTBOOT_PRESEED="/data/hyperchromia/firstboot.conf"

hy_firstboot_log() {
    echo "hyperchromia-firstboot: $*" > /dev/tty1 2>/dev/null || true
}

hy_cmd_firstboot() {
    mkdir -p "$HY_OS_STATE_DIR"

    if [ -f "$HY_FIRSTBOOT_PRESEED" ]; then
        HY_PRESEED_ACTIVE=1
        source "$HY_FIRSTBOOT_PRESEED"
        export HY_PRESEED_ACTIVE

        hy_firstboot_log "applying preseed -- locale..."
        hy_cmd_locale
        hy_firstboot_log "applying preseed -- netconfig..."
        hy_cmd_netconfig
        hy_firstboot_log "applying preseed -- password..."
        hy_cmd_password
        hy_firstboot_log "applying preseed -- mqtt..."
        hy_cmd_mqtt
        hy_firstboot_log "preseed applied."

        shred -u "$HY_FIRSTBOOT_PRESEED" 2>/dev/null || rm -f "$HY_FIRSTBOOT_PRESEED"

        unset HY_PRESEED_ACTIVE HY_PRESEED_HOSTNAME HY_PRESEED_NET_MODE HY_PRESEED_NET_IP \
            HY_PRESEED_NET_MASK HY_PRESEED_NET_GW HY_PRESEED_ROOT_PASSWORD \
            HY_PRESEED_MQTT_HOST HY_PRESEED_MQTT_PORT HY_PRESEED_MQTT_USERNAME \
            HY_PRESEED_MQTT_PASSWORD HY_PRESEED_MQTT_TLS HY_PRESEED_LOCALE_KEYMAP \
            HY_PRESEED_WIFI_ENABLE HY_PRESEED_WIFI_SSID HY_PRESEED_WIFI_PASSWORD
    else
        hy_firstboot_log "no preseed found at $HY_FIRSTBOOT_PRESEED -- configuring interactively on this console."
        {
            echo "=== HyperChromia first-time setup ==="
            echo "No preseed found -- configuring interactively. Run 'hy setup' later to redo this."
            echo
            hy_cmd_locale
            hy_cmd_netconfig
            hy_cmd_password
            hy_cmd_mqtt
        } < /dev/tty1 > /dev/tty1 2>/dev/tty1
    fi

    touch "$HY_FIRSTBOOT_MARKER"
    sync
}
