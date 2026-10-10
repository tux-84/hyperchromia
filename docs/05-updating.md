# Updating

HyperChromia keeps two copies of its SYSTEM partition (A/B slots) and applies updates to whichever
one isn't currently running, so a failed or interrupted update never leaves the device
unbootable — GRUB automatically falls back to the last-known-good slot. Your HyperHDR settings,
backups, and `hy`-managed configuration all live on a separate DATA partition that an update
never touches.

To update a device: `./install.sh` → 2) Create a USB stick → "Update stick" (no config needed),
or `dd` `update.img` onto a spare USB stick (or any spare disk) yourself. Attach it to the
device and power-cycle. HyperChromia detects it at boot, verifies it, applies it to the inactive
slot, and reboots into the new version. The stick can be left attached — HyperChromia won't reapply
an already-installed version.
