#!/bin/bash
# shellcheck disable=SC1091
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

hy_cmd_locale() {
    if [ "$HY_PRESEED_ACTIVE" = "1" ]; then
        if [ -n "$HY_PRESEED_LOCALE_KEYMAP" ] && loadkeys "$HY_PRESEED_LOCALE_KEYMAP" 2>/dev/null; then
            echo "KEYMAP=$HY_PRESEED_LOCALE_KEYMAP" > /etc/vconsole.conf
            sync
        elif [ -n "$HY_PRESEED_LOCALE_KEYMAP" ]; then
            echo "locale: preseed keymap '$HY_PRESEED_LOCALE_KEYMAP' is invalid, skipping." >&2
        fi
        return 0
    fi

    local current
    current=$(awk -F= '/^KEYMAP=/{print $2}' /etc/vconsole.conf 2>/dev/null)
    echo "Current console keymap: ${current:-us (default)}"
    echo

    local keymaps
    mapfile -t keymaps < <(find /usr/share/keymaps -type f \( -name '*.map.gz' -o -name '*.map' \) 2>/dev/null \
        | sed -E 's#.*/##; s/\.map(\.gz)?$//' | sort -u)
    if [ "${#keymaps[@]}" -eq 0 ]; then
        echo "No keymaps found under /usr/share/keymaps." >&2
        return 1
    fi

    local filter matches km
    while true; do
        read -r -p "Search keymaps (e.g. 'de', 'latin1'), or leave empty to list all ${#keymaps[@]}: " filter
        if [ -z "$filter" ]; then
            matches=("${keymaps[@]}")
        else
            matches=()
            local k
            for k in "${keymaps[@]}"; do
                case "$k" in
                    *"$filter"*) matches+=("$k") ;;
                esac
            done
        fi
        if [ "${#matches[@]}" -eq 0 ]; then
            echo "No keymaps match '$filter'. Try again."
            continue
        fi
        break
    done

    echo
    local i
    for i in "${!matches[@]}"; do
        printf '%3d) %s\n' "$((i + 1))" "${matches[$i]}"
    done
    echo

    local choice
    read -r -p "Pick a number (or empty to cancel): " choice
    if [ -z "$choice" ]; then
        echo "Cancelled."
        return 0
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#matches[@]}" ]; then
        echo "Invalid selection." >&2
        return 1
    fi
    km="${matches[$((choice - 1))]}"

    if ! loadkeys "$km" 2>/dev/null; then
        echo "Unknown or invalid keymap: $km" >&2
        return 1
    fi

    echo "Applied '$km' to this console now -- try typing on your keyboard to check it looks right"
    echo "(this matters before you run 'hy password', so you type what you expect to type)."
    if hy_confirm_yn "Make '$km' permanent (survives reboot)? [y/N] "; then
        echo "KEYMAP=$km" > /etc/vconsole.conf
        sync
        echo "Saved. '$km' will be used on future boots."
    else
        echo "Not saved -- this is only applied to the current session."
    fi
}
