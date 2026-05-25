# AGENTS.md

Read this file completely before taking any action in this repository.

## Project

Yocto-based kiosk/appliance OS for the Seeed reTerminal (CM4). Boots into fullscreen Chromium hosting web apps via iframes. First app: Feishin (Navidrome/Jellyfin frontend). Immutable rootfs with RAUC A/B updates.

See `docs/` for build instructions, layer details, and dependency info. See `kas/reterminal-hifi.yml` for the full layer stack and pinned SRCREVs. See `Makefile` for available build targets.

## Plans

All plans go in `.agents/plans/` (not the private vault). Naming: `<YYYY-MM-DD>__<HH-MM-SS> - <task-name>.md`. Each plan has: **Requirements**, **Detailed Implementation Plan + Reasoning**, **Task List**.

The top-level project plan is at `/Users/gconradi/sync/private.enc/agents/plans/2026-05-23__18-02-43 - reterminal-feishin-appliance.md`. Refer to it for full architecture and phase roadmap; never copy it wholesale into this repo.

Before starting work: read the relevant plan, or write one if none exists. After work: update the task list and reasoning if new info was discovered.

## Conventions

- **Machine:** `seeed-reterminal` (from `meta-seeed-cm4`)
- **Distro:** `kiosk-os` (custom, Wayland-only, systemd, no Qt, no X11)
- **Image:** `kiosk-os-image` (custom image recipe in `meta-kiosk-os`)
- **App manifest:** Apps ship `app.json` (name, port, capabilities, config_dir). Ports must be unique. Apps inherit `kiosk-app.bbclass`.
- **Persistent data:** `/data/platform/` for platform, `/data/apps/<name>/` for per-app state. rootfs is read-only.
- **Services bind `127.0.0.1` only.**
- **Never use `${AUTOREV}`** — all upstream layers pinned by SRCREV.

## Gotchas

- **Display rotation:** 720×1280 portrait panel. Landscape needs *both* Cage `transform 270` and DT overlay `tp_rotate=1`.
- **I2S pins reserved:** GPIOs 18-21 are I2S to WM8960. IR receiver on GPIO 24.
- **meta-seeed-cm4 pulls Qt by default.** Don't add `meta-qt5`; strip via `IMAGE_INSTALL:remove`.
- **eMMC boot requires `rootwait`.** No boot0/boot1 — BCM2711 EEPROM boots from `mmcblk0` user partition only.
- **RPi firmware watchdog is 16s.** U-Boot must pet or disable it in time.
- **TMPDIR on named volume:** macOS is case-insensitive; TMPDIR lives on a Podman named volume (VM ext4).
- **Chromium link needs ~16GB RAM.** CI runners need 16+ vCPU, 32+ GB.
