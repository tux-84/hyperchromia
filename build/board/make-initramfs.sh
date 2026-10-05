#!/bin/sh
set -e

OUT="$1"
MODULES_DIR="$2"
BUSYBOX_PATH="$3"
INIT_SCRIPT="$4"

STAGE="$(mktemp -d)"
mkdir -p "$STAGE/bin" "$STAGE/proc" "$STAGE/sys" "$STAGE/dev" "$STAGE/mnt/root" "$STAGE/lib/modules"

install -m 755 "$BUSYBOX_PATH" "$STAGE/bin/busybox"
for applet in $("$STAGE/bin/busybox" --list); do
    [ "$applet" = "busybox" ] && continue
    ln -s busybox "$STAGE/bin/$applet"
done

install -m 755 "$INIT_SCRIPT" "$STAGE/init"

for m in sd_mod usb-storage uas \
         libahci libahci_platform ahci ahci_platform ata_piix ata_generic \
         sata_mv sata_nv sata_promise sata_sil sata_sil24 sata_sis sata_svw sata_uli sata_via sata_vsc \
         pata_ali pata_amd pata_atiixp pata_jmicron pata_marvell pata_oldpiix pata_sch pata_sil680 pata_sis pata_via \
         sdhci sdhci-pci sdhci-acpi sdhci-pltfm cqhci mmc_block \
         nvme-core nvme; do
    found="$(find "$MODULES_DIR" -name "${m}.ko" 2>/dev/null | head -1)"
    [ -n "$found" ] && cp "$found" "$STAGE/lib/modules/${m}.ko"
done

( cd "$STAGE" && find . | cpio -o -H newc 2>/dev/null | gzip -9 ) > "$OUT"
rm -rf "$STAGE"
