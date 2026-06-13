# Host Mesa + Container GPU Stack

## Intent

Move the GPU userspace stack (Mesa EGL, GBM, DRI drivers) from the container to the host. The jellyfin-desktop container currently bundles Fedora's entire `/usr/lib64` including Mesa, then deletes parts of it (LLVM, DRI drivers, GBM backend) to save space, breaking GPU rendering. mpv falls to `vo/wlshm` (CPU software renderer) instead of using VC4/V3D hardware acceleration.

Installing Mesa on the host and bind-mounting GPU libs into the container gives us:
- GPU-accelerated rendering in mpv via VC4/V3D
- Smaller container image (~200MB less without LLVM)
- One source of truth for the GPU stack, built by Yocto against the actual kernel
- Alignment with upstream's design (AppImage strips GPU libs, expects host to provide them)

## Detailed Implementation Plan

### 1. Ensure Mesa packages are on the host rootfs

Mesa is already built because Weston depends on it (`virtual/egl`, `virtual/libgles2`, `virtual/libgbm` all resolve to `mesa` via meta-raspberrypi's `rpi-default-providers.inc`). Runtime `.so` packages land on the image through shlibdeps.

The exception is `mesa-megadriver` (`/usr/lib/dri/*.so`). DRI drivers are dlopen'd, not linked, so shlibdeps won't pull them in. Add it explicitly to `IMAGE_INSTALL` in `kas/common.yaml` under the `kiosk` section. Also add `libdrm` (same dlopen concern for `libdrm_vc4.so` etc).

Verify after build by checking the sysroot or image manifest for: `libegl-mesa`, `libgbm`, `libgles2-mesa`, `libglapi`, `mesa-megadriver`, `libdrm`.

### 2. Add GPU library bind-mounts to `appliance-app.bbclass`

Add read-only bind-mounts of host GPU libs to the podman run command generation, right after the existing `--device /dev/dri` block. All appliance apps get the compositor's Wayland socket and `/dev/dri` already, so GPU lib access is a natural extension.

Bind-mount these host paths into the container:

| Host path | Why |
|---|---|
| `/usr/lib/dri` | DRI drivers (vc4_dri.so, v3d_dri.so, kmsro_dri.so) |
| `/usr/lib/libEGL*` | Mesa EGL |
| `/usr/lib/libgbm*` | GBM |
| `/usr/lib/libGLESv2*` | GLES2 |
| `/usr/lib/libglapi*` | GL dispatch |
| `/usr/lib/libGLdispatch*` | libglvnd dispatch |
| `/usr/lib/libdrm*` | libdrm + platform modules |
| `/usr/lib/libxshmfence*` | X shared memory fences (Mesa dependency) |
| `/usr/share/glvnd` | EGL vendor JSON |

Final approach for the bbclass: mount host `/usr/lib` at `/usr/lib/gpu` (read-only) and `/usr/lib/dri` at `/usr/lib/dri` (for DRI driver dlopen). Set `LD_LIBRARY_PATH=/usr/lib/gpu` so AppRun appends it after the bundled lib paths. No individual soname mounts, no glvnd dependency, no lib-exists checks. Whatever the host has, the container can find.

```python
args += ['-v', '/usr/lib/dri:/usr/lib/dri:ro']
args += ['-v', '/usr/lib:/usr/lib/gpu:ro']
args += ['-e', 'LD_LIBRARY_PATH=/usr/lib/gpu']
```

### 3. Dockerfile AppDir assembly

We own the AppDir assembly inline in the Dockerfile. ~50 lines of `cp`, `rm`, `find`, `patchelf`. No coupling to upstream's `container-build.sh`. If upstream changes the build layout, we deal with it when things break at build time.

Changes:
- Restore full strip list (LLVM, libgallium, DRI, GBM)
- Add GPU lib deletion block (libEGL, libgbm, libvulkan, libdrm, etc.)
- Keep fontconfig/fonts in stage 2
- Keep `verify-deps.sh` and `jellyfin-desktop-wrapper`

### 4. Revert earlier LLVM/DRI changes in the Dockerfile

The changes made earlier this session (keeping LLVM, DRI, libgallium) get reverted. With host Mesa bind-mounted, the container ships no GPU libs. Restore the full upstream strip list, plus add the GPU lib deletion block from `container-build.sh` that our Dockerfile was missing.

### 5. Keep fontconfig change

The `fontconfig` + `fonts-dejavu-core` addition in stage 2 stays.

## Reasoning

Upstream designed the AppImage to strip GPU libs and use the host's. We align with that by providing the GPU stack from the Yocto-built host rootfs. This is the same model Flatpak and Steam use on Linux.

We own the AppDir assembly outright. No sync obligation to upstream's packaging scripts.

## Task List

- [x] Verify Mesa packages on host (check sysroot/manifest for `libegl-mesa`, `libgbm`, `mesa-megadriver`, `libdrm`)
- [x] Add `mesa-megadriver` to `IMAGE_INSTALL` in `kas/common.yaml`
- [x] Add GPU library bind-mounts to `appliance-app.bbclass`
- [x] Revert Dockerfile LLVM/DRI preservation, add upstream's GPU lib deletion block
- [x] Verify fontconfig change still present in stage 2
- [x] Update `verify-deps.sh` to allow host-provided GPU libs as expected-missing

## Changes Made

### `kas/common.yaml`
Added `mesa-megadriver` to `IMAGE_INSTALL` in the kiosk section. DRI drivers are dlopen'd, so shlibdeps won't pull them automatically.

### `layers/meta-appliance-os/classes/appliance-app.bbclass`
Added GPU library bind-mounts after the `--device /dev/dri` block. Mounts `/usr/lib/dri` and `/usr/share/glvnd` as directories, plus individual soname-versioned libs (`libEGL.so.1`, `libEGL_mesa.so.0`, `libgbm.so.1`, `libGLESv2.so.2`, `libglapi.so.0`, `libGLdispatch.so.0`, `libdrm.so.2`, `libxshmfence.so.1`). All read-only.

### `containers/jellyfin-desktop/Dockerfile`
Restored the full LLVM/toolchain/DRI directory deletion that was removed earlier this session. Added upstream's GPU lib deletion block from `container-build.sh` (strips libEGL, libgbm, libvulkan, libdrm, libglapi, etc. from `usr/lib/`). Fontconfig addition in stage 2 unchanged.

### `containers/jellyfin-desktop/verify-deps.sh`
Added an allow-list of GPU/Mesa soname patterns. Libraries matching the allow-list are reported as "OK (host-provided at runtime)" instead of failing the build. Unrecognized missing libs still fail.
