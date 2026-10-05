#!/bin/bash
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

hy_cmd_backup() {
    local avail_kb
    avail_kb=$(df -Pk /data 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -z "$avail_kb" ]; then
        echo "Could not determine free space on /data." >&2
        return 1
    fi
    if [ "$avail_kb" -lt 51200 ]; then
        echo "Not enough free space on /data ($((avail_kb / 1024))MB free, need at least 50MB)." >&2
        return 1
    fi

    mkdir -p "$HY_BACKUP_DIR"
    local archive
    archive="$HY_BACKUP_DIR/backup-$(date +%Y%m%d-%H%M%S).tar.gz"

    local -a members=(bin lib .config/HyperHDR)
    [ -d "$HY_SHARE_DIR" ] && members+=(share)

    echo "Creating backup: $archive"
    if ! tar czf "$archive" -C /data/hyperhdr "${members[@]}"; then
        echo "Backup creation failed." >&2
        rm -f "$archive"
        return 1
    fi

    if ! tar tzf "$archive" >/dev/null 2>&1; then
        echo "Backup archive failed integrity check; removing it." >&2
        rm -f "$archive"
        return 1
    fi

    sync
    echo "Backup created and verified: $archive"
}
