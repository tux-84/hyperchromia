#!/bin/bash
HY_LIB_DIR="${HY_LIB_DIR:-/usr/lib/hy}"
source "$HY_LIB_DIR/common.sh"
source "$HY_LIB_DIR/backup.sh"

hy_upgrade_parse_releases() {
    jq -r '.[] | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$")) | .tag_name as $tag
        | .assets[] | select(.name | test("-Linux-x86_64\\.tar\\.gz$"))
        | [$tag, .name, .browser_download_url, .digest] | @tsv'
}

hy_cmd_upgrade() {
    local cur_ver
    cur_ver=$(hy_current_version)
    if [ -z "$cur_ver" ]; then
        echo "Could not determine the currently installed HyperHDR version." >&2
        return 1
    fi
    echo "Current version: $cur_ver"
    echo "Checking for updates..."

    local json
    json=$(wget -qO- "$HY_GITHUB_API")
    if [ -z "$json" ]; then
        echo "Could not reach GitHub (no internet connectivity or API error)." >&2
        return 1
    fi

    local records
    records=$(echo "$json" | hy_upgrade_parse_releases)
    if [ -z "$records" ]; then
        echo "No usable releases found." >&2
        return 1
    fi

    local -a tags names urls digests
    local seen=" "
    local tag name url digest
    while IFS=$'\t' read -r tag name url digest; do
        [ -z "$tag" ] && continue
        case "$seen" in
            *" $tag "*) continue ;;
        esac
        if hy_version_gt "$tag" "$cur_ver"; then
            tags+=("$tag"); names+=("$name"); urls+=("$url"); digests+=("$digest")
            seen="$seen$tag "
        fi
    done <<< "$records"

    if [ "${#tags[@]}" -eq 0 ]; then
        echo "Already running the latest version ($cur_ver)."
        return 0
    fi

    echo "Newer versions available:"
    local i
    for i in "${!tags[@]}"; do
        printf "%2d) %s\n" "$((i + 1))" "${tags[$i]#v}"
    done
    echo " q) Cancel"

    local choice
    read -r -p "Select a version to install: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#tags[@]}" ]; then
        echo "Cancelled."
        return 0
    fi

    local idx=$((choice - 1))
    local sel_tag="${tags[$idx]}" sel_name="${names[$idx]}" sel_url="${urls[$idx]}" sel_digest="${digests[$idx]}"

    echo "You selected ${sel_tag#v}. This will download, verify and install the"
    echo "update, then REBOOT the system."
    if ! hy_confirm_yn "Proceed with upgrade to ${sel_tag#v}? [y/N] "; then
        echo "Cancelled. No changes made."
        return 0
    fi

    echo "Backing up the current install first..."
    if ! hy_cmd_backup; then
        echo "Backup failed; aborting upgrade, live install untouched." >&2
        return 1
    fi

    rm -rf "$HY_STAGING_DIR"
    mkdir -p "$HY_STAGING_DIR"
    local archive_path="$HY_STAGING_DIR/$sel_name"

    echo "Downloading $sel_name..."
    if ! wget -qO "$archive_path" "$sel_url"; then
        echo "Download failed; aborting, live install untouched." >&2
        rm -rf "$HY_STAGING_DIR"
        return 1
    fi

    local expected_sum="${sel_digest#sha256:}"
    if [ -z "$expected_sum" ]; then
        echo "No usable sha256 digest from GitHub for this asset; aborting for safety." >&2
        rm -rf "$HY_STAGING_DIR"
        return 1
    fi
    local actual_sum
    actual_sum=$(sha256sum "$archive_path" | awk '{print $1}')
    if [ "$actual_sum" != "$expected_sum" ]; then
        echo "Checksum mismatch (expected $expected_sum, got $actual_sum); aborting, live install untouched." >&2
        rm -rf "$HY_STAGING_DIR"
        return 1
    fi
    echo "Checksum verified."

    local extract_dir="$HY_STAGING_DIR/extracted"
    mkdir -p "$extract_dir"
    if ! tar xzf "$archive_path" -C "$extract_dir"; then
        echo "Extraction failed; aborting, live install untouched." >&2
        rm -rf "$HY_STAGING_DIR"
        return 1
    fi

    local staged_bin
    staged_bin=$(find "$extract_dir" -type f -name hyperhdr -perm -u+x 2>/dev/null | head -n1)
    [ -z "$staged_bin" ] && staged_bin=$(find "$extract_dir" -type f -name hyperhdr 2>/dev/null | head -n1)
    if [ -z "$staged_bin" ]; then
        echo "Could not find a hyperhdr binary in the downloaded archive; aborting." >&2
        rm -rf "$HY_STAGING_DIR"
        return 1
    fi
    local staged_root
    staged_root=$(dirname "$staged_bin")

    local lib_path=""
    if [ -d "$(dirname "$staged_root")/lib" ]; then
        lib_path="$(dirname "$staged_root")/lib"
    elif [ -d "$staged_root/lib" ]; then
        lib_path="$staged_root/lib"
    fi

    local share_path=""
    if [ -d "$(dirname "$staged_root")/share" ]; then
        share_path="$(dirname "$staged_root")/share"
    elif [ -d "$staged_root/share" ]; then
        share_path="$staged_root/share"
    fi

    echo "Smoke-testing the staged binary..."
    local version_out smoke_ld=""
    if [ -n "$lib_path" ]; then
        smoke_ld=$(find "$lib_path" -type d 2>/dev/null | tr '\n' ':')
    fi
    if [ -n "$smoke_ld" ]; then
        version_out=$(LD_LIBRARY_PATH="${smoke_ld}${LD_LIBRARY_PATH}" "$staged_bin" --version 2>&1)
    else
        version_out=$("$staged_bin" --version 2>&1)
    fi
    if ! echo "$version_out" | grep -q 'Version'; then
        echo "Smoke test failed; staged binary did not report a version." >&2
        echo "Aborting upgrade, live install left completely untouched." >&2
        rm -rf "$HY_STAGING_DIR"
        return 1
    fi
    echo "Smoke test passed."

    echo "Stopping hyperhdr..."
    systemctl stop hyperhdr

    local old_bin="${HY_BIN_DIR}.old.$$"
    local old_lib="${HY_DATA_LIB_DIR}.old.$$"
    local old_share="${HY_SHARE_DIR}.old.$$"
    [ -d "$HY_BIN_DIR" ] && mv "$HY_BIN_DIR" "$old_bin"
    [ -d "$HY_DATA_LIB_DIR" ] && mv "$HY_DATA_LIB_DIR" "$old_lib"
    [ -d "$HY_SHARE_DIR" ] && mv "$HY_SHARE_DIR" "$old_share"

    hy_upgrade_rollback() {
        echo "Rolling back to the previous install." >&2
        rm -rf "$HY_BIN_DIR" "$HY_DATA_LIB_DIR" "$HY_SHARE_DIR"
        [ -d "$old_bin" ] && mv "$old_bin" "$HY_BIN_DIR"
        [ -d "$old_lib" ] && mv "$old_lib" "$HY_DATA_LIB_DIR"
        [ -d "$old_share" ] && mv "$old_share" "$HY_SHARE_DIR"
        systemctl start hyperhdr
        rm -rf "$HY_STAGING_DIR"
    }

    if ! mv "$staged_root" "$HY_BIN_DIR"; then
        echo "Failed to install the new binary." >&2
        hy_upgrade_rollback
        return 1
    fi

    if [ -n "$lib_path" ]; then
        if ! mv "$lib_path" "$HY_DATA_LIB_DIR"; then
            echo "Failed to install the new libraries." >&2
            rm -rf "$HY_BIN_DIR"
            hy_upgrade_rollback
            return 1
        fi
    elif [ -d "$old_lib" ]; then
        mv "$old_lib" "$HY_DATA_LIB_DIR"
    fi

    if [ -n "$share_path" ]; then
        if ! mv "$share_path" "$HY_SHARE_DIR"; then
            echo "Failed to install the new web resources." >&2
            rm -rf "$HY_BIN_DIR" "$HY_DATA_LIB_DIR"
            hy_upgrade_rollback
            return 1
        fi
    elif [ -d "$old_share" ]; then
        mv "$old_share" "$HY_SHARE_DIR"
    fi

    rm -rf "$old_bin" "$old_lib" "$old_share" "$HY_STAGING_DIR"

    sync
    echo "Upgrade to ${sel_tag#v} installed. Rebooting..."
    reboot
}
