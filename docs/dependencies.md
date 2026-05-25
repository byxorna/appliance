# Dependencies

## Host prerequisites

You need the following on your development machine (macOS or Linux):

### Required

| Tool | Minimum version | Install |
|---|---|---|
| **Podman** or **Docker** | Podman 5.0+ / Docker 24+ | [podman.io](https://podman.io/) / [docker.com](https://docs.docker.com/get-docker/) |
| **make** | any | Xcode CLT (macOS) / `apt install build-essential` (Debian) |
| **git** | 2.x | Xcode CLT (macOS) / `apt install git` (Debian) |

### Recommended

| Tool | Purpose | Install |
|---|---|---|
| **[mise](https://mise.jdx.dev/)** | Reproducible dev tool versions | `curl https://mise.jdx.dev/install.sh \| sh` |

After installing mise, run `mise install` in the repo root to install any pinned tools.

### Container engine setup (macOS)

The Makefile defaults to `CONTAINER_ENGINE=podman`. Pass `CONTAINER_ENGINE=docker` to use Docker instead.

With **Podman** on macOS, you need to initialize the VM once:

```bash
podman machine init
podman machine start
```

The default VM settings (4 CPU, 2 GB RAM) are fine for building the container image. For actual Yocto builds in later phases, you'll need more resources:

```bash
podman machine stop
podman machine set --cpus 4 --memory 16384 --disk-size 100
podman machine start
```

### ECR credential helper workaround (Podman only)

If your `~/.docker/config.json` contains ECR credential helpers (e.g. from AWS work), Podman will try to load them and fail. The Makefile handles this automatically by creating an empty auth file at `~/.cache/reterminal-hifi-builder/.podman-auth.json` and passing `--authfile` to all Podman commands. Docker users are unaffected.

## What the container provides

Everything needed for Yocto builds is inside the container — you don't install any of it on your host:

- Ubuntu 22.04 (aarch64, native on Apple Silicon)
- GCC, G++, make, and all Yocto host packages ([full list](https://docs.yoctoproject.org/ref-manual/system-requirements.html#required-packages-for-the-build-host))
- Python 3.10 + pip
- [kas 5.2](https://kas.readthedocs.io/) — Yocto build orchestrator
- git, wget, tmux, vim

## mise

The repo includes a `.mise.toml` for managing host-side dev tools. Currently it's a skeleton — tools will be added as the project grows (e.g. `shellcheck`, `yamllint`).

Container engines (Podman/Docker) are **not** managed by mise. On macOS, Podman requires the full Homebrew/installer package (VM infrastructure, `gvproxy`, `vfkit`), and Docker has its own installer.
