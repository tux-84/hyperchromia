#!/bin/bash
# shellcheck disable=SC1091,SC2153
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

hy_cmd_restore() {
    local archive="$1"

    if [ -z "$archive" ]; then
        archive=$(find "$HY_BACKUP_DIR" -maxdepth 1 -name 'backup-*.tar.gz' 2>/dev/null | sort | tail -n1)
        if [ -z "$archive" ]; then
            echo "No backup archives found in $HY_BACKUP_DIR." >&2
            return 1
        fi
        echo "Using most recent backup: $archive"
    fi

    if [ ! -f "$archive" ]; then
        echo "Archive not found: $archive" >&2
        return 1
    fi

    if ! tar tzf "$archive" >/dev/null 2>&1; then
        echo "Archive is not a valid, readable tar file: $archive" >&2
        return 1
    fi

    echo "Stopping hyperhdr..."
    systemctl stop hyperhdr

    echo "Restoring from $archive..."
    rm -rf "$HY_BIN_DIR" "$HY_DATA_LIB_DIR" "$HY_SHARE_DIR" "$HY_CONFIG_DIR"
    if ! tar xzf "$archive" -C /data/hyperhdr; then
        echo "Restore extraction failed." >&2
        systemctl start hyperhdr
        return 1
    fi
    sync

    echo "Starting hyperhdr..."
    systemctl start hyperhdr
    if hy_wait_for_active hyperhdr 10; then
        echo "Restore complete; hyperhdr is active."
    else
        echo "Restore complete but hyperhdr did not become active within 10s." >&2
        return 1
    fi
}
