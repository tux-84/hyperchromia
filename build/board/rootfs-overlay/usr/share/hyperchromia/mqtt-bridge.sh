#!/bin/bash
# shellcheck disable=SC1091,SC1090
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

MQTT_HOST=""
MQTT_PORT="1883"
MQTT_USERNAME=""
MQTT_PASSWORD=""
MQTT_TLS="0"
source "$HY_MQTT_CONF"

[ -z "$MQTT_HOST" ] && exit 0

hy_hostname=$(hostname)
prefix="hyperchromia/$hy_hostname"
device_id="hyperchromia_$hy_hostname"

mosq_opts=(-h "$MQTT_HOST" -p "$MQTT_PORT" -i "$device_id-bridge")
[ -n "$MQTT_USERNAME" ] && mosq_opts+=(-u "$MQTT_USERNAME")
[ -n "$MQTT_PASSWORD" ] && mosq_opts+=(-P "$MQTT_PASSWORD")
[ "$MQTT_TLS" = "1" ] && mosq_opts+=(--cafile /etc/ssl/certs/ca-certificates.crt)

hy_mqtt_wait_for_broker() {
    local i=0
    while [ "$i" -lt 30 ]; do
        (exec 3<>"/dev/tcp/$MQTT_HOST/$MQTT_PORT") 2>/dev/null && return 0
        i=$((i + 1))
        sleep 1
    done
    return 1
}

if ! hy_mqtt_wait_for_broker; then
    echo "mqtt-bridge: broker $MQTT_HOST:$MQTT_PORT unreachable after 30s; giving up for this run." >&2
    exit 1
fi

hy_mqtt_pub() {
    mosquitto_pub "${mosq_opts[@]}" -r -t "$1" -m "$2" 2>/dev/null
}

hy_mqtt_device_json() {
    printf '"device":{"identifiers":["%s"],"name":"HyperChromia (%s)","model":"HyperChromia","manufacturer":"HyperChromia"}' \
        "$device_id" "$hy_hostname"
}

hy_mqtt_publish_discovery() {
    local dev avail
    dev=$(hy_mqtt_device_json)
    avail="\"availability_topic\":\"$prefix/status/mqtt\",\"payload_available\":\"online\",\"payload_not_available\":\"offline\""

    hy_mqtt_pub "homeassistant/button/${device_id}_reboot/config" \
        "{\"name\":\"Reboot\",\"unique_id\":\"${device_id}_reboot\",\"command_topic\":\"$prefix/cmd/reboot\",\"payload_press\":\"PRESS\",$avail,$dev}"
    hy_mqtt_pub "homeassistant/button/${device_id}_poweroff/config" \
        "{\"name\":\"Power off\",\"unique_id\":\"${device_id}_poweroff\",\"command_topic\":\"$prefix/cmd/poweroff\",\"payload_press\":\"PRESS\",$avail,$dev}"
    hy_mqtt_pub "homeassistant/button/${device_id}_restart_hyperhdr/config" \
        "{\"name\":\"Restart HyperHDR\",\"unique_id\":\"${device_id}_restart_hyperhdr\",\"command_topic\":\"$prefix/cmd/restart_hyperhdr\",\"payload_press\":\"PRESS\",$avail,$dev}"

    hy_mqtt_pub "homeassistant/binary_sensor/${device_id}_hyperhdr/config" \
        "{\"name\":\"HyperHDR\",\"unique_id\":\"${device_id}_hyperhdr\",\"state_topic\":\"$prefix/status/hyperhdr\",\"payload_on\":\"ON\",\"payload_off\":\"OFF\",$avail,$dev}"
    hy_mqtt_pub "homeassistant/switch/${device_id}_led/config" \
        "{\"name\":\"LED device\",\"unique_id\":\"${device_id}_led\",\"command_topic\":\"$prefix/cmd/led\",\"state_topic\":\"$prefix/status/led\",\"payload_on\":\"ON\",\"payload_off\":\"OFF\",$avail,$dev}"
    hy_mqtt_pub "homeassistant/binary_sensor/${device_id}_led/config" ""
    hy_mqtt_pub "homeassistant/binary_sensor/${device_id}_mqtt/config" \
        "{\"name\":\"MQTT bridge\",\"unique_id\":\"${device_id}_mqtt\",\"state_topic\":\"$prefix/status/mqtt\",\"payload_on\":\"online\",\"payload_off\":\"offline\",\"device_class\":\"connectivity\",$dev}"
    hy_mqtt_pub "homeassistant/sensor/${device_id}_cpu_temp/config" \
        "{\"name\":\"CPU temperature\",\"unique_id\":\"${device_id}_cpu_temp\",\"state_topic\":\"$prefix/status/cpu_temp\",\"device_class\":\"temperature\",\"unit_of_measurement\":\"°C\",$avail,$dev}"
}

hy_mqtt_status_loop() {
    local result all_state led_state temp
    while true; do
        if hy_mqtt_pub "$prefix/status/mqtt" "online"; then
            echo "online" > "$HY_MQTT_STATE_FILE"
        else
            echo "offline" > "$HY_MQTT_STATE_FILE"
        fi

        result=$(hy_hyperhdr_status)
        read -r all_state led_state <<< "$result"
        case "$all_state" in
            true) hy_mqtt_pub "$prefix/status/hyperhdr" "ON" ;;
            false) hy_mqtt_pub "$prefix/status/hyperhdr" "OFF" ;;
        esac
        case "$led_state" in
            true) hy_mqtt_pub "$prefix/status/led" "ON" ;;
            false) hy_mqtt_pub "$prefix/status/led" "OFF" ;;
        esac

        temp=$(hy_cpu_temp)
        [ "$temp" != "?" ] && hy_mqtt_pub "$prefix/status/cpu_temp" "$temp"

        sleep 10
    done
}

hy_mqtt_publish_discovery
( hy_mqtt_status_loop ) &

mosquitto_sub "${mosq_opts[@]}" -v -t "$prefix/cmd/#" \
    --will-topic "$prefix/status/mqtt" --will-payload "offline" --will-retain \
    | while IFS=' ' read -r topic payload; do
        true "$payload"
        case "$topic" in
            "$prefix/cmd/reboot") systemctl reboot ;;
            "$prefix/cmd/poweroff") systemctl poweroff ;;
            "$prefix/cmd/restart_hyperhdr") systemctl restart hyperhdr ;;
            "$prefix/cmd/led")
                if [ "$payload" = "ON" ]; then
                    hy_hyperhdr_set_led true
                else
                    hy_hyperhdr_set_led false
                fi
                ;;
        esac
    done
sub_status="${PIPESTATUS[0]}"

echo "offline" > "$HY_MQTT_STATE_FILE"
[ "$sub_status" -eq 0 ] || exit 1
