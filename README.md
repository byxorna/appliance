# Appliance OS

A minimal, single-purpose Linux distribution for dedicated hardware appliances. Boots into a fullscreen application shell hosting pluggable web applications. Built with [Yocto](https://www.yoctoproject.org/) scarthgap (5.0 LTS). Immutable rootfs with RAUC A/B atomic updates.

The architecture separates hardware support (BSP layers) from the base OS and application layers, so adding support for new devices means adding a BSP layer and a kas config — the OS and app layers are shared.

## Supported hardware

| Device | Status | Build target |
|---|---|---|
| [Seeed reTerminal](https://www.seeedstudio.com/ReTerminal-with-CM4-p-4904.html) (CM4, 4GB RAM, 32GB eMMC, 5" DSI touchscreen) | MVP | `reterminal-hifi` |

Variant configs live in `kas/variant-<name>.yaml`. Each variant defines a machine, BSP repos, and hardware-specific packages on top of the shared `kas/common.yaml`.

## Applications

| Application | Status |
|---|---|
| [Feishin](https://github.com/jeffvli/feishin) — music player for Navidrome/Jellyfin | Planned |

## Quickstart

Builds run inside a container. See [docs/dependencies.md](docs/dependencies.md) for host prerequisites and [docs/building.md](docs/building.md) for the full build workflow, cache layout, and troubleshooting.

```bash
make image                        # Build the build-host container image (~5 min first time)
make check                        # Parse-validate all layers and configs (no build)
make build                        # Build the default variant (reterminal-hifi)
make VARIANT=reterminal-hifi build  # Build a specific variant
make build-all                    # Build all variants
make shell                        # Open an interactive shell in the build environment
make kas-shell                    # Drop into kas shell with the project config loaded
make status                       # Show bitbake progress from running build containers
make clean                        # Remove the container image and all caches
```

Inside the container, `kas` and the full Yocto host toolchain are available. The repo is bind-mounted at `/workspace`.

See [docs/flashing.md](docs/flashing.md) for writing the image to the device and [docs/post-install.md](docs/post-install.md) for WiFi, Bluetooth, and other post-install configuration.
