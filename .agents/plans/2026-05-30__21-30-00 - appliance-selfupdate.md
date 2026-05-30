# Self-Update Script Embedded in OS

## Requirements

1. A shell script (`appliance-selfupdate`) ships on the device.
2. It clones the appliance repo (or pulls to a given rev if already cloned) into `/tmp`.
3. It runs `make build-update` to produce a RAUC bundle.
4. Assumes all dependencies (git, make, container engine) are present. No guardrails.
5. `docs/updates.md` documents how to run it.

## Detailed Implementation Plan + Reasoning

### Build-time identity from /etc/os-release

The script reads `/etc/os-release` at runtime:

| Field | os-release key | Example |
|---|---|---|
| Repo URL | `HOME_URL` | `https://github.com/byxorna/appliance` |
| Variant | `VARIANT_ID` | `reterminal-hifi` |
| Current version | `VERSION_ID` | `0.1.0-3-gbce1bc4` |

All three already flow from Makefile → kas env → distro conf → os-release. No build-time substitution in the script.

### Script design

Simple, linear, no flags beyond `--ref`. No abstraction.

1. Source `/etc/os-release`.
2. Validate `HOME_URL` is set.
3. Set `WORKDIR=/tmp/appliance-selfupdate`.
4. If `$WORKDIR/.git` exists, `git fetch origin` + `git checkout <ref>` + `git pull` (if on a branch). Otherwise `git clone --depth 1 [--branch <ref>] $HOME_URL $WORKDIR`.
5. `cd $WORKDIR && make VARIANT=${VARIANT_ID} build-update`.
6. Print the path to the `.raucb` artifact.

That's it. No `--install`, no cleanup, no interactive prompts. The user decides what to do with the bundle. Keeping it simple means there's less to debug when testing viability on constrained hardware.

### Why /tmp

`/tmp` is tmpfs or on the rootfs (writable via overlayfs on `/etc`, but `/tmp` is typically tmpfs). On a 4GB RAM CM4, tmpfs `/tmp` may be too small for a full clone + build. If so, the user can override `WORKDIR` or we switch to `/data/selfupdate` in a later iteration. Starting with `/tmp` to see what happens.

### Recipe

Trivial — one script, one recipe. `RDEPENDS` on `git` and `make`. Both already in the image.

### Docs

Add a "Self-update from source" section to `docs/updates.md` after "Rollback". Short: what it does, how to run it, what to do with the bundle.

## Task List

- [x] Write `appliance-selfupdate` shell script
- [x] Create `appliance-selfupdate_1.0.bb` recipe
- [x] Add `appliance-selfupdate` to IMAGE_INSTALL in kas/common.yaml
- [x] Add "Self-update from source" section to docs/updates.md
