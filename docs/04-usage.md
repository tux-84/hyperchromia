# Usage

## `hy` CLI reference

| Command | Description |
|---|---|
| `hy restart` | Restart HyperHDR, verify it comes back up |
| `hy net` | Show network diagnostics (read-only) |
| `hy netconfig` | Change IP mode (DHCP/static) or hostname |
| `hy backup` | Archive the current HyperHDR install |
| `hy restore [archive]` | Restore a backup (defaults to the most recent) |
| `hy upgrade` | Check for and install a newer HyperHDR version |
| `hy factoryreset` | **Destructive.** Reset HyperHDR back to factory defaults |
| `hy password` | Change the root password |
| `hy locale` | Try, then optionally save, a console keyboard layout |
| `hy mqtt` | Configure the MQTT bridge (Home Assistant) |
| `hy reboot` / `hy poweroff` | Self-explanatory |

## Home Assistant integration

Run `hy mqtt` and enter your broker's host, port, username, and password (leave the host blank
to turn it off again). That's it — no YAML, no manual entity setup. A "HyperChromia" device shows up
in Home Assistant under Settings → Devices & Services → MQTT, with:

- Buttons to reboot, power off, or restart HyperHDR
- Sensors for whether HyperHDR is running, whether the LED device is on, and whether the box
  itself is reachable

If HyperChromia loses power or drops off the network, Home Assistant marks it (and its entities)
offline automatically — you don't need to do anything for that to work.

## Configuration

`config.env` at the repo root:

```bash
HYPERCHROMIA_DEFAULT_HOSTNAME=hyperchromia
HYPERHDR_DEFAULT_VERSION=latest
```

There is no static default root password. Add your own SSH public key to `authorized_keys`
at the repo root (gitignored — never commit a real key here) for key-based root login with
password login disabled, or set a password through the USB installer's factory setup prompts
(`./install.sh` → 2 → factory), applied automatically on first boot. A build with neither will
warn you: that image would have no way to log in as root at all. Change the password later any
time with `hy password`.
