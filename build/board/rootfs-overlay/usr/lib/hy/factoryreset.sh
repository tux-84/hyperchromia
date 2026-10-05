#!/bin/bash
# shellcheck disable=SC1091,SC2153
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

hy_cmd_factoryreset() {
    printf '\e[31m'
    cat <<'EOF'
WARNING: FACTORY RESET

This will PERMANENTLY:
  - Erase the installed HyperHDR binary and replace it with the
    factory-default version baked into this image.
  - Erase all HyperHDR configuration and settings
    (/data/hyperhdr/.config/HyperHDR) and reset them to factory defaults.
  - Delete ALL backup archives under /data/hyperhdr/backups.
  - Reset the hostname and network configuration (static IP, etc.)
    back to factory defaults.

This action cannot be undone.
EOF
    printf '\e[0m'

    local ans
    read -r -p "Type 'yes' to confirm factory reset: " ans
    if [ "$ans" != "yes" ]; then
        echo "Cancelled. No changes made."
        return 0
    fi

    if [ ! -e "$HY_FACTORY_SEED/bin/hyperhdr" ] || [ ! -d "$HY_FACTORY_SEED/lib" ]; then
        echo "Factory seed at $HY_FACTORY_SEED is missing or looks incomplete; aborting" >&2
        echo "to avoid wiping /data with no valid seed to restore from." >&2
        return 1
    fi

    echo "Stopping hyperhdr..."
    systemctl stop hyperhdr

    echo "Wiping HyperHDR data..."
    rm -rf "$HY_BIN_DIR" "$HY_DATA_LIB_DIR" "$HY_CONFIG_DIR" "$HY_BACKUP_DIR"
    mkdir -p "$HY_CONFIG_DIR" "$HY_BACKUP_DIR"

    echo "Resetting hostname and network configuration to factory defaults..."
    local d slug upper
    for d in etc var/lib; do
        slug=$(echo "$d" | tr / -)
        upper="$HY_OVERLAY_BASE/$slug/upper"
        [ -d "$upper" ] && rm -rf "${upper:?}"/.[!.]* "${upper:?}"/..?* "${upper:?}"/* 2>/dev/null
    done

    sync
    echo "Factory reset staged. Rebooting to complete it..."
    reboot
}
