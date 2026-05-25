# reTerminal HiFi Appliance

A kiosk/appliance OS for the [Seeed reTerminal](https://www.seeedstudio.com/ReTerminal-with-CM4-p-4904.html) (CM4, 4GB RAM, 32GB eMMC, 5" touchscreen). Boots into a fullscreen web kiosk hosting pluggable applications. First application: [Feishin](https://github.com/jeffvli/feishin) music player for Navidrome/Jellyfin.

Built with Yocto scarthgap (5.0 LTS). Immutable rootfs with RAUC A/B atomic updates.

## Quickstart

Builds run inside a Podman container on macOS (or Linux). Prerequisites: [Podman](https://podman.io/) installed and running.

```bash
make image       # Build the build-host container image (~5 min first time)
make shell       # Open an interactive shell in the build environment
make kas-shell   # Drop into kas shell with the project config loaded
make clean       # Remove the container image
```

Inside the container, `kas` and the full Yocto host toolchain are available. The repo is bind-mounted at `/workspace`.

## Repository Layout

```
├── .agents/plans/           # Task and phase plans
├── build/
│   └── Dockerfile           # Build-host container definition
├── kas/
│   └── reterminal-hifi.yml  # kas build configuration (layer pins, machine, distro)
├── meta-kiosk-os/           # Custom platform layer (distro, BSP config, daemons, shell, image)
├── meta-kiosk-app-feishin/  # Feishin application layer
├── mirror-sources.txt       # Upstream repos to mirror (future task)
├── Makefile                 # Build orchestration
├── AGENTS.md                # Agent instructions and project context
└── README.md                # This file
```

## Plans

The top-level project plan lives in the private sync vault. Phase-level and feature plans for this repo live in `.agents/plans/`. See [Phase 0 scaffolding](.agents/plans/2026-05-25__13-45-14%20-%20phase-0-project-scaffolding.md) for the current phase.

## Status

**Phase 0: Scaffolding.** Repo structure, build container, kas stub, skeleton layers. No working Yocto image yet.
