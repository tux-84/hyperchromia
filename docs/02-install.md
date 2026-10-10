# Install

```bash
git clone git@github.com:julzops/hyperchromia.git
cd hyperchromia
./install.sh
```

`install.sh` asks what you want: build only (`factory.img`/`update.img`, no USB), or build and
flash a USB stick directly. Everything builds inside an isolated Docker container, so it works
the same on any host architecture — macOS and Linux are both supported for the USB-flashing
path. Pass `-v`/`--verbose` to see full build/flash output instead of the default progress bar.

## Installing a new device (USB installer, recommended)

```bash
./install.sh   # choose 2) Create a USB stick, then "Factory/installer stick"
```

You'll be asked for hostname, network (DHCP/static), Wi-Fi, root password (or rely on an SSH
key — see Usage below), MQTT broker, and console keymap, all on your own machine — no
screen or keyboard needed on the target device afterwards. The script then builds the image and
flashes it to a removable USB device you pick (only genuinely removable disks are ever listed).

Plug that USB stick into the target machine and power it on. It partitions the target's internal
disk, installs HyperChromia with your settings pre-baked, then **powers off** — remove the USB stick
and power the machine back on. It boots straight into a fully configured HyperChromia, no interaction
required.

## Manual install (advanced)

If you'd rather `dd` directly onto a drive you've pulled out of the machine:

```bash
# macOS
diskutil list                                  # find the target disk, e.g. /dev/disk4
diskutil unmountDisk /dev/disk4
sudo dd if=factory.img of=/dev/rdisk4 bs=4m status=progress
diskutil eject /dev/disk4

# Linux
lsblk                                          # find the target disk, e.g. /dev/sdb
sudo dd if=factory.img of=/dev/sdb bs=4M status=progress conv=fsync
sync
```

**Double-check the device path — this overwrites the entire target drive.** The drive boots
directly via UEFI into HyperChromia; first boot applies whatever preseed was baked in at build time
(or the defaults, if none was given).
