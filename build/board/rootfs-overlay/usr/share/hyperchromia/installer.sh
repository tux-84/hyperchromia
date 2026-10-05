#!/bin/bash
# shellcheck disable=SC1091
set -e
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"

HY_INSTALLER_ESP_SIZE_MB=96
HY_INSTALLER_ROOT_SIZE_MB=1024

hy_installer_infobox() {
    TERM=linux dialog --backtitle "HyperChromia Installer" --infobox "$1" 8 60 > /dev/tty1 2>/dev/tty1
}

hy_installer_fail() {
    TERM=linux dialog --backtitle "HyperChromia Installer" --title "ERROR" \
        --infobox "$*\n\nInstall did not complete. Halting here -- fix the issue and reboot to retry." 10 70 \
        > /dev/tty1 2>/dev/tty1
    while true; do
        sleep 3600
    done
}

hy_installer_copy_with_progress() {
    local src="$1" dst="$2" label="$3"
    local chunk_mb=4
    local chunk_bytes=$(( chunk_mb * 1024 * 1024 ))
    local total total_chunks rc

    total=$(wc -c < "$src" | tr -d ' ')
    total_chunks=$(( (total + chunk_bytes - 1) / chunk_bytes ))

    (
        local i=0 written pct last_pct=-1
        while [ "$i" -lt "$total_chunks" ]; do
            dd if="$src" of="$dst" bs="${chunk_mb}M" skip="$i" seek="$i" count=1 \
                conv=notrunc,fsync 2>/dev/null || exit 1
            i=$((i + 1))
            written=$(( i * chunk_bytes ))
            [ "$written" -gt "$total" ] && written=$total
            pct=$(( written * 100 / total ))
            if [ "$pct" != "$last_pct" ]; then
                echo "$pct"
                last_pct="$pct"
            fi
        done
    ) | TERM=linux dialog --backtitle "HyperChromia Installer" --title "Installing" \
        --gauge "$label" 10 70 0 > /dev/tty1 2>/dev/tty1

    rc=${PIPESTATUS[0]}
    return "$rc"
}

hy_installer_part() {
    local disk="$1" num="$2"
    case "$disk" in
        *[0-9]) echo "/dev/${disk}p${num}" ;;
        *) echo "/dev/${disk}${num}" ;;
    esac
}

