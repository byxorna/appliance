# Building

The reTerminal HiFi Appliance builds inside an OCI container (Podman by default; Docker also works). The host machine does not need Yocto, BitBake, or any cross-compiler — everything runs in the container.

## Quick start

```bash
make image       # Build the build-host container image (~5 min first time)
make shell       # Open an interactive bash shell in the build environment
make kas-shell   # Enter a kas shell with kas/reterminal-hifi.yml loaded
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

All cache directories are created automatically. They persist across container runs so you don't re-fetch or re-compile unchanged packages.

The repo reference cache (`KAS_REPO_REF_DIR`) stores bare git clones of upstream layers. When kas needs a repo, it clones using git's `--reference` mechanism against this cache, making subsequent clones near-instant.

## Running a full build

Once inside the container (via `make shell` or `make kas-shell`):

```bash
# Option A: kas builds everything in one shot
kas build kas/reterminal-hifi.yml

# Option B: enter bitbake environment manually
kas shell kas/reterminal-hifi.yml
bitbake core-image-minimal
```

> **Note:** As of Phase 0, upstream layer SRCREVs are placeholder stubs (`TODO-*`). A real build will not succeed until Phase 1 resolves them.

## Cache management

All caches live under `~/.cache/reterminal-hifi-builder/`:

| Directory | Contents | Safe to delete? |
|---|---|---|
| `downloads/` | Yocto source tarballs | Yes — sources will be re-fetched |
| `sstate/` | Yocto shared state | Yes — rebuild will be slower but correct |
| `repos/` | Bare git reference clones of upstream layers | Yes — repos will be re-cloned |

`make clean` removes the container image **and** the entire cache directory, giving you a true clean slate.

To remove only the caches without deleting the container image:

```bash
rm -rf ~/.cache/reterminal-hifi-builder
```
