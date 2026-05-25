# Building

The reTerminal HiFi Appliance builds inside an OCI container (Podman by default; Docker also works). The host machine does not need Yocto, BitBake, or any cross-compiler — everything runs in the container.

## Quick start

```bash
make image       # Build the build-host container image (~5 min first time)
make shell       # Open an interactive bash shell in the build environment
make kas-shell   # Enter a kas shell with kas/reterminal-hifi.yml loaded
make clean       # Remove the container image
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

Both cache directories are created automatically. They persist across container runs so you don't re-fetch or re-compile unchanged packages.

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

- **sstate-cache**: Safe to delete anytime. Rebuild will be slower but correct.
- **downloads**: Safe to delete. Sources will be re-fetched.
- `make clean` only removes the container image, not the caches.

To nuke everything:

```bash
make clean
rm -rf ~/.cache/reterminal-hifi-builder
```
