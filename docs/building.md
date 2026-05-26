# Building

The reTerminal HiFi Appliance builds inside an OCI container (Podman by default; Docker also works). The host machine does not need Yocto, BitBake, or any cross-compiler — everything runs in the container.

## Quick start

```bash
make image       # Build the build-host container image (~5 min first time)
make build       # Run the full bitbake build non-interactively
make shell       # Open an interactive bash shell in the build environment
make kas-shell   # Enter a kas shell with kas/reterminal-hifi.yaml loaded
make status      # Show bitbake progress from running build containers
make clean       # Remove the container image and all caches
```

## What `make image` builds

`build/Dockerfile` produces an Ubuntu 22.04 aarch64 container with:

- Full Yocto scarthgap host dependencies (gcc, git, python3, etc.)
- [kas 5.2](https://kas.readthedocs.io/) — Yocto build orchestrator
- A non-root `builder` user whose UID/GID match the host user (avoids file ownership issues with bind mounts)

The image is tagged `reterminal-hifi-builder:latest`. Override the container engine with `make CONTAINER_ENGINE=docker image`.

## Bind mounts

When you run `make shell` or `make kas-shell`, the Makefile bind-mounts:

| Host path | Container path | Purpose |
|---|---|---|
| Repo root (`.`) | `/workspace` | Source tree, kas configs, layers |
| `~/.cache/reterminal-hifi-builder/downloads` | `/workspace/downloads` | Yocto `DL_DIR` — fetched source tarballs |
| `~/.cache/reterminal-hifi-builder/sstate` | `/workspace/sstate-cache` | Yocto `SSTATE_DIR` — shared state cache |
| `~/.cache/reterminal-hifi-builder/repos` | `/workspace/repos` | `KAS_REPO_REF_DIR` — git reference clones for upstream layers |
| Named volume `reterminal-hifi-tmpdir` | `/workspace/build/tmp` | Yocto `TMPDIR` — case-sensitive filesystem for build artifacts |

All cache directories are created automatically. They persist across container runs so you don't re-fetch or re-compile unchanged packages.

The repo reference cache (`KAS_REPO_REF_DIR`) stores bare git clones of upstream layers. When kas needs a repo, it clones using git's `--reference` mechanism against this cache, making subsequent clones near-instant.

The build's `TMPDIR` uses a named container volume instead of a bind mount because macOS filesystems (HFS+/APFS) are case-insensitive, which Yocto rejects. The named volume lives on the Podman VM's case-sensitive ext4 filesystem and persists across container runs for incremental builds.

## Running a full build

```bash
make build       # Non-interactive: runs bitbake in a container and exits
```

Or interactively:

```bash
make kas-shell
bitbake -c build core-image-minimal
```

> **Note:** Upstream SRCREVs are pinned in `kas/reterminal-hifi.yaml`. See `docs/layers.md` for the pinned versions table.

## Cache management

All caches live under `~/.cache/reterminal-hifi-builder/`:

| Directory | Contents | Safe to delete? |
|---|---|---|
| `downloads/` | Yocto source tarballs | Yes — sources will be re-fetched |
| `sstate/` | Yocto shared state | Yes — rebuild will be slower but correct |
| `repos/` | Bare git reference clones of upstream layers | Yes — repos will be re-cloned |

`make clean` removes the container image, the named TMPDIR volume, **and** the entire cache directory, giving you a true clean slate.

To remove only the caches without deleting the container image:

```bash
rm -rf ~/.cache/reterminal-hifi-builder
```
