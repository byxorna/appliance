# Appliance OS

A minimal, single-purpose Linux distribution for dedicated hardware appliances. Boots into a fullscreen application shell hosting pluggable web applications. Built with [Yocto](https://www.yoctoproject.org/) scarthgap (5.0 LTS).

## Design principles

The appliance is self-replicating. Everything needed to understand, rebuild, reflash, and maintain the system ships on the device as manpages. Run `man appliance` on the device for an overview, or `man -k appliance` to list all topics. Source docs live in `docs/` as Markdown.

The root filesystem is read-only. Persistent state lives on separate partitions (`/data`, `/home`) that survive updates. RAUC A/B slot switching means updates either fully succeed or the system rolls back automatically.

Hardware support is separated from the OS and application layers. Adding a new device means adding a BSP layer and a kas config; the OS and apps are shared.

## Supported hardware

| Device | Status | Build target |
|---|---|---|
| [Seeed reTerminal](https://www.seeedstudio.com/ReTerminal-with-CM4-p-4904.html) (CM4, 4GB RAM, 32GB eMMC, 5" DSI touchscreen) | MVP | `reterminal-hifi` |

Variant configs live in `kas/variant-<name>.yaml`. Each variant defines a machine, BSP repos, and hardware-specific packages on top of the shared `kas/common.yaml`.

## Applications

| Application | Status |
|---|---|
| [Feishin](https://github.com/jeffvli/feishin) — music player for Navidrome/Jellyfin | In progress |

## Quickstart

Builds run inside a container. See [docs/dependencies.md](docs/dependencies.md) for host prerequisites and [docs/building.md](docs/building.md) for the full build workflow, cache layout, and troubleshooting.

```bash
make build-image                  # Build the OCI builder container image (~5 min first time)
make check                        # Parse-validate all layers and configs (no build)
make build                        # Full build: parse-check, firmware image, RAUC update bundle
make VARIANT=reterminal-hifi build  # Build a specific variant
make build-all                    # Build all variants
make build-containers             # Build all app container images (arm64)
make save-containers              # Save container images as OCI tarballs in artifacts/
make shell                        # Open an interactive shell in the build environment
make kas-shell                    # Drop into kas shell with the project config loaded
make status                       # Show bitbake progress from running build containers
make clean                        # Remove the container image and all caches
```

Inside the container, `kas` and the full Yocto host toolchain are available. The repo is bind-mounted at `/workspace`.

See [docs/flashing.md](docs/flashing.md) for writing the image to the device and [docs/post-install.md](docs/post-install.md) for WiFi, Bluetooth, and other post-install configuration.
