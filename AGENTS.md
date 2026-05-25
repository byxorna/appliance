# AGENTS.md

## Prime Directive

You are working on a Yocto-based embedded Linux appliance for the Seeed reTerminal (CM4). Read this file completely before taking any action in this repository.

## Plan Storage

All plans go in `.agents/plans/` inside this repository, **not** in the private vault. File naming convention:

```
.agents/plans/<YYYY-MM-DD>__<HH-MM-SS> - <task-name>.md
```

Each plan must have three sections: **Requirements**, **Detailed Implementation Plan + Reasoning**, and **Task List**. The top-level project plan lives in the private sync vault at `/Users/gconradi/sync/private.enc/agents/plans/2026-05-23__18-02-43 - reterminal-feishin-appliance.md`. Refer to it for full architecture and phase roadmap, but never copy it wholesale into this repo.

## Plan & Review Cadence

Before starting work:
1. Read the relevant plan in `.agents/plans/`.
2. If no plan exists for the task, write one first.
3. Check off tasks as you complete them.

After completing work:
1. Update the task list in the relevant plan.
2. If you discovered new information, update the plan's reasoning section.

## Project Overview

**What this builds:** A kiosk/appliance OS for the Seeed reTerminal (CM4, 4GB RAM, 32GB eMMC, 5" 720×1280 DSI touchscreen). Boots into a fullscreen Chromium kiosk shell hosting web applications via iframes. First application is Feishin (music player frontend for Navidrome/Jellyfin). Immutable rootfs with RAUC A/B updates.

**Key architecture layers:**
- **Platform** (`meta-kiosk-os`): hardware, display, compositor (Cage), Chromium, networking, RAUC updates, PipeWire audio, persistent storage
- **Shell** (`kiosk-shell`): web app hosting iframe-based app switcher, settings, now-playing bar, WebSocket clients to `kiosk-buttond` and `kiosk-playd`
- **Applications** (`meta-kiosk-app-*`): self-contained web app bundles with `app.json` manifests, installed to `/usr/share/kiosk-apps/<name>/`

**Build system:** Yocto scarthgap (5.0 LTS) with kas, built inside a Podman container on macOS arm64.

## Build Environment

```bash
make image       # Build the Podman container image (Ubuntu 22.04 + kas + Yocto host deps)
make shell       # Interactive shell inside the build container
make kas-shell   # Drop into `kas shell kas/reterminal-hifi.yml`
make clean       # Remove the container image
```

Yocto sstate and downloads are persisted at `~/.cache/reterminal-hifi-builder/{sstate,downloads}` via bind mounts. The repo itself is bind-mounted at `/workspace` inside the container.

## Repository Layout

```
├── .agents/plans/       # Task plans (this repo only, not the private vault)
├── build/Dockerfile     # Yocto build host container
├── kas/                 # kas configuration files
│   └── reterminal-hifi.yml
├── meta-kiosk-os/       # Platform layer (distro, BSP config, platform daemons, shell, image recipe)
├── meta-kiosk-app-feishin/  # Feishin app layer
├── mirror-sources.txt   # Upstream repos to mirror (not yet mirrored)
├── Makefile             # Build orchestration
└── AGENTS.md            # This file
```

## Layer Stack

```
poky (scarthgap)
  meta-openembedded (meta-oe, meta-python, meta-networking, meta-multimedia)
  meta-raspberrypi (scarthgap)
  meta-seeed-cm4 (main, tracks scarthgap — provides MACHINE=seeed-reterminal)
  meta-clang (scarthgap, required by meta-chromium)
  meta-browser/meta-chromium (scarthgap)
  meta-rauc (scarthgap)
  meta-rauc-community (scarthgap)
  meta-kiosk-os (custom — platform)
  meta-kiosk-app-feishin (custom — Feishin app)
```

All upstream layers are pinned by SRCREV in `kas/reterminal-hifi.yml`. Never use `${AUTOREV}` in production.

## Conventions

- **Machine:** `seeed-reterminal` (from `meta-seeed-cm4`)
- **Distro:** `kiosk-os` (custom, Wayland-only, systemd, no Qt, no X11)
- **Image:** `kiosk-os-image` (custom image recipe in `meta-kiosk-os`)
- **App manifest:** Every app ships `app.json` with name, port, capabilities, config_dir. Ports must be unique across all apps. Apps inherit `kiosk-app.bbclass`.
- **Persistent data:** `/data/platform/` for platform config, `/data/apps/<name>/` for per-app state. rootfs is read-only.
- **Services bind to `127.0.0.1` only.** Nothing is exposed on the LAN.

## Gotchas

- **Display rotation:** The reTerminal DSI panel is 720×1280 portrait. Landscape requires *both* Cage `transform 270` and DT overlay `tp_rotate=1`. Missing either one causes touch/display mismatch.
- **I2S pins reserved:** GPIOs 18-21 carry I2S audio to the WM8960 codec. Do not use them for IR or other GPIO functions. IR receiver goes on GPIO 24.
- **meta-seeed-cm4 pulls Qt by default.** Strip it via `IMAGE_INSTALL:remove` and by not adding `meta-qt5` to the layer list. If `meta-seeed-cm4` has `LAYERDEPENDS` on it, satisfy parse-time deps but never install Qt packages.
- **eMMC boot requires `rootwait`** in kernel cmdline. The controller enumerates asynchronously.
- **No eMMC boot0/boot1.** BCM2711 EEPROM can't read them. Everything boots from user partition `mmcblk0`.
- **RPi firmware watchdog is 16s.** U-Boot must pet or disable it within 16s of cold start.
- **Podman on macOS:** Dockerfile uses `docker.io/library/ubuntu:22.04` (fully qualified) to avoid registry ambiguity. `:Z` SELinux flag is harmless on macOS.
- **Chromium + CM4 memory:** Chromium link step needs ~16GB RAM. CI runners need 16+ vCPU, 32+ GB RAM. The default GitHub Actions runner will OOM.

## Current Status

**Phase 0: Scaffolding** — repo structure, build container, kas stub, skeleton layers. No Yocto builds run yet, no real SRCREVs resolved.

## Phase Roadmap

See the top-level plan for full details. Summary:

0. Project scaffolding (current)
1. Minimal bootable image (core-image-minimal on CM4)
2. reTerminal hardware support (display, touch, buttons, sensors)
3. Platform kiosk infrastructure (Cage, Chromium, kiosk-init, kiosk-httpd)
4. Shell + button daemon + playback coordinator
5. Feishin app integration
6. Audio (PipeWire, USB DAC, bit-perfect path validation)
7. RAUC A/B updates
8. Persistent data
9. Update delivery
10. Polish (boot splash, boot time, lockdown, docs)
