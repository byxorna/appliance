# Jellyfin TV Variant

## Intent

Add a new appliance variant `variant-mycroft-mkii-rpi-devkit-tv.yaml` that boots into Jellyfin Desktop instead of Feishin. Same hardware target (Mark II RPi4 + SJ201), same kiosk architecture, different app.

## Situation

- `jellyfin-desktop` is a Rust+CEF+mpv native app (not Electron).
- Nightly aarch64 AppImage builds published at `nightly.link/jellyfin/jellyfin-desktop/workflows/build-linux-appimage/main/linux-appimage-aarch64.zip`.
- The AppImage bundles its own glibc, CEF, mpv, FFmpeg, PipeWire client libs. Self-contained.
- Uses Wayland natively (via `jfn-wayland` crate). Supports `--ozone-platform=wayland` via CEF.
- AppRun creates a symlink at `/tmp/.jf-cef-interp/` for the patched ELF interpreter. Needs writable `/tmp`.
- Same container-based deployment pattern as Feishin: extract AppImage in Ubuntu 24.04 container, passthrough Wayland/PipeWire/D-Bus/GPU.

## Detailed Implementation Plan

### 1. Move `feishin` from common.yaml to variant-specific configs

The kiosk line in common.yaml currently hardcodes `feishin`:
```
IMAGE_INSTALL:append = " weston weston-init kiosk-user appliance-init feishin podman crun fuse-overlayfs dbus-user-session"
```
Remove `feishin` from the kiosk section. Add `feishin` to the `local_conf_header` of every existing variant that uses it:
- `kas/variant-reterminal-hifi.yaml`
- `kas/variant-mycroft-mkii-rpi-devkit-hifi.yaml`

`podman`, `crun`, `fuse-overlayfs`, `dbus-user-session` stay in common (all variants use containers).

### 2. Create `containers/jellyfin-desktop/`

- `Dockerfile`: Ubuntu 24.04 base. Install Wayland/GL/audio libs (similar to Feishin but no GTK/Electron deps). Download aarch64 AppImage from nightly.link, extract with `--appimage-extract`, install wrapper.
- `jellyfin-desktop-wrapper`: Shell script setting up Wayland env and exec'ing the AppRun (or the binary directly with proper LD_LIBRARY_PATH). The AppImage bundles its own glibc so we need to let AppRun handle the ld-linux setup, or replicate its env setup.

Key differences from Feishin container:
- No `--ozone-platform=wayland` (not Electron). jellyfin-desktop uses native Wayland via its own compositor code.
- Needs writable `/tmp` for the CEF interpreter symlink.
- PipeWire client libs are bundled, but SPA_PLUGIN_DIR and PIPEWIRE_MODULE_DIR need to point at bundled paths (AppRun handles this).
- No `--no-sandbox` needed (no Electron sandbox).

### 3. Create Yocto recipe

`layers/meta-appliance-apps/recipes-apps/jellyfin-desktop/jellyfin-desktop_0.0.1.bb`:
- Inherits `appliance-app`
- Ships `app.json` (name=jellyfin-desktop, vt=2, image=appliance-jellyfin-desktop:latest)
- Persistent config: bind-mount for jellyfin-desktop config dir (likely `~/.config/jellyfin-desktop/` or similar)

### 4. Create kas variant

`kas/variant-mycroft-mkii-rpi-devkit-tv.yaml`: clone from hifi variant, replace feishin with jellyfin-desktop in IMAGE_INSTALL, hostname `mycroft-mkii-rpi-devkit-tv`.

## Reasoning

Makefile does not need changes. `VARIANTS` auto-discovers `kas/variant-*.yaml` and container build targets auto-discover `containers/*/Dockerfile`.

## Task List

- [x] Remove `feishin` from `kas/common.yaml` kiosk section
- [x] Add `feishin` to `kas/variant-reterminal-hifi.yaml` local_conf_header
- [x] Add `feishin` to `kas/variant-mycroft-mkii-rpi-devkit-hifi.yaml` local_conf_header
- [x] Create `containers/jellyfin-desktop/Dockerfile`
- [x] Create `containers/jellyfin-desktop/jellyfin-desktop-wrapper`
- [x] Create `layers/meta-appliance-apps/recipes-apps/jellyfin-desktop/jellyfin-desktop_0.0.1.bb`
- [x] Create `layers/meta-appliance-apps/recipes-apps/jellyfin-desktop/files/app.json`
- [x] Create `layers/meta-appliance-apps/recipes-apps/jellyfin-desktop/files/jellyfin-desktop-config.conf`
- [x] Create `layers/meta-appliance-apps/recipes-apps/jellyfin-desktop/files/home-kiosk-.config-jellyfin-desktop.mount`
- [x] Create `kas/variant-mycroft-mkii-rpi-devkit-tv.yaml`
- [x] Update README.md with Mark II hardware + Jellyfin Desktop app

## Changes Made

Moved `feishin` from `kas/common.yaml` kiosk section to per-variant `app:` local_conf_header blocks in `variant-reterminal-hifi.yaml` and `variant-mycroft-mkii-rpi-devkit-hifi.yaml`. Apps are now variant-specific.

Container: `containers/jellyfin-desktop/Dockerfile` is a multi-stage build. Stage 1 (`builder`) uses the upstream Fedora toolchain (RPM Fusion for full FFmpeg, Rust, meson, CEF, patchelf) to compile jellyfin-desktop + mpv from source at a pinned commit (`JELLYFIN_DESKTOP_COMMIT` build arg), then assembles the AppDir following upstream's `container-build.sh` logic. Stage 2 copies the AppDir into Ubuntu 24.04 with the wrapper script. Layers are ordered for cache efficiency: OS upgrade, RPM Fusion, dev packages, appimagetool, source clone, CEF download, build, AppDir assembly. The wrapper delegates to the bundled AppRun, which handles the patched ELF interpreter, LD_LIBRARY_PATH, PipeWire paths, and glibc setup. Jellyfin Desktop auto-detects Wayland via `WAYLAND_DISPLAY` and passes `--ozone-platform=wayland` to CEF internally.

Yocto recipe follows the feishin pattern: inherits `appliance-app`, ships `app.json`, tmpfiles.d conf, and a systemd bind-mount unit for persistent config at `~/.config/jellyfin-desktop`.

kas variant cloned from hifi variant with `jellyfin-desktop` replacing `feishin` in IMAGE_INSTALL, hostname `mycroft-mkii-rpi-devkit-tv`.

README updated with Mark II hardware entry and Jellyfin Desktop application entry.
