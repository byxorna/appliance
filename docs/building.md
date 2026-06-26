# Building

All builds run inside an OCI container (Podman by default; Docker also works). The host machine does not need Yocto, BitBake, or any cross-compiler — everything runs in the container.

## Quick start

```bash
make build-image  # Build the build-host container image (~5 min first time)
make build        # Run the full bitbake build non-interactively
make shell        # Open an interactive bash shell in the build environment
make kas-shell    # Enter a kas shell with the active kas config loaded
make status       # Show bitbake progress from running build containers
make clean        # Remove the container image and all caches
```

The default variant is `reterminal-hifi`. To build a specific variant:

```bash
make VARIANT=reterminal-hifi build
```

To build all variants:

```bash
make build-all
```

Variant configs live in `kas/variant-<name>.yaml`. List available variants with `make print-variants`.

## What `make image` builds

`make build-image` produces an Ubuntu 22.04 aarch64 container with:

- Full Yocto scarthgap host dependencies (gcc, git, python3, etc.)
- [kas 5.2](https://kas.readthedocs.io/) — Yocto build orchestrator
- A non-root `builder` user whose UID/GID match the host user (avoids file ownership issues with bind mounts)

The image is tagged `appliance-builder:latest`. Override the container engine with `make CONTAINER_ENGINE=docker build-image`.

## Bind mounts

When you run `make shell` or `make kas-shell`, the Makefile bind-mounts:

| Host path | Container path | Purpose |
|---|---|---|
| Repo root (`.`) | `$W` | Source tree, kas configs, layers |
| `.cache/downloads` | `$W/downloads` | Yocto `DL_DIR` — fetched source tarballs |
| `.cache/sstate` | `$W/sstate-cache` | Yocto `SSTATE_DIR` — shared state cache |
| `.cache/repos` | `$W/repos` | `KAS_REPO_REF_DIR` — git reference clones for upstream layers |
| Named volume `appliance-<VARIANT>-tmpdir` | `$W/build/tmp` | Yocto `TMPDIR` — case-sensitive filesystem for build artifacts |

`$W` is the container workspace root (currently `/workspace`).

All cache directories are created automatically. They persist across container runs so you don't re-fetch or re-compile unchanged packages.

The repo reference cache (`KAS_REPO_REF_DIR`) stores bare git clones of upstream layers. When kas needs a repo, it clones using git's `--reference` mechanism against this cache, making subsequent clones near-instant.

The build's `TMPDIR` uses a named container volume instead of a bind mount because macOS filesystems (HFS+/APFS) are case-insensitive, which Yocto rejects. The named volume lives on the Podman VM's case-sensitive ext4 filesystem and persists across container runs for incremental builds. Each variant gets its own named volume (`appliance-<VARIANT>-tmpdir`).

## Running a full build

```bash
make build       # Non-interactive: runs bitbake in a container and exits
```

Or interactively:

```bash
make kas-shell
bitbake -c build core-image-minimal
```

To include hardware test tools (evtest, i2c-tools, alsa-utils, etc.):

```bash
kas build kas/variant-reterminal-hifi.yaml:kas/test-tools.yaml
```

> **Note:** Common upstream SRCREVs are pinned in `kas/features/common.yaml`. Variant-specific repos and machine config are in `kas/variant-<name>.yaml`. See `docs/layers.md` for the pinned versions table.

## Inspecting build output

The build's `TMPDIR` lives on a Podman named volume, so it's not directly accessible from macOS. To inspect files inside the build tree, use `make shell` and browse from there. Paths below use `$W` for the container workspace root:

```bash
make shell

# View the generated config.txt
cat $W/build/tmp/deploy/images/seeed-reterminal/bootfiles/config.txt

# List deployed images
ls -lh $W/build/tmp/deploy/images/seeed-reterminal/

# Check the rootfs manifest
cat $W/build/tmp/deploy/images/seeed-reterminal/core-image-minimal-seeed-reterminal.rootfs.manifest

# Check build logs for a recipe
cat $W/build/tmp/work/seeed_reterminal-poky-linux/seeed-linux-dtoverlays/1.0/temp/log.do_compile
```

## Building app container images

Apps run inside OCI containers on the device. Container images are built on the host using Podman (or Docker) and saved as tarballs for loading onto the device.

Each subdirectory under `containers/` with a `Dockerfile` becomes a buildable image. Tags default to `appliance-<name>:latest`; set `CONTAINER_REGISTRY` to prepend a registry prefix (e.g., `make CONTAINER_REGISTRY=ghcr.io/myorg build-containers`).

```bash
make build-containers             # Build all app container images (arm64)
make build-container-feishin      # Build a single app container image
make save-containers              # Save all as OCI tarballs in artifacts/
make save-container-feishin       # Save a single container as tarball
```

To load a container image onto the device (streams via stdin, no temp file needed on the device):

```bash
ssh root@reterminal-hifi podman load < artifacts/appliance-feishin-latest.tar
```

## Cache management

All caches live under `.cache/` in the repo root (gitignored):

| Directory | Contents | Safe to delete? |
|---|---|---|
| `.cache/downloads/` | Yocto source tarballs | Yes, sources will be re-fetched |
| `.cache/sstate/` | Yocto shared state | Yes, rebuild will be slower but correct |
| `.cache/repos/` | Bare git reference clones of upstream layers | Yes, repos will be re-cloned |

`make clean` removes the container image, the named TMPDIR volume, **and** the entire cache directory, giving you a true clean slate.

To remove only the caches without deleting the container image:

```bash
rm -rf .cache
```

## Full rebuild and deploy

This walks through building everything from scratch for a variant and deploying it to a running device. Useful after layer changes, config changes, or when troubleshooting stale build state.

### 1. Build

```bash
# find what you would like to build
make print-variants

# pick something
VARIANT=mycroft-mkii-rpi-devkit-hifi

# build it
make VARIANT=$VARIANT clean-cache build save-containers
```

`clean-cache` resets the TMPDIR volume and sstate, forcing a full rebuild. `build` produces the firmware image (`.wic.bz2`) and RAUC update bundle (`.raucb`). `save-containers` builds and saves all app container images as OCI tarballs in `artifacts/`.

For incremental builds (no cache reset), drop `clean-cache`:

```bash
make VARIANT=$VARIANT build save-containers
```

### 2. Deploy the rootfs update

Copy the RAUC bundle to the device and install it to the inactive slot:

```bash
HOST=root@mycroft-mkii-rpi-devkit-hifi
BUNDLE=$(ls artifacts/$VARIANT-*.raucb)

scp $BUNDLE $HOST:/tmp/
ssh $HOST rauc install /tmp/$(basename $BUNDLE)
```

### 3. Deploy container images

Stream each tarball directly into `podman load` over SSH to avoid needing disk space on the device for a temporary copy:

```bash
for tar in artifacts/appliance-*-latest.tar; do
    ssh $HOST podman load < $tar
done
```

### 4. Reboot

```bash
ssh $HOST reboot
```

After reboot, `appliance-mark-good.service` marks the new slot as good. Verify with `ssh $HOST rauc status`.

### Listing variants and machines

```bash
make print-variants    # one variant per line
make print-machines    # one unique machine per line
```

## Troubleshooting

### Pseudo inode/path mismatch during `do_rootfs`

Pseudo's fakeroot database can go stale with long-lived TMPDIR volumes, particularly on Podman/macOS. If `do_rootfs` fails with `path mismatch` or `inode mismatch` errors, reset the build state:

```bash
make clean-cache
make build
```


