#!/bin/bash
# shellcheck disable=SC1091
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

hy_cmd_mqtt() {
    local host port username password tls cur_username

    if [ "$HY_PRESEED_ACTIVE" = "1" ]; then
        hy_mqtt_apply_preseed
        return $?
    fi

    echo "HyperChromia MQTT Bridge Configuration"
    read -r -p "Broker host (empty to disable): " host
    if [ -z "$host" ]; then
        sed -i "s/^MQTT_HOST=.*/MQTT_HOST=/" "$HY_MQTT_CONF"
        rm -f "$HY_MQTT_PROVISIONED"
        systemctl stop hyperchromia-mqtt
        echo "MQTT bridge disabled."
        return 0
    fi

    cur_username=$(sed -n 's/^MQTT_USERNAME=//p' "$HY_MQTT_CONF")
    read -r -p "Broker port [1883]: " port
    port="${port:-1883}"
    read -r -p "Username [$cur_username]: " username
    username="${username:-$cur_username}"
    read -r -s -p "Password (leave blank to keep current): " password
    echo
    if hy_confirm_yn "Use TLS? [y/N] "; then
        tls=1
    else
        tls=0
    fi

    sed -i \
        -e "s/^MQTT_HOST=.*/MQTT_HOST=$host/" \
        -e "s/^MQTT_PORT=.*/MQTT_PORT=$port/" \
        -e "s/^MQTT_USERNAME=.*/MQTT_USERNAME=$username/" \
        -e "s/^MQTT_TLS=.*/MQTT_TLS=$tls/" \
        "$HY_MQTT_CONF"
    [ -n "$password" ] && sed -i "s/^MQTT_PASSWORD=.*/MQTT_PASSWORD=$password/" "$HY_MQTT_CONF"

    touch "$HY_MQTT_PROVISIONED"
    systemctl restart hyperchromia-mqtt
    echo "MQTT bridge configured and restarted."
}

hy_mqtt_apply_preseed() {
    if [ -z "$HY_PRESEED_MQTT_HOST" ]; then
        return 0
    fi

    sed -i \
        -e "s/^MQTT_HOST=.*/MQTT_HOST=$HY_PRESEED_MQTT_HOST/" \
        -e "s/^MQTT_PORT=.*/MQTT_PORT=${HY_PRESEED_MQTT_PORT:-1883}/" \
        -e "s/^MQTT_USERNAME=.*/MQTT_USERNAME=$HY_PRESEED_MQTT_USERNAME/" \
        -e "s/^MQTT_TLS=.*/MQTT_TLS=${HY_PRESEED_MQTT_TLS:-0}/" \
        "$HY_MQTT_CONF"
    [ -n "$HY_PRESEED_MQTT_PASSWORD" ] && sed -i "s/^MQTT_PASSWORD=.*/MQTT_PASSWORD=$HY_PRESEED_MQTT_PASSWORD/" "$HY_MQTT_CONF"
    touch "$HY_MQTT_PROVISIONED"
}
