# Dockerfile: use upstream container-build.sh directly

## Intent

Replace our ~100-line AppDir assembly in the Dockerfile with a single call to upstream's `container-build.sh`. We already duplicate the Fedora toolchain image (identical package list). The assembly logic, lib stripping, patchelf fixups, and GPU lib removal are all in `container-build.sh`. No reason to maintain a second copy.

## Detailed Implementation Plan

### Stage 1 (builder)

Keep the existing Fedora toolchain setup (RPM Fusion, dev packages, appimagetool). These layers match upstream's `dev/linux/appimage/Dockerfile` and change rarely.

After cloning + `cargo xtask fetch-cef`, replace everything from `cargo xtask build` through the end of stage 1 with:

```dockerfile
RUN mkdir -p /build /host-output && \
    VERSION=dev /src/dev/linux/appimage/container-build.sh
```

`container-build.sh` does all of: `cargo xtask build`, `strip`, AppDir assembly, lib flattening, LLVM/GPU lib stripping, patchelf, and appimagetool packaging. `/tmp/AppDir` survives after the script finishes.

### Stage 2 (runtime)

Unchanged. `COPY --from=builder /tmp/AppDir /opt/jellyfin-desktop`, then fontconfig, verify-deps, wrapper, user setup.

### What we delete

Lines 81-187 of the current Dockerfile (the `cargo xtask build` step and the entire "Assemble AppDir" `RUN` block). ~107 lines replaced by 2.

### What we keep (our additions, not upstream)

- fontconfig + fonts-dejavu-core install (stage 2)
- `verify-deps.sh` with GPU lib allow-list
- `jellyfin-desktop-wrapper`
- `USER 810:810` + `ENTRYPOINT`

### verify-deps.sh

Still needed. `container-build.sh` strips GPU libs from the AppDir (upstream design). Our allow-list in `verify-deps.sh` handles this.

### Risks

`container-build.sh` expects `/build` (cargo output cache) and `/host-output` (AppImage output) to exist as directories. Both are created by `mkdir -p` before the call.

`VERSION` env var controls the AppImage filename. We pass `dev` since we don't use the `.AppImage` file itself (we take `/tmp/AppDir` directly). If `container-build.sh` starts using `VERSION` for something else, this could matter, but it's only used in the output filename today.

If upstream changes `container-build.sh` in a way that breaks with our toolchain image, the build fails loudly. No silent runtime failures.

## Task List

- [x] Rewrite Dockerfile stage 1: remove inline assembly, call `container-build.sh`
- [x] Verify stage 2 is unchanged (fontconfig, verify-deps, wrapper, entrypoint)
- [x] Update the host-mesa plan to reflect this change

## Changes Made

Replaced lines 81-187 of the Dockerfile (~107 lines of inline AppDir assembly) with a 2-line `mkdir -p /build /host-output && VERSION=dev /src/dev/linux/appimage/container-build.sh`. Updated header comments. Stage 2 unchanged.
