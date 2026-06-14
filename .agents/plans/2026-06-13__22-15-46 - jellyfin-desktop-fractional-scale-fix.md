# Fix: jellyfin-desktop black screen on compositors without wp_fractional_scale_v1

## Intent

Fix the black screen when jellyfin-desktop runs under Weston 13.0.1 kiosk-shell. The app hangs in `wait_for_vo_window()` because `jfn_wl_scale_known()` requires a `wp_fractional_scale_v1.preferred_scale` event that Weston 13.0.1 never sends.

Also fix Mesa shader cache EACCES caused by podman creating an intermediate mount-point directory as root.

## Root Cause: Black Screen

Call chain that never completes:

1. `app.rs:~655` calls `wait_for_vo_window()`, loops until `vo_ready()` returns true
2. `vo_ready()` requires `host_ready()`
3. `host_ready()` (`wlproxy_host.rs:29`) delegates to `jfn_wl_scale_known()`
4. `jfn_wl_scale_known()` (`proxy.rs:70`) checks `WINDOW_STATE.scale() > 0.0`, initialized to 0
5. `scale` is only set by the `on_scale` callback, fired by `FracScaleH::handle_preferred_scale()`
6. That handler only fires on `wp_fractional_scale_v1.preferred_scale` events
7. Weston 13.0.1 doesn't implement this protocol server-side (confirmed by Weston source, runtime logs)

The wlproxy's `PendingConfigure` defaults `scale_120` to 120 (1.0x), so `fire_configure()` delivers correct physical pixel sizes. But `WINDOW_STATE.scale_bits` is a separate atomic in a separate module, starts at 0, and never gets set.

## Root Cause: Mesa Shader Cache EACCES

app.json mounts persistent cache at `/home/kiosk/.cache/jellyfin-desktop`. Podman auto-creates the intermediate `/home/kiosk/.cache/` directory as root:root before the userns mapping applies. The bind mount covers `jellyfin-desktop/` with correct ownership, but `.cache/` stays root:root mode 755. Mesa tries to mkdir `mesa_shader_cache_db` inside it as uid 810, gets EACCES.

## Detailed Implementation Plan

### Black screen fix

Patch `jfn_wl_scale_known()` to also return true when an `xdg_toplevel.configure` has been received (window size is known). A configure proves the compositor is alive and has committed to a geometry. Without fractional scale, the implicit scale is 1.0.

```rust
pub fn jfn_wl_scale_known() -> bool {
    WINDOW_STATE.scale() > 0.0 || jfn_wl_window_size_known()
}
```

Safe because all downstream consumers already default to scale 1.0 when the sentinel is unset: `jfn_wl_get_cached_scale()` returns 1.0, `PendingConfigure.scale_120` defaults to 120, CEF's `cached_scale` returns 1.0.

Applied as a `git apply` patch in the Dockerfile: `containers/jellyfin-desktop/patches/0001-wayland-fallback-scale-for-compositors-without-fractional-scale.patch`.

### Mesa shader cache fix

Set `MESA_SHADER_CACHE_DIR=/home/kiosk/.cache/jellyfin-desktop/mesa` in app.json's env block. Points Mesa at a subdirectory of the existing persistent bind mount, which is writable by kiosk and survives reboots.

## Task List

- [x] Trace root cause through upstream source code
- [x] Confirm Weston 13.0.1 lacks `wp_fractional_scale_v1` server-side
- [x] Confirm no upstream fix exists or is in progress
- [x] Design minimal patch
- [x] Write plan
- [x] Apply patch to Dockerfile
- [x] Add MESA_SHADER_CACHE_DIR to app.json env
- [ ] Rebuild container and test on device
- [ ] Confirm fix resolves the black screen
- [ ] Confirm shader cache populates at /home/kiosk/.cache/jellyfin-desktop/mesa
- [ ] File upstream bug against jellyfin/jellyfin-desktop with root cause analysis, affected compositors, and suggested fix
