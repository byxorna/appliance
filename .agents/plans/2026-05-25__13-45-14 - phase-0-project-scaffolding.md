# Phase 0 - Project Scaffolding

## Requirements

Stand up `~/code/byxorna/reterminal-hifi-appliance` as a Yocto-based project repo for the reTerminal HiFi appliance, with builds executed inside a Podman container on macOS arm64. Phase 0 is scaffolding only: no Yocto builds run, no upstream code mirrored yet, no recipes written. Goal is that a developer (or CI) can clone the repo, run a single `make` target, and land in a working Yocto build environment inside Linux, with this repo bind-mounted.

Phase 0 success criteria:

1. Repo exists at `~/code/byxorna/reterminal-hifi-appliance` and is a git repo with an initial commit.
2. Repo-local `AGENTS.md` is in place and directs the assistant to store future plans at `.agents/plans/`. The Phase 0 plan itself lives there as the first entry.
3. Repo-local plan storage directory `.agents/plans/` exists and contains this plan.
4. `kas/` directory exists with a stub `reterminal-hifi.yml` that lists the layers we'll pin in Phase 0+1 (poky, meta-openembedded, meta-raspberrypi, meta-seeed-cm4, meta-clang, meta-browser, meta-rauc, meta-rauc-community). SRCREVs may be placeholder TODO values; resolving real pins is a Phase 0 follow-up task, not a blocker for the scaffold.
5. `meta-kiosk-os/` and `meta-kiosk-app-feishin/` skeleton layers exist with valid `conf/layer.conf` (layer name, priority, compat scarthgap, no recipes yet). `bitbake-layers add-layer` would accept them.
6. `build/Dockerfile` defines a Yocto build host image (Ubuntu 22.04, `kas`, the Yocto host-package list, locale, non-root user). Image builds on this Mac under Podman.
7. `Makefile` exposes at least: `make image` (build the container image), `make shell` (open an interactive shell inside the container with the repo bind-mounted at the same path), `make kas-shell` (drop into `kas shell kas/reterminal-hifi.yml`), `make clean` (remove the container image).
8. `mirror-sources.txt` lists the upstream repos we'll later mirror to our own infra (per top-level plan Phase 0 task #5). No mirroring is actually performed in Phase 0.
9. README explains: what the project is, how to enter the build environment, where the top-level plan lives, where future plans go (`.agents/plans/`).
10. `.gitignore` covers Yocto build artifacts, sstate, downloads, editor cruft, and Podman/Docker local state.
11. `make shell` succeeds end-to-end on this Mac (Podman 5.5.0, applehv, 4 cpu / 17 GB / 93 GB disk).

Out of scope for Phase 0:

- Any actual `bitbake` invocation.
- Resolving real upstream SRCREVs (placeholder values are acceptable; nailing them is a Phase 0 follow-up).
- Mirroring upstream repos.
- Any layer recipe content.
- CI configuration.

## Detailed Implementation Plan + Reasoning

### Repo layout

```
~/code/byxorna/reterminal-hifi-appliance/
├── .agents/
│   └── plans/
│       └── 2026-05-25__13-45-14 - phase-0-project-scaffolding.md
├── .gitignore
├── AGENTS.md
├── README.md
├── Makefile
├── mirror-sources.txt
├── build/
│   └── Dockerfile
├── kas/
│   └── reterminal-hifi.yml
├── meta-kiosk-os/
│   ├── COPYING.MIT
│   ├── README.md
│   └── conf/
│       └── layer.conf
└── meta-kiosk-app-feishin/
    ├── COPYING.MIT
    ├── README.md
    └── conf/
        └── layer.conf
```

The top-level plan continues to live in the private sync vault at `/Users/gconradi/sync/private.enc/agents/plans/2026-05-23__18-02-43 - reterminal-feishin-appliance.md`. Phase-level plans and any per-feature plans for this project go in this repo's `.agents/plans/`. The repo-local AGENTS.md makes that policy explicit so a future agent session lands on the right location without inheriting the private-vault path.

### Repo-local AGENTS.md

Inherits the prime directive and "Plan & Review" cadence from the top-level `~/sync/private.enc/AGENTS.md`, but overrides the plan-storage location:

- Plans go to `.agents/plans/<date in yyyy-mm-dd__HH-MM-SS> - <TASK_NAME>.md` (repo-local, not the private vault).
- Keep the same section conventions (requirements / detailed plan + reasoning / task list).
- Keep the same documentation-style and epistemic-integrity rules.
- Add a short project-specific section: what this repo builds, where the top-level plan lives, how to enter the build env.

### Build container

The Yocto build host runs inside Podman. Image is built from `build/Dockerfile`:

- Base: `ubuntu:22.04` (matches Yocto scarthgap LTS host requirements).
- Installs the Yocto host package set per the scarthgap manual.
- Installs `kas` via pip (current stable; pin in image for reproducibility).
- Creates a non-root user `builder` with UID/GID configurable at build time so bind-mounted files don't end up root-owned on the host.
- Sets locale to `en_US.UTF-8` (Yocto fetch tools require a UTF-8 locale).
- Workdir `/workspace`, the bind-mount target for this repo.

