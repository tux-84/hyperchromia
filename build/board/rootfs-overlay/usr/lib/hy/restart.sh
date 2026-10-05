#!/bin/bash
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

hy_cmd_restart() {
    echo "Restarting hyperhdr..."
    systemctl restart hyperhdr

    if hy_wait_for_active hyperhdr 10; then
        echo "hyperhdr restarted successfully (active)."
    else
        echo "hyperhdr did not become active within 10s." >&2
        systemctl status hyperhdr --no-pager -l >&2
        return 1
    fi
}
