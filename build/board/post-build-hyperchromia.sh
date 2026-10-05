#!/bin/sh
# shellcheck disable=SC2153
set -e

TARGET_DIR="$1"

mkdir -p "$BINARIES_DIR/efi-part/EFI/debian"
cp -f "$BR2_EXTERNAL_HYPERHDR_PATH/board/grub-hyperchromia.cfg" "$BINARIES_DIR/efi-part/EFI/debian/grub.cfg"

mkdir -p "$TARGET_DIR/usr/share/hyperchromia"
cp -f "$BR2_EXTERNAL_HYPERHDR_PATH/board/grub-hyperchromia-installed.cfg" "$TARGET_DIR/usr/share/hyperchromia/grub-installed.cfg"

"$HOST_DIR/bin/grub-editenv" "$BINARIES_DIR/efi-part/EFI/debian/grubenv" create
"$HOST_DIR/bin/grub-editenv" "$BINARIES_DIR/efi-part/EFI/debian/grubenv" set \
    hyperchromia_active_slot=a hyperchromia_pending=

cp -f "$HY_GRUB_EFI_PATH" "$BINARIES_DIR/efi-part/EFI/BOOT/bootx64.efi"
rm -f "$BINARIES_DIR/efi-part/EFI/BOOT/grub.cfg" \
    "$BINARIES_DIR/efi-part/EFI/BOOT/grubenv" \
    "$BINARIES_DIR/efi-part/EFI/BOOT/grubx64.efi"

VERSION="${HYPERCHROMIA_VERSION:-unknown}"
HOSTNAME="${HYPERCHROMIA_DEFAULT_HOSTNAME:-hyperchromia}"

cat > "$TARGET_DIR/etc/os-release" <<EOF
NAME="HyperChromia"
ID=hyperchromia
VERSION="$VERSION"
VERSION_ID="$VERSION"
PRETTY_NAME="HyperChromia $VERSION"
EOF

echo "$HOSTNAME" > "$TARGET_DIR/etc/hostname"

sed -i 's|^\(root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*\):.*|\1:/bin/bash|' "$TARGET_DIR/etc/passwd"
sed -i 's|^root:[^:]*:|root:*:|' "$TARGET_DIR/etc/shadow"

if [ -n "$HY_AUTHORIZED_KEYS" ] && [ -f "$HY_AUTHORIZED_KEYS" ]; then
    mkdir -p "$TARGET_DIR/root/.ssh"
    chmod 700 "$TARGET_DIR/root/.ssh"
    cp "$HY_AUTHORIZED_KEYS" "$TARGET_DIR/root/.ssh/authorized_keys"
    chmod 600 "$TARGET_DIR/root/.ssh/authorized_keys"
fi

cat > "$TARGET_DIR/etc/issue" <<EOF
HyperChromia $VERSION
EOF

mkdir -p "$TARGET_DIR/usr/share/hyperchromia/factory-seed"
if [ -n "$HY_PRESEED_FILE" ] && [ -f "$HY_PRESEED_FILE" ]; then
    cp "$HY_PRESEED_FILE" "$TARGET_DIR/usr/share/hyperchromia/factory-seed/firstboot.conf"
else
    cat > "$TARGET_DIR/usr/share/hyperchromia/factory-seed/firstboot.conf" <<EOF
HY_PRESEED_HOSTNAME=$HOSTNAME
HY_PRESEED_NET_MODE=dhcp
HY_PRESEED_NET_IP=
HY_PRESEED_NET_MASK=
HY_PRESEED_NET_GW=
HY_PRESEED_ROOT_PASSWORD=
HY_PRESEED_MQTT_HOST=
HY_PRESEED_MQTT_PORT=1883
HY_PRESEED_MQTT_USERNAME=
HY_PRESEED_MQTT_PASSWORD=
HY_PRESEED_MQTT_TLS=0
HY_PRESEED_LOCALE_KEYMAP=us
HY_PRESEED_WIFI_ENABLE=0
HY_PRESEED_WIFI_SSID=
HY_PRESEED_WIFI_PASSWORD=
EOF
fi
chmod 600 "$TARGET_DIR/usr/share/hyperchromia/factory-seed/firstboot.conf"