`Makefile` orchestrates:

- `make image` -> `podman build -t reterminal-hifi-builder:latest build/`
- `make shell` -> `podman run --rm -it -v "$(PWD)":/workspace:Z reterminal-hifi-builder:latest /bin/bash`
- `make kas-shell` -> same as `make shell` but with entrypoint `kas shell kas/reterminal-hifi.yml`
- `make clean` -> `podman rmi reterminal-hifi-builder:latest`

The `:Z` SELinux relabel flag is harmless on macOS (Podman ignores it) and correct if a Linux user later runs the same Makefile. We do not pass `--privileged` or any device passthrough in Phase 0; KVM acceleration on macOS isn't available anyway, and Yocto doesn't need it for parsing / fetching / small builds.

A bind-mounted sstate-cache and downloads dir (under `~/.cache/reterminal-hifi-builder/{downloads,sstate}`) keeps Yocto state across container restarts. We add the mount in the Makefile so first run creates the directories; the Dockerfile itself stays stateless.

### kas configuration stub

`kas/reterminal-hifi.yml` is a minimal but valid kas file. It declares:

- header version 14
- machine `seeed-reterminal` (declared but unused until Phase 2)
- distro `kiosk-os` (placeholder, no distro conf yet)
- target `core-image-minimal` for Phase 1
- repos: poky, meta-openembedded, meta-raspberrypi, meta-seeed-cm4, meta-clang, meta-browser, meta-rauc, meta-rauc-community with `branch: scarthgap` and `commit: TODO-<layer>` placeholders
- layers list referencing `meta-kiosk-os` and `meta-kiosk-app-feishin` from this repo

The placeholder commits are flagged in the file with a `# TODO Phase 0 follow-up: resolve real SRCREV before first build` comment so Phase 1 can't accidentally build against floating HEAD.

### Skeleton layers

Each of `meta-kiosk-os/` and `meta-kiosk-app-feishin/` ships:

- `COPYING.MIT` (standard MIT text)
- `README.md` (one paragraph: what this layer is for)
- `conf/layer.conf` with `BBFILE_COLLECTIONS`, `BBFILE_PATTERN_<name>`, `BBFILE_PRIORITY_<name>`, `LAYERSERIES_COMPAT_<name> = "scarthgap"`, and `LAYERDEPENDS_<name>` left empty for now.

No recipes, no classes. Just enough that the layer is structurally valid.

### Source mirror manifest

`mirror-sources.txt` is plain text, one repo per line, format `<role> <upstream-url> <intended-branch>`:

```
poky                  git://git.yoctoproject.org/poky                                  scarthgap
meta-openembedded     git://git.openembedded.org/meta-openembedded                     scarthgap
meta-raspberrypi      git://git.yoctoproject.org/meta-raspberrypi                      scarthgap
meta-seeed-cm4        https://github.com/Seeed-Studio/meta-seeed-cm4.git               scarthgap
meta-clang            https://github.com/kraj/meta-clang.git                           scarthgap
meta-browser          https://github.com/OSSystems/meta-browser.git                    scarthgap
meta-rauc             https://github.com/rauc/meta-rauc.git                            scarthgap
meta-rauc-community   https://github.com/rauc/meta-rauc-community.git                  scarthgap
seeed-linux-dtoverlays https://github.com/Seeed-Studio/seeed-linux-dtoverlays.git      master
```

We do not mirror in Phase 0. The file is a contract for Phase 0 follow-up work and for the eventual CI mirror job.

### .gitignore

Covers Yocto build dirs (`build/tmp`, `build/downloads`, `build/sstate-cache`, `build-*`, `tmp-*`, `sstate-cache/`), kas state (`.kas-cache`), editor cruft (`.idea/`, `.vscode/`, `*.swp`), macOS junk (`.DS_Store`), and Podman/Docker local volumes if anyone runs them at repo root.

### README

Two screens, max. Sections:

1. What this is (one paragraph; link to the top-level plan path in the private vault).
2. Quickstart: `make image`, `make shell`, `make kas-shell`.
3. Repo layout (one paragraph + tree).
4. Where plans live (`.agents/plans/`, link to this Phase 0 plan).
5. Status: pre-build scaffold; no working image yet.

### Git initialization

- `git init` (default branch `main`).
- `git config user.name` / `user.email` left to the host's global settings.
- First commit includes everything above.
- No remote configured in Phase 0; the user will add one when they're ready to push.

### Validation

After scaffolding:

