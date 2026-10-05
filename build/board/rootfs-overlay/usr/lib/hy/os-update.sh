#!/bin/bash
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

hy_osupdate_verify_manifest() {
    local source_dir="$1"
    local manifest="$source_dir/manifest.json"
    [ -f "$manifest" ] || return 1
    [ "$(jq -r '.hyperchromia_update' "$manifest" 2>/dev/null)" = "true" ] || return 1

    local path expected actual
    while IFS=$'\t' read -r path expected; do
        [ -z "$path" ] && continue
        actual=$(sha256sum "$source_dir/$path" 2>/dev/null | awk '{print $1}')
        [ "$actual" = "$expected" ] || return 1
    done < <(jq -r '.files[] | [.path, .sha256] | @tsv' "$manifest" 2>/dev/null)

    jq -r '.hyperchromia_version' "$manifest"
}

hy_osupdate_other_slot() {
    [ "$1" = "a" ] && echo "b" || echo "a"
}

hy_osupdate_slot_root_label() {
    [ "$1" = "a" ] && echo "$HY_OS_ROOTA_LABEL" || echo "$HY_OS_ROOTB_LABEL"
}

hy_osupdate_ui_write() {
    { tee /dev/tty1 > /dev/ttyS0; } 2>/dev/null
}

hy_osupdate_ui_cols() {
    tput cols 2>/dev/null || echo 80
}

hy_osupdate_ui_rows() {
    tput lines 2>/dev/null || echo 24
}