hy_installer_find_target() {
    local boot_disk="$1" disk candidates="" count=0

    for disk in $(lsblk -dn -o NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}'); do
        [ "$disk" = "$boot_disk" ] && continue
        case "$(readlink -f "/sys/block/$disk" 2>/dev/null)" in
            */usb*/*) continue ;;
        esac
        candidates="$candidates $disk"
        count=$((count + 1))
    done

    if [ "$count" -eq 0 ]; then
        hy_installer_infobox "No internal disk found to install onto."
        return 1
    fi

    if [ "$count" -eq 1 ]; then
        echo "$candidates" | tr -d ' '
        return 0
    fi

    local i=0 disk_list=() menu_args=() size model choice tmpfile chosen chosen_size chosen_model red_rc
    for disk in $candidates; do
        i=$((i + 1))
        disk_list+=("$disk")
        size=$(lsblk -dn -o SIZE "/dev/$disk" 2>/dev/null)
        model=$(lsblk -dn -o MODEL "/dev/$disk" 2>/dev/null)
        menu_args+=("$i" "/dev/$disk  ${size:-unknown size}  ${model:-unknown model}")
    done

    red_rc=$(mktemp)
    cat > "$red_rc" <<'EOF'
title_color = (RED,WHITE,ON)
border_color = (RED,WHITE,ON)
button_active_color = (WHITE,RED,ON)
button_label_active_color = (WHITE,RED,ON)
EOF

    while true; do
        tmpfile=$(mktemp)
        TERM=linux dialog --backtitle "HyperChromia Installer" \
            --title "Select install disk" \
            --nocancel \
            --menu "Multiple internal disks were found. Choose one to install HyperChromia onto." \
            20 70 "$i" "${menu_args[@]}" \
            2>"$tmpfile" <"/dev/tty1" >"/dev/tty1"
        choice=$(cat "$tmpfile")
        rm -f "$tmpfile"
        chosen="${disk_list[$((choice - 1))]}"
        chosen_size=$(lsblk -dn -o SIZE "/dev/$chosen" 2>/dev/null)
        chosen_model=$(lsblk -dn -o MODEL "/dev/$chosen" 2>/dev/null)

        if DIALOGRC="$red_rc" TERM=linux dialog --backtitle "HyperChromia Installer" \
            --title "CONFIRM -- THIS WILL ERASE THE DISK" \
            --defaultno \
            --yesno "Install HyperChromia onto /dev/$chosen (${chosen_size:-unknown size} ${chosen_model:-unknown model})?\n\nALL DATA ON THIS DISK WILL BE PERMANENTLY ERASED.\n\nAre you sure?" \
            12 70 \
            <"/dev/tty1" >"/dev/tty1" 2>/dev/tty1; then
            break
        fi
    done
    rm -f "$red_rc"

    echo "$chosen"
}

hy_installer_run() {
    local boot_disk target_disk esp_src

    hy_booted_from_removable_media || return 0
    boot_disk=$(hy_boot_disk) || return 0

    hy_installer_infobox "Booted from removable media (/dev/$boot_disk) -- looking for an install target."

    systemctl stop data.mount >/dev/null 2>&1 || true
    systemctl mask data.mount >/dev/null 2>&1 || true

    target_disk=$(hy_installer_find_target "$boot_disk") || \
        hy_installer_fail "No internal disk available to install onto."

    hy_installer_infobox "Installing HyperChromia onto /dev/$target_disk. This will ERASE that disk."

    sgdisk --zap-all "/dev/$target_disk" >/dev/null 2>&1 || \
        hy_installer_fail "failed to wipe the partition table on /dev/$target_disk."
    sgdisk \
        -n 1:0:+${HY_INSTALLER_ESP_SIZE_MB}M -t 1:ef00 -c 1:boot \
        -n 2:0:+${HY_INSTALLER_ROOT_SIZE_MB}M -t 2:8300 -c 2:rootA \
        -n 3:0:+${HY_INSTALLER_ROOT_SIZE_MB}M -t 3:8300 -c 3:rootB \
        -n 4:0:0 -t 4:8300 -c 4:data \
        "/dev/$target_disk" >/dev/null 2>&1 || \
        hy_installer_fail "failed to create partitions on /dev/$target_disk."
    local esp_dev rootA_dev rootB_dev data_dev
    esp_dev=$(hy_installer_part "$target_disk" 1)
    rootA_dev=$(hy_installer_part "$target_disk" 2)
    rootB_dev=$(hy_installer_part "$target_disk" 3)
    data_dev=$(hy_installer_part "$target_disk" 4)

    local dev part_ready i size
    for dev in "$esp_dev" "$rootA_dev" "$rootB_dev" "$data_dev"; do
        part_ready=0
        i=0
        while [ "$i" -lt 20 ]; do
            partprobe "/dev/$target_disk" >/dev/null 2>&1 || true
            udevadm settle --timeout=10 2>/dev/null || true
            size=$(blockdev --getsize64 "$dev" 2>/dev/null || echo 0)
            if [ -n "$size" ] && [ "$size" -gt 0 ] 2>/dev/null; then
                part_ready=1
                break
            fi
            sleep 1
            i=$((i + 1))
        done
        [ "$part_ready" -eq 1 ] || \
            hy_installer_fail "the kernel never recognized $dev after repartitioning /dev/$target_disk (device size stayed 0). Try a different disk/port, or power-cycle the machine and retry."
    done

    hy_installer_infobox "Formatting boot and data partitions..."
    for dev in "$esp_dev" "$rootA_dev" "$rootB_dev" "$data_dev"; do
        umount "$dev" 2>/dev/null || true
    done
    mkfs.vfat -F32 -n BOOT "$esp_dev" >/dev/tty1 2>&1 || \
        hy_installer_fail "failed to format the boot partition ($esp_dev)."
    mkfs.ext4 -F -F -L data "$data_dev" >/dev/tty1 2>&1 || \
        hy_installer_fail "failed to format the data partition ($data_dev)."

    local copy_rc

    hy_installer_infobox "Copying system onto the new disk..."
    esp_src=$(hy_installer_part "$boot_disk" 1)
    mkdir -p /run/hyperchromia-installer-src /run/hyperchromia-installer-dst
    mount -t vfat -o ro "$esp_src" /run/hyperchromia-installer-src || \
        hy_installer_fail "failed to mount the live media's boot partition ($esp_src)."
    mount -t vfat -o rw "$esp_dev" /run/hyperchromia-installer-dst || \
        hy_installer_fail "failed to mount the new disk's boot partition ($esp_dev)."

    (
        echo 0
        cp -a /run/hyperchromia-installer-src/EFI /run/hyperchromia-installer-dst/ || exit 1
        echo 16
        cp -a /run/hyperchromia-installer-src/bzImage-a /run/hyperchromia-installer-dst/ || exit 1
        echo 33
        cp -a /run/hyperchromia-installer-src/bzImage-b /run/hyperchromia-installer-dst/ || exit 1
        echo 50
        cp -a /run/hyperchromia-installer-src/initrd-a /run/hyperchromia-installer-dst/ || exit 1
        echo 66
        cp -a /run/hyperchromia-installer-src/initrd-b /run/hyperchromia-installer-dst/ || exit 1
        echo 83
        cp -f /usr/share/hyperchromia/grub-installed.cfg /run/hyperchromia-installer-dst/EFI/debian/grub.cfg || exit 1
        echo 100
    ) | TERM=linux dialog --backtitle "HyperChromia Installer" --title "Installing" \
        --gauge "Copying system files..." 10 70 0 > /dev/tty1 2>/dev/tty1
    copy_rc=${PIPESTATUS[0]}

    if [ "$copy_rc" -ne 0 ]; then
        umount /run/hyperchromia-installer-src || true
        umount /run/hyperchromia-installer-dst || true
        hy_installer_fail "failed copying boot files onto the new disk's boot partition."
    fi
    umount /run/hyperchromia-installer-src || true
    umount /run/hyperchromia-installer-dst || true

    local active_root_src src_sum rootA_sum rootB_sum
    active_root_src=$(findmnt -no SOURCE / 2>/dev/null)
    hy_installer_infobox "Computing source checksum..."
    src_sum=$(sha256sum "$active_root_src" | cut -d' ' -f1)

    hy_installer_copy_with_progress "$active_root_src" "$rootA_dev" "Copying rootA..." || \
        hy_installer_fail "failed while copying rootA."
    hy_installer_infobox "Verifying rootA checksum..."
    rootA_sum=$(sha256sum "$rootA_dev" | cut -d' ' -f1)
    if [ "$rootA_sum" != "$src_sum" ]; then
        hy_installer_fail "verification failed copying rootA -- checksum mismatch. Retry, or try a different USB stick/port."
    fi

    hy_installer_copy_with_progress "$active_root_src" "$rootB_dev" "Copying rootB..." || \
        hy_installer_fail "failed while copying rootB."
    hy_installer_infobox "Verifying rootB checksum..."
    rootB_sum=$(sha256sum "$rootB_dev" | cut -d' ' -f1)
    if [ "$rootB_sum" != "$src_sum" ]; then
        hy_installer_fail "verification failed copying rootB -- checksum mismatch. Retry, or try a different USB stick/port."
    fi

    mount -t vfat -o rw "$esp_dev" /run/hyperchromia-installer-dst
    grub-editenv "/run/hyperchromia-installer-dst/EFI/debian/grubenv" create
    grub-editenv "/run/hyperchromia-installer-dst/EFI/debian/grubenv" set \
        hyperchromia_active_slot=a hyperchromia_pending=
    umount /run/hyperchromia-installer-dst || true

    sync

    local done_msg="Install complete.\n\nPress Enter to reboot. Wait until the machine shuts down, then remove the USB stick before it boots back up."

    TERM=linux dialog --backtitle "HyperChromia Installer" --title "Install complete" \
        --msgbox "$done_msg" 14 70 > /dev/tty1 2>/dev/tty1 < /dev/tty1
    reboot
}

if [ "$1" = "--check-boot-media" ]; then
    hy_installer_run
fi
