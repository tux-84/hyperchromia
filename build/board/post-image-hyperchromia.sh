#!/bin/sh
set -e

"$BR2_EXTERNAL_HYPERHDR_PATH/board/make-initramfs.sh" \
    "$BINARIES_DIR/initramfs.cpio.gz" \
    "${TARGET_DIR:-$(dirname "$BINARIES_DIR")/target}/lib/modules" \
    "$HY_BUSYBOX_PATH" \
    "$BR2_EXTERNAL_HYPERHDR_PATH/board/initramfs-init"

cp "$BR2_EXTERNAL_HYPERHDR_PATH/board/genimage-hyperchromia.cfg" "$BINARIES_DIR/genimage-hyperchromia.cfg"
support/scripts/genimage.sh -c "$BINARIES_DIR/genimage-hyperchromia.cfg"

mv "$BINARIES_DIR/disk.img" "$BINARIES_DIR/factory.img"

STAGE="$BINARIES_DIR/update-img-staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$BINARIES_DIR/bzImage" "$STAGE/bzImage"
cp "$BINARIES_DIR/initramfs.cpio.gz" "$STAGE/initramfs.cpio.gz"
cp "$BINARIES_DIR/rootfs.squashfs" "$STAGE/rootfs.squashfs"
cat > "$STAGE/manifest.json" <<EOF
{
  "hyperchromia_update": true,
  "schema_version": 1,
  "hyperchromia_version": "${HYPERCHROMIA_VERSION:-unknown}",
  "files": [
    {"path": "bzImage", "sha256": "$(sha256sum "$STAGE/bzImage" | cut -d' ' -f1)"},
    {"path": "initramfs.cpio.gz", "sha256": "$(sha256sum "$STAGE/initramfs.cpio.gz" | cut -d' ' -f1)"},
    {"path": "rootfs.squashfs", "sha256": "$(sha256sum "$STAGE/rootfs.squashfs" | cut -d' ' -f1)"}
  ]
}
EOF
"$HOST_DIR/bin/mksquashfs" "$STAGE" "$BINARIES_DIR/update.img" -noappend -all-root
rm -rf "$STAGE"
