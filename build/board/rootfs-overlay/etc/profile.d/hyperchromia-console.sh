#!/bin/bash
# shellcheck disable=SC1091

[[ $- == *i* ]] || return 0
[ -t 0 ] && [ -t 1 ] || return 0

HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

printf '\e[2J\e[H'
_hyperchromia_logo=(
    "#################   "
    "#################   "
    "######              "
    "######              "
    "######              "
    "######              "
    "######              "
    "#################   "
    "#################"
)
_hyperchromia_banner=(
    ""
    "#     #                             #####                               #        "
    "#     # #   # #####  ###### #####  #      #      #####   ##### #     #      #####"
    "#     #  # #  #    # #      #    # #      #      #    # #    # ##   ##  #       #"
    "#######   #   #    # #####  #    # #      #####  #    # #    # # # # #  #   #####"
    "#     #   #   #####  #      #####  #      #    # #####  #    # #  #  #  #  #    #"
    "#     #   #   #      #      #   #  #      #    # #   #  #    # #     #  #  #    #"
    "#     #   #   #      ###### #    #  ##### #    # #    #  ##### #     #  #   #####"
    ""
)
printf '\e[1;31m'
for _hyperchromia_i in "${!_hyperchromia_logo[@]}"; do
    printf '%s   %s\n' "${_hyperchromia_logo[$_hyperchromia_i]}" "${_hyperchromia_banner[$_hyperchromia_i]}"
done
printf '\e[0m'
unset _hyperchromia_logo _hyperchromia_banner _hyperchromia_i
echo "Type 'hy help' to see available commands."

