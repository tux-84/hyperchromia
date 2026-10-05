#!/bin/bash
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

hy_cmd_net() {
    local iface
    iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
    [ -z "$iface" ] && iface=$(ip -o link show up 2>/dev/null | awk -F': ' '$2 != "lo" {print $2; exit}')

    if [ -z "$iface" ]; then
        echo "No active network interface found."
        return 1
    fi

    local state ipv4 ipv6 gw mac dns mode svc
    state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null)
    ipv4=$(ip -4 -o addr show dev "$iface" scope global 2>/dev/null | awk '{print $4; exit}')
    ipv6=$(ip -6 -o addr show dev "$iface" scope global 2>/dev/null | awk '{print $4; exit}')
    gw=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
    mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
    dns=$(awk '/^nameserver/ {printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)

    mode="unknown"
    svc=$(hy_connman_active_service)
    if [ -n "$svc" ]; then
        mode=$(hy_connman_mode "$svc")
        [ -z "$mode" ] && mode="unknown"
    fi

    echo "Interface     : $iface"
    echo "Link state    : ${state:-unknown}"
    echo "IPv4 address  : ${ipv4:-none}"
    echo "IPv6 address  : ${ipv6:-none}"
    echo "Gateway       : ${gw:-none}"
    echo "DNS servers   : ${dns:-none}"
    echo "MAC address   : ${mac:-unknown}"
    echo "Config mode   : $mode"
}
