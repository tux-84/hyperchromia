# Building

Building produces `factory.img` (for the USB installer / a first `dd`) and `update.img` (for
later A/B updates), without necessarily flashing anything.

## Via `install.sh` (recommended)

```bash
./install.sh   # choose 1) Build only
```

This builds both images in the repo root and stops — no USB stick, no `dd`. Use the images
later with the manual install or update flows (see Install and Updating).

## Via `scripts/build.sh` (advanced / CI)

`install.sh` is a thin wrapper around `scripts/build.sh`, which can be run directly:

```bash
scripts/build.sh
```

It builds everything inside a Docker container (Buildroot 2026.08), so the host architecture
doesn't matter. Useful environment variables:

| Variable | Effect |
|---|---|
| `JOBS` | Parallel build jobs inside the container (default `8`) |
| `HY_CONTAINER_CHOICE` | `scratch` (fresh container) or `resume` (reuse the last one) — skips the interactive prompt, useful for CI |
| `HY_CI_CLEANUP` | `1` removes the build container and its volume on exit instead of leaving it for a resumed build |

Both `factory.img` and `update.img` are copied to the repo root when the build finishes.