1. `cd ~/code/byxorna/reterminal-hifi-appliance && make image` succeeds (Podman builds the Ubuntu 22.04 image with kas installed).
2. `make shell` opens a bash prompt inside the container, `pwd` shows `/workspace`, `ls` shows the repo, `kas --version` prints a version, `whoami` shows the non-root user.
3. `make kas-shell` runs (it will fail or warn because SRCREVs are TODO placeholders; that's expected and not a Phase 0 failure).

### Risks and notes

- Podman on macOS uses applehv; image build pulls Ubuntu base from a registry (Docker Hub by default). If the user's Podman is configured for a different default registry, `make image` may prompt or fail. The Makefile uses fully qualified `docker.io/library/ubuntu:22.04` to avoid this.
- macOS-side filesystem perf is the long-term bottleneck for Yocto builds. Phase 0 doesn't hit it. Phase 1+ may motivate moving sstate to a Podman-managed named volume; out of scope here.
- kas is pinned to 5.2 in the Dockerfile. The kas config uses header version 14, which is backwards compatible with kas 5.x (latest format is version 22).
- **Discovered during implementation:** macOS default GID (20, `staff`) collides with Ubuntu's `dialout` group. Dockerfile uses `groupadd -o` / `useradd -o` to allow GID reuse.
- **Discovered during implementation:** Host `~/.docker/config.json` may contain `credHelpers` entries (e.g. `ecr-login`) that Podman tries to load, causing `error getting credentials`. Makefile creates an empty auth file at `~/.cache/reterminal-hifi-builder/.podman-auth.json` and passes `--authfile` to all Podman commands to bypass this.
- **Discovered during implementation:** kas 5.0+ uses `pyproject.toml` for packaging, and Ubuntu 22.04's pip 22.0.2 cannot parse the metadata (produces package name `unknown` instead of `kas`). Fixed by upgrading pip before installing kas. kas is now pinned to 5.2.

## Task List

### Setup

- [x] Create `~/code/byxorna/reterminal-hifi-appliance` directory tree (`.agents/plans/`, `build/`, `kas/`, `meta-kiosk-os/conf/`, `meta-kiosk-app-feishin/conf/`)
- [x] `git init` in repo root, default branch `main`

### Docs and policy

- [x] Write repo-local `AGENTS.md` directing plans to `.agents/plans/`, inheriting top-level prime directive + plan cadence
- [x] Copy this plan into `.agents/plans/2026-05-25__13-45-14 - phase-0-project-scaffolding.md`
- [x] Write `README.md` (project description, quickstart, repo layout, plans location, status)
- [x] Write `.gitignore` covering Yocto / kas / Podman / editor / macOS artifacts
- [x] Write `mirror-sources.txt` with the upstream repo list per the manifest above

### Build environment

- [x] Write `build/Dockerfile`: Ubuntu 22.04 base, Yocto scarthgap host packages, `kas` via pip, non-root `builder` user with configurable UID/GID, UTF-8 locale, `/workspace` workdir
- [x] Write `Makefile` with `image`, `shell`, `kas-shell`, `clean` targets; bind-mount this repo at `/workspace`; pass through host UID/GID; mount `~/.cache/reterminal-hifi-builder/{downloads,sstate}` if present

### Yocto skeleton

- [x] Write `kas/reterminal-hifi.yml` stub: header v14, machine `seeed-reterminal`, distro `kiosk-os`, target `core-image-minimal`, layer list with placeholder TODO SRCREVs and an explicit follow-up comment
- [x] Write `meta-kiosk-os/conf/layer.conf`, `meta-kiosk-os/README.md`, `meta-kiosk-os/COPYING.MIT`
- [x] Write `meta-kiosk-app-feishin/conf/layer.conf`, `meta-kiosk-app-feishin/README.md`, `meta-kiosk-app-feishin/COPYING.MIT`

### Validation

- [x] `make image` succeeds on this Mac
- [x] `make shell` lands in `/workspace` as the `builder` user with `kas --version` working
- [x] `make kas-shell` parses the kas file (TODO SRCREVs are expected to warn / fail at fetch time; parse success is enough for Phase 0)

### Commit

- [x] `git add -A && git commit -m "Phase 0 scaffolding"` (no push; no remote configured)

### Phase 0 close-out (post-scaffold additions)

- [x] Fix kas version: upgrade pip in Dockerfile to work around Ubuntu 22.04 pip 22.0.2 metadata bug, pin kas==5.2
- [x] Add `docs/building.md` — build instructions, cache management, bind mounts
- [x] Add `docs/dependencies.md` — host prerequisites, container contents, mise
- [x] Add `.mise.toml` — skeleton mise config for host dev tool management
- [x] Update `README.md` — add docs/ and .mise.toml to layout, link to docs/dependencies.md
- [x] Update `AGENTS.md` — add docs/ and .mise.toml to layout, note kas 5.2
- [x] Commit close-out additions

### Follow-ups (not Phase 0 acceptance, deferred to Phase 1 entry)

- [ ] Resolve real SRCREVs for every layer in `kas/reterminal-hifi.yml`
- [ ] Decide whether to mirror upstream sources before first real build (cheap insurance against a vendor takedown; one-evening task)
- [ ] Consider switching `git://` URLs to `https://` if git protocol remains blocked in the Podman container
