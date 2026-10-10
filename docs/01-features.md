# Features

- **Read-only root.** SquashFS `SYSTEM` partition + a writable `DATA` partition for
  everything that actually changes at runtime. Pulling the power never corrupts the OS.
- **`hy` CLI.** `restart`, `net`, `netconfig` (incl. Wi-Fi), `backup`, `restore`, `upgrade`,
  `factoryreset`, `password`, `setup`, `reboot`, `poweroff` — tab-completion included.
- **Branded console.** Auto-login, logo, a live status header (CPU/RAM/uptime/IP/version)
  pinned to the top of the screen.
- **Self-contained upgrades.** `hy upgrade` fetches, verifies, and installs HyperHDR's
  own official release — no package manager, no OS rebuild required.
- **Home Assistant integration.** Point HyperChromia at your MQTT broker and it shows up in
  Home Assistant on its own, with buttons and status sensors. If the box goes offline,
  Home Assistant notices (see below).
- **Broad hardware target.** UEFI boot, generic PC kernel config — not tied to one
  specific mini-PC model.

## Benchmarks

Measured on a Dell Wyse 3040 (Intel Atom x5-Z8350, quad-core, fanless) running HyperHDR under
HyperChromia, capturing and processing a Full HD source at 60 FPS. CPU usage is aggregate across
all cores (100% = every core fully busy), on both the Wyse 3040 and the Pi 2/3/4 (both quad-core):

| Metric | HyperChromia on Dell Wyse 3040 | Raspberry Pi (community-reported) |
|---|---|---|
| Resolution / frame rate | 1920×1080 @ 60 FPS | 1920×1080 @ 30-60 FPS |
| CPU usage | ~49% | ~50-75% (Pi 2/3/4) |
| RAM usage (total system, OS + HyperHDR) | ~196 MB | ~320-330 MB (Pi 4, per HyperHDR's maintainer) |

### Used hardware cost (October 2026)

| Device | Typical used price | Notes |
|---|---|---|
| Dell Wyse 3040 | ~$20-30 | Complete unit — RAM/storage included, often with PSU |
| Raspberry Pi 4 | ~$65-100 | With PSU + SD card, to match a complete unit |
| Raspberry Pi 5 | ~$100-160 | With PSU + SD card, to match a complete unit |
