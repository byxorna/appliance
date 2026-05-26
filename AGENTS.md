# AGENTS.md

Read this file completely before taking any action in this repository.

## Project

Yocto-based appliance OS for the Seeed reTerminal (CM4). Boots into a fullscreen application shell hosting web apps via iframes. First app: Feishin (Navidrome/Jellyfin frontend). Immutable rootfs with RAUC A/B updates.

See `docs/` for build instructions, layer details, and dependency info. See `kas/reterminal-hifi.yaml` for the full layer stack and pinned SRCREVs. See `Makefile` for available build targets.

## Plans

All plans go in `.agents/plans/` (not the private vault). Naming: `<YYYY-MM-DD>__<HH-MM-SS> - <task-name>.md`. Each plan has: **Requirements**, **Detailed Implementation Plan + Reasoning**, **Task List**.

The top-level project plan is at `/Users/gconradi/sync/private.enc/agents/plans/2026-05-23__18-02-43 - reterminal-feishin-appliance.md`. Refer to it for full architecture and phase roadmap; never copy it wholesale into this repo.

Before starting work: read the relevant plan, or write one if none exists. After work: update the task list and reasoning if new info was discovered.

## Conventions

- **Machine:** `appliance-reterminal` (derived from `seeed-reterminal` in `meta-appliance-os/conf/machine/`)
- **Distro:** `appliance-os` (thin wrapper around poky; systemd init)
- **Image:** `core-image-minimal` (temporary; `appliance-os-image` will be the final image recipe)
- **App manifest:** Apps ship `app.json` (name, port, capabilities, config_dir). Ports must be unique. Apps inherit `appliance-app.bbclass`.
- **Persistent data:** `/data/platform/` for platform, `/data/apps/<name>/` for per-app state. rootfs is read-only.
- **Services bind `127.0.0.1` only.**
- **Never use `${AUTOREV}`** — all upstream layers pinned by SRCREV.

## Documentation preferences

- **No "Status" section in README.md.** The README should be stable reference material, not a changelog.
- **Keep docs generalizable.** Avoid coupling descriptions to specific implementation details that may change. Prefer describing purpose over enumerating internals.
- **Use `.yaml` extension** for YAML files, not `.yml`.

## Gotchas

- **Display rotation:** 720×1280 portrait panel. Landscape needs *both* Cage `transform 270` and DT overlay `tp_rotate=1`.
- **I2S pins reserved:** GPIOs 18-21 are I2S to WM8960. IR receiver on GPIO 24.
- **meta-seeed-cm4 pulls Qt by default.** Don't add `meta-qt5`; strip via `IMAGE_INSTALL:remove`.
- **eMMC boot requires `rootwait`.** No boot0/boot1 — BCM2711 EEPROM boots from `mmcblk0` user partition only.
- **RPi firmware watchdog is 16s.** U-Boot must pet or disable it in time.
- **TMPDIR on named volume:** macOS is case-insensitive; TMPDIR lives on a Podman named volume (VM ext4).
- **BBMASK in layer.conf:** `meta-seeed-cm4`'s `rpi-bootfiles.bbappend` wget is 404. Masked via `BBMASK +=` in `meta-appliance-os/conf/layer.conf`.
- **`:append` can't be un-appended:** Redefining a shell function in a bbappend does NOT cancel `:append` fragments from other layers. Use `BBMASK` to mask the offending bbappend.
- **Recipe bbappend scope != machine conf scope:** `KERNEL_DEVICETREE:remove` in a kernel bbappend only affects the kernel recipe's datastore, not `IMAGE_BOOT_FILES` in image recipes. Machine-level variable overrides must go in machine conf.
- **Chromium link needs ~16GB RAM.** CI runners need 16+ vCPU, 32+ GB.