if tput csr 0 0 &>/dev/null; then
    _hyperchromia_logo_lines=9
    _hyperchromia_row_status=$(( _hyperchromia_logo_lines + 2 ))
    _hyperchromia_row_cpu=$(( _hyperchromia_row_status + 1 ))
    _hyperchromia_row_ram=$(( _hyperchromia_row_cpu + 1 ))
    _hyperchromia_row_temp=$(( _hyperchromia_row_ram + 1 ))
    _hyperchromia_row_url=$(( _hyperchromia_row_temp + 2 ))
    _hyperchromia_row_rule=$(( _hyperchromia_row_url + 2 ))
    _hyperchromia_header_lines=$(( _hyperchromia_row_rule + 1 ))

    _hyperchromia_cap_sc=$(tput sc)
    _hyperchromia_cap_rc=$(tput rc)
    _hyperchromia_cap_el=$(tput el)
    _hyperchromia_cap_cup_status=$(tput cup "$_hyperchromia_row_status" 0)
    _hyperchromia_cap_cup_cpu=$(tput cup "$_hyperchromia_row_cpu" 0)
    _hyperchromia_cap_cup_ram=$(tput cup "$_hyperchromia_row_ram" 0)
    _hyperchromia_cap_cup_temp=$(tput cup "$_hyperchromia_row_temp" 0)
    _hyperchromia_cap_cup_url=$(tput cup "$_hyperchromia_row_url" 0)

    _hyperchromia_prev_cpu_total=0
    _hyperchromia_prev_cpu_idle=0

    _hyperchromia_bar() {
        local pct="$1" width="$2" filled empty
        [ "$pct" -lt 0 ] && pct=0
        [ "$pct" -gt 100 ] && pct=100
        filled=$(( pct * width / 100 ))
        empty=$(( width - filled ))
        printf '['
        [ "$filled" -gt 0 ] && printf '%*s' "$filled" '' | tr ' ' '#'
        [ "$empty" -gt 0 ] && printf '%*s' "$empty" '' | tr ' ' '-'
        printf ']'
    }

    _hyperchromia_cpu_pct_result=0

    _hyperchromia_cpu_percent() {
        local line user nice system idle iowait irq softirq steal idletotal total dtotal didle
        line=$(awk '/^cpu /{print; exit}' /proc/stat 2>/dev/null)
        read -r _ user nice system idle iowait irq softirq steal _ _ <<< "$line"
        idletotal=$(( idle + iowait ))
        total=$(( user + nice + system + idletotal + irq + softirq + steal ))
        dtotal=$(( total - _hyperchromia_prev_cpu_total ))
        didle=$(( idletotal - _hyperchromia_prev_cpu_idle ))
        _hyperchromia_prev_cpu_total=$total
        _hyperchromia_prev_cpu_idle=$idletotal
        if [ "$dtotal" -le 0 ]; then
            _hyperchromia_cpu_pct_result=0
        else
            _hyperchromia_cpu_pct_result=$(( (dtotal - didle) * 100 / dtotal ))
        fi
    }

    _hyperchromia_status_line() {
        local hyperhdr_txt led_txt mqtt_txt ip ver os_ver
        hyperhdr_txt="N/A"
        led_txt="N/A"
        mqtt_txt=$(hy_mqtt_status 2>/dev/null)
        ip=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1)
        [ -z "$ip" ] && ip="no IP"
        ver=$(hy_current_version 2>/dev/null)
        [ -z "$ver" ] && ver="unknown"
        os_ver=$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"')
        [ -z "$os_ver" ] && os_ver="unknown"
        printf 'HyperChromia %-12s  HyperHDR: %-3s  LED: %-3s  MQTT: %-14s  IP %-15s  v%s' \
            "$os_ver" "$hyperhdr_txt" "$led_txt" "$mqtt_txt" "$ip" "$ver"
    }

    _hyperchromia_cpu_line() {
        local pct="$1"
        printf 'CPU %s %3d%%' "$(_hyperchromia_bar "$pct" 20)" "$pct"
    }

    _hyperchromia_ram_line() {
        local mem_total mem_avail mem_used mem_total_mb pct
        mem_total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)
        mem_avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)
        if [ -n "$mem_total" ] && [ -n "$mem_avail" ] && [ "$mem_total" -gt 0 ]; then
            mem_used=$(( (mem_total - mem_avail) / 1024 ))
            mem_total_mb=$(( mem_total / 1024 ))
            pct=$(( (mem_total - mem_avail) * 100 / mem_total ))
        else
            mem_used=0; mem_total_mb=0; pct=0
        fi
        printf 'RAM %s %d/%dMB' "$(_hyperchromia_bar "$pct" 20)" "$mem_used" "$mem_total_mb"
    }

    _hyperchromia_temp_line() {
        local temp="$1"
        if [ "$temp" = "?" ]; then
            printf 'Temp N/A'
        else
            printf 'Temp %d°C' "$temp"
        fi
    }

    _hyperchromia_url_line() {
        local host port
        host=$(hostname 2>/dev/null)
        [ -z "$host" ] && host="hyperchromia"
        port=$(hy_hyperhdr_port)
        if [ "$port" = "80" ]; then
            printf 'Web UI: http://%s' "$host"
        else
            printf 'Web UI: http://%s:%s' "$host" "$port"
        fi
    }

    _hyperchromia_header_redraw() {
        _hyperchromia_cpu_percent
        printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s' \
            "$_hyperchromia_cap_sc" \
            "$_hyperchromia_cap_cup_status" "$(_hyperchromia_status_line)" "$_hyperchromia_cap_el" \
            "$_hyperchromia_cap_cup_cpu" "$(_hyperchromia_cpu_line "$_hyperchromia_cpu_pct_result")" "$_hyperchromia_cap_el" \
            "$_hyperchromia_cap_cup_ram" "$(_hyperchromia_ram_line)" "$_hyperchromia_cap_el" \
            "$_hyperchromia_cap_cup_temp" "$(_hyperchromia_temp_line "$(hy_cpu_temp)")" "$_hyperchromia_cap_el" \
            "$_hyperchromia_cap_cup_url" "$(_hyperchromia_url_line)" "$_hyperchromia_cap_el"
        printf '%s' "$_hyperchromia_cap_rc"
    }

    _hyperchromia_draw_rule() {
        local cols
        cols=$(tput cols)
        tput cup "$_hyperchromia_row_rule" 0
        printf '\e[1;37m'
        printf '%*s' "$cols" '' | tr ' ' '-'
        printf '\e[0m'
    }

    _hyperchromia_apply_region() {
        local lines
        lines=$(tput lines)
        printf '\e[?6l'
        tput csr "$_hyperchromia_header_lines" $((lines - 1))
        tput cup "$_hyperchromia_header_lines" 0
    }

    _hyperchromia_full_redraw() {
        _hyperchromia_apply_region
        _hyperchromia_draw_rule
        _hyperchromia_header_redraw
    }

    _hyperchromia_on_winch() {
        _hyperchromia_full_redraw
    }

    _hyperchromia_cleanup() {
        [ -n "$_hyperchromia_updater_pid" ] && kill "$_hyperchromia_updater_pid" 2>/dev/null
        local lines
        lines=$(tput lines)
        tput csr 0 $((lines - 1))
    }

    trap '_hyperchromia_cleanup' EXIT
    trap '_hyperchromia_cleanup; exit 130' INT
    trap '_hyperchromia_cleanup; exit 143' TERM
    trap '_hyperchromia_cleanup; exit 129' HUP
    trap '_hyperchromia_cleanup; exit 131' QUIT
    trap '_hyperchromia_on_winch' WINCH

    _hyperchromia_full_redraw

    ( while true; do _hyperchromia_header_redraw; sleep 1; done ) &
    _hyperchromia_updater_pid=$!
    disown "$_hyperchromia_updater_pid" 2>/dev/null
fi