hy_osupdate_ui_center() {
    local text="$1" cols pad
    cols=$(hy_osupdate_ui_cols)
    pad=$(( (cols - ${#text}) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf '%*s%s' "$pad" '' "$text"
}

hy_osupdate_ui_init() {
    local from_ver="$1" to_ver="$2" rows mid

    rows=$(hy_osupdate_ui_rows)
    mid=$(( rows / 2 ))
    HY_OSUPDATE_UI_BAR_ROW=$(( mid + 1 ))
    HY_OSUPDATE_UI_STATUS_ROW=$(( mid + 3 ))

    {
        printf '\e[2J\e[H'
        printf '\e[%d;1H' "$(( mid - 3 ))"
        hy_osupdate_ui_center "HyperChromia Update"
        printf '\e[%d;1H' "$(( mid - 1 ))"
        hy_osupdate_ui_center "Updating from $from_ver to $to_ver"
        printf '\n\n\n\n'
        hy_osupdate_ui_center "Do NOT power off or unplug the device during this update."
    } | hy_osupdate_ui_write
}

hy_osupdate_ui_status() {
    {
        printf '\e[%d;1H\e[2K' "$HY_OSUPDATE_UI_STATUS_ROW"
        hy_osupdate_ui_center "$1"
    } | hy_osupdate_ui_write
}

hy_osupdate_ui_bar_fill() {
    local n="$1" ch="$2" out="" i=0
    while [ "$i" -lt "$n" ]; do out="${out}${ch}"; i=$((i + 1)); done
    echo "$out"
}

hy_osupdate_ui_progress() {
    local pct="$1" barwidth=40 filled empty line
    filled=$(( pct * barwidth / 100 ))
    empty=$(( barwidth - filled ))
    line="[$(hy_osupdate_ui_bar_fill "$filled" '#')$(hy_osupdate_ui_bar_fill "$empty" '-')] ${pct}%"
    {
        printf '\e[%d;1H\e[2K' "$HY_OSUPDATE_UI_BAR_ROW"
        hy_osupdate_ui_center "$line"
    } | hy_osupdate_ui_write
}

hy_osupdate_countdown() {
    local n=5
    while [ "$n" -gt 0 ]; do
        hy_osupdate_ui_status "Starting in ${n}s..."
        sleep 1
        n=$((n - 1))
    done
}

hy_osupdate_copy_with_progress() {
    local src="$1" dst="$2"
    local chunk_mb=4
    local chunk_bytes=$(( chunk_mb * 1024 * 1024 ))
    local total i=0 written pct total_chunks

    total=$(wc -c < "$src" | tr -d ' ')
    total_chunks=$(( (total + chunk_bytes - 1) / chunk_bytes ))

    while [ "$i" -lt "$total_chunks" ]; do
        dd if="$src" of="$dst" bs="${chunk_mb}M" skip="$i" seek="$i" count=1 conv=notrunc 2>/dev/null || return 1
        i=$((i + 1))
        written=$(( i * chunk_bytes ))
        [ "$written" -gt "$total" ] && written=$total
        pct=$(( written * 100 / total ))
        hy_osupdate_ui_progress "$pct"
    done
}

hy_osupdate_apply() {
    local source_dir="$1"
    local version="$2"
    local from_version="$3"
    local active inactive inactive_label inactive_dev size actual_sum expected_sum

    hy_osupdate_ui_init "$from_version" "$version"
    hy_osupdate_countdown

    hy_osupdate_ui_status "Preparing update..."
    mkdir -p "$HY_OS_ESP_MOUNT"
    if ! mount -t vfat -o rw "/dev/disk/by-partlabel/$HY_OS_ESP_LABEL" "$HY_OS_ESP_MOUNT"; then
        hy_osupdate_ui_status "Update failed: could not mount the boot partition. Continuing normal boot."
        sleep 5
        return 1
    fi

    active=$(grub-editenv "$HY_OS_GRUBENV" list 2>/dev/null | sed -n 's/^hyperchromia_active_slot=//p')
    [ -z "$active" ] && active="a"
    inactive=$(hy_osupdate_other_slot "$active")
    inactive_label=$(hy_osupdate_slot_root_label "$inactive")
    inactive_dev="/dev/disk/by-partlabel/$inactive_label"

    mkdir -p "$HY_OS_STATE_DIR"
    printf '{"last_attempted_version":"%s","result":"pending"}\n' "$version" > "$HY_OS_UPDATE_STATE"
    sync

    hy_osupdate_ui_status "Writing new system image..."
    if ! hy_osupdate_copy_with_progress "$source_dir/rootfs.squashfs" "$inactive_dev"; then
        hy_osupdate_ui_status "Update failed while writing. Continuing normal boot."
        umount "$HY_OS_ESP_MOUNT"
        sleep 5
        return 1
    fi

    hy_osupdate_ui_status "Verifying written data..."
    size=$(wc -c < "$source_dir/rootfs.squashfs" | tr -d ' ')
    expected_sum=$(sha256sum "$source_dir/rootfs.squashfs" | awk '{print $1}')
    actual_sum=$(head -c "$size" "$inactive_dev" | sha256sum | awk '{print $1}')
    if [ "$actual_sum" != "$expected_sum" ]; then
        hy_osupdate_ui_status "Update failed verification. Continuing normal boot."
        umount "$HY_OS_ESP_MOUNT"
        sleep 5
        return 1
    fi

    hy_osupdate_ui_status "Installing new kernel..."
    cp "$source_dir/bzImage" "$HY_OS_ESP_MOUNT/bzImage-$inactive.new"
    mv "$HY_OS_ESP_MOUNT/bzImage-$inactive.new" "$HY_OS_ESP_MOUNT/bzImage-$inactive"
    cp "$source_dir/initramfs.cpio.gz" "$HY_OS_ESP_MOUNT/initrd-$inactive.new"
    mv "$HY_OS_ESP_MOUNT/initrd-$inactive.new" "$HY_OS_ESP_MOUNT/initrd-$inactive"

    grub-editenv "$HY_OS_GRUBENV" set "hyperchromia_active_slot=$inactive" "hyperchromia_pending="

    umount "$HY_OS_ESP_MOUNT"
    sync

    hy_osupdate_ui_progress 100
    hy_osupdate_ui_status "Update complete. Rebooting into HyperChromia $version..."
    sleep 3
    reboot
}

hy_osupdate_mark_pending_failed() {
    local running_version="$1"
    local last_version last_result
    [ -f "$HY_OS_UPDATE_STATE" ] || return 0
    last_version=$(jq -r '.last_attempted_version' "$HY_OS_UPDATE_STATE" 2>/dev/null)
    last_result=$(jq -r '.result' "$HY_OS_UPDATE_STATE" 2>/dev/null)
    if [ "$last_result" = "pending" ] && [ "$last_version" != "$running_version" ]; then
        printf '{"last_attempted_version":"%s","result":"failed"}\n' "$last_version" > "$HY_OS_UPDATE_STATE"
    fi
}

hy_osupdate_already_attempted_and_failed() {
    local version="$1"
    local last_version last_result
    [ -f "$HY_OS_UPDATE_STATE" ] || return 1
    last_version=$(jq -r '.last_attempted_version' "$HY_OS_UPDATE_STATE" 2>/dev/null)
    last_result=$(jq -r '.result' "$HY_OS_UPDATE_STATE" 2>/dev/null)
    [ "$last_version" = "$version" ] && [ "$last_result" = "failed" ]
}

hy_osupdate_check_boot_media() {
    local disk devtype version running_version candidates

    running_version=$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"')
    hy_osupdate_mark_pending_failed "$running_version"

    candidates=$(lsblk -dn -o NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}')
    for disk in $candidates; do
        devtype=$(blkid -o value -s TYPE "/dev/$disk" 2>/dev/null)
        [ "$devtype" = "squashfs" ] || continue

        mkdir -p "$HY_OS_UPDATE_MOUNT"
        mount -t squashfs -o ro "/dev/$disk" "$HY_OS_UPDATE_MOUNT" 2>/dev/null || continue

        version=$(hy_osupdate_verify_manifest "$HY_OS_UPDATE_MOUNT")
        if [ -z "$version" ] || [ "$version" = "$running_version" ] \
            || hy_osupdate_already_attempted_and_failed "$version"; then
            umount "$HY_OS_UPDATE_MOUNT"
            continue
        fi

        hy_osupdate_apply "$HY_OS_UPDATE_MOUNT" "$version" "$running_version"
        umount "$HY_OS_UPDATE_MOUNT" 2>/dev/null
    done
}

if [ "$1" = "--check-boot-media" ]; then
    hy_osupdate_check_boot_media
fi
