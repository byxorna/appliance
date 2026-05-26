# Phase 1: First Bootable Image

**Goal**: Build `core-image-minimal` for `MACHINE=appliance-reterminal` using the
upstream `poky` distro. Verify all 12 layers parse and compile cleanly.
Once the base image builds, create the `appliance-os` distro and switch to it.

**Status**: In progress — build reaching image generation (~3668/3671 tasks).
Three upstream layer incompatibilities fixed. Pending: DT overlay removal
needs kernel sstate clean after machine rename.

## Tasks

- [x] Resolve all upstream SRCREVs via `git ls-remote`
- [x] Switch `git://` URLs to `https://` (git protocol blocked by yoctoproject.org)
- [x] Fix `BBFILE_PRIORITY` quoting in custom layer.conf files
- [x] Fix `meta-rauc-community` sublayer path (`meta-rauc-raspberrypi`)
- [x] Add `meta-lts-mixins-rust` (scarthgap/rust) for meta-chromium dependency
- [x] Add `meta-lts-mixins-uboot` (scarthgap/u-boot) for meta-rauc-raspberrypi
- [x] Mount TMPDIR on named Podman volume (macOS case-insensitivity workaround)
- [x] Temporarily switch distro to `poky` for first build
- [x] Achieve clean bitbake parse (2904 recipes, 0 errors)
- [x] Fix GCC 13 parallel build race (gcc-cross bbappend, `-j 2`)
- [x] Fix missing DT overlays for 6.1 kernel (machine conf `KERNEL_DEVICETREE:remove`)
- [x] Fix rpi-bootfiles 404 wget (BBMASK seeed bbappend)
- [x] Derive `appliance-reterminal` machine from `seeed-reterminal` (proper scoping for IMAGE_BOOT_FILES)
- [x] Complete `core-image-minimal` build with `distro: poky`
- [ ] Create `meta-appliance-os/conf/distro/appliance-os.conf` (minimal distro based on poky)
- [ ] Switch kas config back to `distro: appliance-os`
- [ ] Verify build with appliance-os distro
- [ ] Flash image to SD card and boot on reTerminal hardware
- [ ] Document build time, image size, and any issues in this plan

## Architecture decisions

### Named volume for TMPDIR
macOS filesystems (HFS+/APFS) are case-insensitive, which Yocto refuses.
`build/tmp` is mounted on a named Podman volume (`reterminal-hifi-tmpdir`)
so it lives on the VM's case-sensitive ext4 filesystem. The volume persists
across container runs for incremental builds and is cleaned by `make clean`.

### LTS mixin layers
`meta-lts-mixins` is an official Yocto Project repo that backports newer
components to LTS releases. Two branches are needed:
- `scarthgap/rust` — updated Rust toolchain for Chromium (meta-browser)
- `scarthgap/u-boot` — updated U-Boot for RAUC integration (meta-rauc-community)

Both are pinned by commit in `kas/reterminal-hifi.yml`.

### Temporary poky distro
The `appliance-os` distro config doesn't exist yet. Using `poky` for the first
build validates that all layers compile. The appliance-os distro will be created
after the base build succeeds, starting as a thin wrapper around poky with
`DISTRO_FEATURES` customizations.

## Issues discovered

| # | Issue | Resolution |
|---|---|---|
| 1 | `meta-rauc-community` is a multi-layer repo, not a single layer | Added `layers: meta-rauc-raspberrypi:` to kas config |
| 2 | meta-chromium requires `scarthgap-rust-mixin` layer | Added meta-lts-mixins on `scarthgap/rust` branch |
| 3 | meta-rauc-raspberrypi requires `lts-u-boot-mixin` layer | Added meta-lts-mixins on `scarthgap/u-boot` branch |
| 4 | TMPDIR rejected on case-insensitive macOS filesystem | Named Podman volume for `/workspace/build/tmp` |
| 5 | meta-seeed-cm4 missing LAYERSERIES_COMPAT | Upstream issue, harmless warning, not our fix |
| 6 | meta-rauc wants `rauc` in DISTRO_FEATURES | Expected — will be enabled in appliance-os distro |
| 7 | GCC 13 parallel build race on aarch64 (`cc1plus` link fails) | `PARALLEL_MAKE = "-j 2"` in `gcc-cross_%.bbappend` |
| 8 | DT overlays missing in 6.1 kernel (post-6.1 additions in rpi-base.inc) | `KERNEL_DEVICETREE:remove` in `appliance-reterminal.conf` machine conf |
| 9 | rpi-bootfiles wget 404 (dt-blob-disp1-cam2.bin) | `BBMASK +=` in `meta-appliance-os/conf/layer.conf` to mask seeed bbappend |
| 10 | KERNEL_DEVICETREE:remove in bbappend doesn't affect IMAGE_BOOT_FILES | Derived `appliance-reterminal` machine — :remove at machine conf scope |

## Build environment

- Host: macOS arm64, Podman 5.5.0, applehv VM (4 CPU, 17 GB RAM, 93 GB disk)
- Container: Ubuntu 22.04 aarch64 (native), kas 5.2
- Machine: appliance-reterminal (derived from seeed-reterminal, Cortex-A72 aarch64, RPi CM4 based)
- Distro: poky 5.0.18 (temporary, will switch to appliance-os)
- Layers: 10 upstream + 2 local (meta-appliance-os, meta-appliance-app-feishin)
- Tasks: ~3671 total

## Layer priorities

| Layer | Priority |
|-------|----------|
| meta (poky) | 5 |
| meta-seeed-cm4 | 6 |
| meta-raspberrypi | 9 |
| meta-appliance-os | 10 |
| meta-appliance-app-feishin | 10 |
