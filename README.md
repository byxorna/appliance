# reTerminal HiFi Appliance

A single-purpose appliance OS for the [Seeed reTerminal](https://www.seeedstudio.com/ReTerminal-with-CM4-p-4904.html) (CM4, 4GB RAM, 32GB eMMC, 5" touchscreen). Boots into a fullscreen application shell hosting pluggable web applications. First application: [Feishin](https://github.com/jeffvli/feishin) music player for Navidrome/Jellyfin.

Built with Yocto scarthgap (5.0 LTS). Immutable rootfs with RAUC A/B atomic updates.

## Quickstart

Builds run inside a container (Podman by default; Docker also works). See [docs/dependencies.md](docs/dependencies.md) for host prerequisites and [docs/building.md](docs/building.md) for the full build workflow, cache layout, and troubleshooting.

```bash
make image       # Build the build-host container image (~5 min first time)
make check       # Parse-validate all layers and configs (no build)
make build       # Build image and extract artifacts to artifacts/
make shell       # Open an interactive shell in the build environment
make kas-shell   # Drop into kas shell with the project config loaded
make status      # Show bitbake progress from running build containers
make clean       # Remove the container image and all caches
```

Inside the container, `kas` and the full Yocto host toolchain are available. The repo is bind-mounted at `/workspace`.

See [docs/flashing.md](docs/flashing.md) for extracting artifacts and writing the image to SD card or eMMC. See [docs/post-install.md](docs/post-install.md) for WiFi and other post-install configuration.

## Repository Layout

```
├── .agents/plans/           # Task and phase plans
├── build/
│   └── Dockerfile           # Build-host container definition
├── docs/                    # Project documentation
│   ├── building.md          # Build instructions and cache management
│   ├── dependencies.md      # Host prerequisites and container contents
│   ├── flashing.md          # Extracting and flashing images
│   └── layers.md            # Upstream layer versions and release constraints
├── kas/
│   └── reterminal-hifi.yaml # kas build configuration (layer pins, machine, distro)
├── meta-appliance-os/       # Platform layer (machine conf, BSP fixes, distro)
├── meta-appliance-app-feishin/  # Feishin application layer
├── Makefile                 # Build orchestration
├── AGENTS.md                # Agent instructions and project context
└── README.md                # This file
```
