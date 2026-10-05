#!/bin/bash
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

hy_booted_from_removable_media && exit 0

echo "hyperchromia-boot-confirm: waiting for hyperhdr to become healthy..." > /dev/tty1 2>/dev/null || true

if hy_wait_for_active hyperhdr 90; then
    mkdir -p "$HY_OS_ESP_MOUNT"
    if mount -t vfat -o rw "/dev/disk/by-partlabel/$HY_OS_ESP_LABEL" "$HY_OS_ESP_MOUNT"; then
        grub-editenv "$HY_OS_GRUBENV" set hyperchromia_pending=
        umount "$HY_OS_ESP_MOUNT"
    fi

    if [ -f "$HY_OS_UPDATE_STATE" ]; then
        version=$(jq -r '.last_attempted_version' "$HY_OS_UPDATE_STATE" 2>/dev/null)
        mkdir -p "$HY_OS_STATE_DIR"
        printf '{"last_attempted_version":"%s","result":"confirmed"}\n' "$version" > "$HY_OS_UPDATE_STATE"
    fi
else
    echo "hyperchromia-boot-confirm: hyperhdr did not become healthy in time; rebooting to let GRUB's boot-counting decide." > /dev/tty1 2>/dev/null || true
    sleep 3
    reboot
fi
