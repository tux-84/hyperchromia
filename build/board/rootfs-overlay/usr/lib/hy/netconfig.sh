#!/bin/bash
# shellcheck disable=SC1091
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

hy_netconfig_wifi_find_service() {
    local ssid="$1" line name svc
    while IFS= read -r line; do
        svc="${line##* }"
        name="${line:4}"
        name="${name% "$svc"}"
        name="${name%"${name##*[![:space:]]}"}"
        if [ "$name" = "$ssid" ]; then
            echo "$svc"
            return 0
        fi
    done < <(connmanctl services 2>/dev/null)
    return 1
}

hy_netconfig_wifi_on() {
    connmanctl enable wifi >/dev/null 2>&1
}

hy_netconfig_wifi_off() {
    connmanctl disable wifi >/dev/null 2>&1
}

hy_netconfig_wifi_connect() {
    local ssid="$1" password="$2" svc
    [ -n "$ssid" ] || return 1
    connmanctl enable wifi >/dev/null 2>&1
    connmanctl scan wifi >/dev/null 2>&1
    svc=$(hy_netconfig_wifi_find_service "$ssid")
    if [ -z "$svc" ]; then
        echo "netconfig: network '$ssid' not found." >&2
        return 1
    fi
    mkdir -p /var/lib/connman
    cat > /var/lib/connman/hyperchromia_wifi.config <<EOF
[service_hyperchromia_wifi]
Type = wifi
Name = $ssid
Passphrase = $password
EOF
    chmod 600 /var/lib/connman/hyperchromia_wifi.config
    hy_run_timeout 10 connmanctl connect "$svc" >/dev/null 2>&1
}

hy_cmd_netconfig() {
    if [ "$HY_PRESEED_ACTIVE" = "1" ]; then
        hy_netconfig_apply_preseed
        return $?
    fi

    case "$1" in
        wifi)
            case "$2" in
                on)
                    hy_netconfig_wifi_on
                    ;;
                off)
                    hy_netconfig_wifi_off
                    ;;
                connect)
                    if [ -z "$3" ]; then
                        echo "Usage: hy netconfig wifi connect <ssid> [password]" >&2
                        return 1
                    fi
                    hy_netconfig_wifi_connect "$3" "$4"
                    ;;
                *)
                    echo "Usage: hy netconfig wifi <on|off|connect <ssid> [password]>" >&2
                    return 1
                    ;;
            esac
            return $?
            ;;
    esac

    echo "HyperChromia Network Configuration"
    echo "1) Switch to DHCP"
    echo "2) Switch to static IP"
    echo "3) Change hostname"
    echo "4) Enable Wi-Fi"
    echo "5) Disable Wi-Fi"
    echo "6) Connect to a Wi-Fi network"
    echo "q) Cancel"

    local choice
    read -r -p "Select an option: " choice

    case "$choice" in
        1)
            local svc
            svc=$(hy_connman_active_service)
            if [ -z "$svc" ]; then
                echo "Could not determine the active network service." >&2
                return 1
            fi
            echo "This will switch '$svc' to DHCP."
            if hy_confirm_yn "Save this change and reboot now? [y/N] "; then
                connmanctl config "$svc" --ipv4 dhcp
                sync
                reboot
            else
                echo "Cancelled. No changes made."
            fi
            ;;
        2)
            local svc ip mask gw
            svc=$(hy_connman_active_service)
            if [ -z "$svc" ]; then
                echo "Could not determine the active network service." >&2
                return 1
            fi
            read -r -p "IP address: " ip
            read -r -p "Netmask: " mask
            read -r -p "Gateway: " gw
            if ! hy_valid_ipv4 "$ip" || ! hy_valid_ipv4 "$mask" || ! hy_valid_ipv4 "$gw"; then
                echo "Invalid IPv4 address, netmask or gateway format." >&2
                return 1
            fi
            echo "This will set '$svc' to static: $ip / $mask via $gw"
            if hy_confirm_yn "Save this change and reboot now? [y/N] "; then
                connmanctl config "$svc" --ipv4 manual "$ip" "$mask" "$gw"
                sync
                reboot
            else
                echo "Cancelled. No changes made."
            fi
            ;;
        3)
            local newname
            read -r -p "New hostname: " newname
            if ! hy_valid_hostname "$newname"; then
                echo "Invalid hostname." >&2
                return 1
            fi
            echo "This will set the hostname to '$newname'."
            if hy_confirm_yn "Save this change and reboot now? [y/N] "; then
                echo "$newname" > /etc/hostname
                hostnamectl set-hostname "$newname"
                sync
                reboot
            else
                echo "Cancelled. No changes made."
            fi
            ;;
        4)
            hy_netconfig_wifi_on
            echo "Wi-Fi enabled."
            ;;
        5)
            hy_netconfig_wifi_off
            echo "Wi-Fi disabled."
            ;;
        6)
            local ssid password
            read -r -p "SSID: " ssid
            read -r -s -p "Password: " password
            echo
            if hy_netconfig_wifi_connect "$ssid" "$password"; then
                echo "Connecting to '$ssid'..."
            else
                echo "Failed to connect to '$ssid'." >&2
                return 1
            fi
            ;;
        *)
            echo "Cancelled."
            ;;
    esac
}

hy_netconfig_apply_preseed() {
    local svc

    if [ -n "$HY_PRESEED_HOSTNAME" ]; then
        if hy_valid_hostname "$HY_PRESEED_HOSTNAME"; then
            echo "$HY_PRESEED_HOSTNAME" > /etc/hostname
            hostnamectl set-hostname "$HY_PRESEED_HOSTNAME"
        else
            echo "netconfig: preseed hostname '$HY_PRESEED_HOSTNAME' is invalid, skipping." >&2
        fi
    fi

    case "$HY_PRESEED_NET_MODE" in
        static)
            svc=$(hy_connman_active_service)
            if [ -z "$svc" ]; then
                echo "netconfig: could not determine the active network service, skipping static IP preseed." >&2
                return 1
            fi
            if ! hy_valid_ipv4 "$HY_PRESEED_NET_IP" || ! hy_valid_ipv4 "$HY_PRESEED_NET_MASK" \
                || ! hy_valid_ipv4 "$HY_PRESEED_NET_GW"; then
                echo "netconfig: invalid preseed static IP/netmask/gateway, skipping." >&2
                return 1
            fi
            connmanctl config "$svc" --ipv4 manual "$HY_PRESEED_NET_IP" "$HY_PRESEED_NET_MASK" "$HY_PRESEED_NET_GW"
            ;;
        dhcp)
            svc=$(hy_connman_active_service)
            [ -n "$svc" ] && connmanctl config "$svc" --ipv4 dhcp
            ;;
        ""|*)
            :
            ;;
    esac

    if [ "$HY_PRESEED_WIFI_ENABLE" = "1" ] && [ -n "$HY_PRESEED_WIFI_SSID" ]; then
        hy_netconfig_wifi_connect "$HY_PRESEED_WIFI_SSID" "$HY_PRESEED_WIFI_PASSWORD" \
            || echo "netconfig: could not connect to preseed Wi-Fi network '$HY_PRESEED_WIFI_SSID'." >&2
    fi

    sync
}
