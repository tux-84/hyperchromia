#!/bin/bash
# shellcheck disable=SC1091
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

hy_cmd_status() {
    local result all_state led_state os_version temp
    os_version=$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"')
    echo "HyperChromia: ${os_version:-unknown}"

    temp=$(hy_cpu_temp)
    if [ "$temp" = "?" ]; then
        echo "CPU temp: unavailable"
    else
        echo "CPU temp: ${temp}°C"
    fi

    result=$(hy_hyperhdr_status)
    read -r all_state led_state <<< "$result"

    case "$all_state" in
        true) echo "HyperHDR: on" ;;
        false) echo "HyperHDR: off" ;;
        *) echo "HyperHDR: unknown (not reachable on :$(hy_hyperhdr_port))" >&2; return 1 ;;
    esac

    case "$led_state" in
        true) echo "LED device: on" ;;
        false) echo "LED device: off" ;;
        *) echo "LED device: unknown" ;;
    esac

    echo "MQTT: $(hy_mqtt_status)"
}
