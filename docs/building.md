# Building

All builds run inside an OCI container (Podman by default; Docker also works). The host machine does not need Yocto, BitBake, or any cross-compiler — everything runs in the container.

## Quick start

```bash
make image       # Build the build-host container image (~5 min first time)
make build       # Run the full bitbake build non-interactively
make shell       # Open an interactive bash shell in the build environment
make kas-shell   # Enter a kas shell with the active kas config loaded
make status      # Show bitbake progress from running build containers
make clean       # Remove the container image and all caches
```

The default variant is `reterminal-hifi`. To build a specific variant:

```bash
make VARIANT=reterminal-hifi build
```

To build all variants:

```bash
make build-all
```

Variant configs live in `kas/variant-<name>.yaml`. The Makefile discovers all variants by globbing `kas/variant-*.yaml`.

## What `make image` builds

`build/Dockerfile` produces an Ubuntu 22.04 aarch64 container with:

- Full Yocto scarthgap host dependencies (gcc, git, python3, etc.)
- [kas 5.2](https://kas.readthedocs.io/) — Yocto build orchestrator
- A non-root `builder` user whose UID/GID match the host user (avoids file ownership issues with bind mounts)

The image is tagged `appliance-builder:latest`. Override the container engine with `make CONTAINER_ENGINE=docker image`.

## Bind mounts

When you run `make shell` or `make kas-shell`, the Makefile bind-mounts:

| Host path | Container path | Purpose |
|---|---|---|
| Repo root (`.`) | `/workspace` | Source tree, kas configs, layers |
| `.cache/downloads` | `/workspace/downloads` | Yocto `DL_DIR` — fetched source tarballs |
| `.cache/sstate` | `/workspace/sstate-cache` | Yocto `SSTATE_DIR` — shared state cache |
| `.cache/repos` | `/workspace/repos` | `KAS_REPO_REF_DIR` — git reference clones for upstream layers |
| Named volume `appliance-<VARIANT>-tmpdir` | `/workspace/build/tmp` | Yocto `TMPDIR` — case-sensitive filesystem for build artifacts |

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

> **Note:** Common upstream SRCREVs are pinned in `kas/common.yaml`. Variant-specific repos and machine config are in `kas/variant-<name>.yaml`. See `docs/layers.md` for the pinned versions table.

## Inspecting build output

The build's `TMPDIR` lives on a Podman named volume, so it's not directly accessible from macOS. To inspect files inside the build tree, use `make shell` and browse from there:

```bash
make shell

# View the generated config.txt
cat /workspace/build/tmp/deploy/images/seeed-reterminal/bootfiles/config.txt

# List deployed images
ls -lh /workspace/build/tmp/deploy/images/seeed-reterminal/

# Check the rootfs manifest
cat /workspace/build/tmp/deploy/images/seeed-reterminal/core-image-minimal-seeed-reterminal.rootfs.manifest

# Check build logs for a recipe
cat /workspace/build/tmp/work/seeed_reterminal-poky-linux/seeed-linux-dtoverlays/1.0/temp/log.do_compile
```

## Cache management

All caches live under `.cache/` in the repo root (gitignored):

| Directory | Contents | Safe to delete? |
|---|---|---|
| `.cache/downloads/` | Yocto source tarballs | Yes — sources will be re-fetched |
| `.cache/sstate/` | Yocto shared state | Yes — rebuild will be slower but correct |
| `.cache/repos/` | Bare git reference clones of upstream layers | Yes — repos will be re-cloned |

`make clean` removes the container image, the named TMPDIR volume, **and** the entire cache directory, giving you a true clean slate.

To remove only the caches without deleting the container image:

```bash
rm -rf .cache
```

## Troubleshooting

### Pseudo inode/path mismatch during `do_rootfs`

Pseudo's fakeroot database can go stale with long-lived TMPDIR volumes, particularly on Podman/macOS. If `do_rootfs` fails with `path mismatch` or `inode mismatch` errors, reset the build state:

```bash
make clean-build
make build
```


