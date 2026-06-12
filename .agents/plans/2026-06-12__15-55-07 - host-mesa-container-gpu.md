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

Implementation: rather than mounting each `.so` individually (brittle if soversions change), mount a directory. Create a `/usr/lib/gpu/` directory on the host via a small recipe or tmpfiles.d snippet. Populate it with symlinks to the real libs. Mount `/usr/lib/gpu:/usr/lib/gpu:ro` into the container and set `LD_LIBRARY_PATH` to include it.

Simpler alternative that avoids the indirection: mount `/usr/lib/dri:/usr/lib/dri:ro` (directory, stable path) and `/usr/share/glvnd:/usr/share/glvnd:ro`. For the `.so` files, mount the whole `/usr/lib` as a lower-priority read-only overlay... no, that's complicated.

Simplest approach: the AppDir's `LD_LIBRARY_PATH` puts bundled libs first. Upstream's script deletes GPU libs from the AppDir. When mpv's Mesa `libEGL` (deleted from AppDir) isn't found in `$APPDIR/usr/lib`, the linker falls through to the system `/usr/lib`. So we just need `/usr/lib` to be visible. It already is (the container's Ubuntu rootfs has `/usr/lib`). We just need the host's Mesa files to exist there.

Mount the host libs into `/usr/lib/` in the container. The container's Ubuntu base has an empty `/usr/lib/` (plus fontconfig from our earlier change). The bind-mounts overlay specific files/dirs on top of it.

Final approach for the bbclass:

```python
# Host GPU libraries (Mesa EGL, GBM, DRI drivers). The container's AppDir
# strips these (upstream design), expecting host-provided GPU stack.
args += ['-v', '/usr/lib/dri:/usr/lib/dri:ro']
args += ['-v', '/usr/share/glvnd:/usr/share/glvnd:ro']
# Individual libs: glob at recipe parse time won't work (cross-compile).
# Mount the needed .so files by stable soname.
for lib in ['libEGL.so.1', 'libEGL_mesa.so.0',
            'libgbm.so.1', 'libGLESv2.so.2',
            'libglapi.so.0', 'libGLdispatch.so.0',
            'libdrm.so.2', 'libxshmfence.so.1']:
    args += ['-v', '/usr/lib/%s:/usr/lib/%s:ro' % (lib, lib)]
```

Sonames are stable (`.so.1`, `.so.2`, `.so.0`). They don't change between Mesa minor versions. If a major soversion bump happens (rare, maybe once a decade for libdrm), the build breaks visibly.

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
