# reTerminal HiFi Appliance

A kiosk/appliance OS for the [Seeed reTerminal](https://www.seeedstudio.com/ReTerminal-with-CM4-p-4904.html) (CM4, 4GB RAM, 32GB eMMC, 5" touchscreen). Boots into a fullscreen web kiosk hosting pluggable applications. First application: [Feishin](https://github.com/jeffvli/feishin) music player for Navidrome/Jellyfin.

Built with Yocto scarthgap (5.0 LTS). Immutable rootfs with RAUC A/B atomic updates.

## Quickstart

Builds run inside a container (Podman by default; Docker also works). See [docs/dependencies.md](docs/dependencies.md) for full setup.

```bash
make image       # Build the build-host container image (~5 min first time)
make build       # Run the full bitbake build non-interactively
make shell       # Open an interactive shell in the build environment
make kas-shell   # Drop into kas shell with the project config loaded
make status      # Show bitbake progress from running build containers
make clean       # Remove the container image and all caches
```

Inside the container, `kas` and the full Yocto host toolchain are available. The repo is bind-mounted at `/workspace`.

## Repository Layout

```
├── .agents/plans/           # Task and phase plans
├── build/
│   └── Dockerfile           # Build-host container definition
├── docs/                    # Project documentation
│   ├── building.md          # Build instructions and cache management
│   ├── dependencies.md      # Host prerequisites and container contents
│   └── layers.md            # Upstream layer versions and release constraints
├── kas/
│   └── reterminal-hifi.yml  # kas build configuration (layer pins, machine, distro)
├── meta-kiosk-os/           # Custom platform layer (machine conf, BSP fixes, distro)
├── meta-kiosk-app-feishin/  # Feishin application layer
├── mirror-sources.txt       # Upstream repos to mirror (future task)
├── .mise.toml               # Host dev tool versions (mise)
├── Makefile                 # Build orchestration
├── AGENTS.md                # Agent instructions and project context
└── README.md                # This file
```

## Plans

The top-level project plan lives in the private sync vault. Phase-level and feature plans for this repo live in `.agents/plans/`. See [Phase 0 scaffolding](.agents/plans/2026-05-25__13-45-14%20-%20phase-0-project-scaffolding.md) for the current phase.

## Status

**Phase 1: First Bootable Image.** Building `core-image-minimal` with `distro: poky` and `machine: kiosk-reterminal`. Upstream layer incompatibilities fixed via bbappends and BBMASK in meta-kiosk-os. Build reaching image generation stage (~3668/3671 tasks).
