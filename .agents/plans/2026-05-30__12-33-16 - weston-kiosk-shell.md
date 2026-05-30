# Weston Kiosk Shell — Boot to Compositor with VT Switching

## Requirements

1. Boot directly into a Wayland compositor (Weston in kiosk-shell mode) on the reTerminal DSI display.
2. Compositor starts with an empty/idle screen initially (no application launched).
3. VT switching works: Ctrl-Alt-F1 drops to a text login console, Ctrl-Alt-F7 returns to the compositor.
4. Display rotation handled (720×1280 portrait panel needs landscape orientation).
5. No new upstream layers required — Weston + weston-init ship in poky.

## Detailed Implementation Plan + Reasoning

### Why Weston over Cage

Cage is not available in any of our upstream layers (poky, meta-oe, meta-raspberrypi). Adding `meta-wayland` would introduce a new layer dependency for a single recipe. Weston is already in poky with `shell-kiosk` enabled by default in its PACKAGECONFIG. The kiosk shell is purpose-built for single-app fullscreen use — identical end result to Cage, zero new dependencies.

### How Weston kiosk-shell works

- `shell=kiosk-shell.so` in `weston.ini` selects the kiosk shell plugin.
- Kiosk shell makes every surface fullscreen with no decorations, task bar, or background.
- If no client connects, Weston shows a black screen (exactly what we want for step 2).
- Later phases will add a systemd service that launches Chromium as the kiosk app.

### Weston service architecture (upstream weston-init)

The `weston-init` recipe provides:
- `weston.service` — runs Weston as a system service on `/dev/tty7` under a `weston` user.
- `weston.socket` — Wayland socket activation.
- `weston.ini` — config file at `/etc/xdg/weston/weston.ini`.
- `weston.env` — environment file at `/etc/default/weston`.
- A `weston` user in the `video`, `input`, `render`, `wayland` groups.

VT switching works because Weston runs on `tty7` (configured in the service unit). systemd auto-spawns `getty@tty1` on Ctrl-Alt-F1.

### Display rotation

The reTerminal has a 720×1280 portrait DSI panel. For landscape mode we need:
- `transform=rotate-270` in the `[output]` section of `weston.ini` (Weston handles this natively via DRM output transform).
- Touch rotation is handled via the DT overlay (`tp_rotate=1` in config.txt) — already configured in the BSP layer.

### Implementation steps

1. **Add `weston` and `weston-init` to IMAGE_INSTALL** in `kas/common.yaml` under a new `kiosk` local_conf_header key.

2. **Create `weston-init` bbappend** in `meta-appliance-os` to customize the kiosk:
   - Override `weston.ini` to set `shell=kiosk-shell.so` and output transform for the DSI panel.
   - Override `weston.env` to set `WESTON_TTY=7` (already the default, but explicit).
   - Add `no-idle-timeout` to PACKAGECONFIG so the screen never blanks.
   - Ensure the `weston` user has access to the DRM device.

3. **Enable graphical.target** — Weston's service unit is `WantedBy=graphical.target`. We need `graphical.target` to be the default systemd target (currently it's likely `multi-user.target`). Set via `SYSTEMD_DEFAULT_TARGET = "graphical.target"` or a symlink.

4. **Validate VT switching** — after boot:
   - Weston should be running on tty7 showing a black screen.
   - Ctrl-Alt-F1 should switch to a text login on tty1.
   - Ctrl-Alt-F7 should switch back to Weston.
   - `loginctl` should show the Weston session.

### What we do NOT need

- No `meta-wayland` layer (Cage) — Weston is in poky.
- No Chromium yet — just the empty compositor for now.
- No custom systemd service — `weston-init` provides one.
- No PAM config changes — `weston-init` includes `weston-autologin`.

## Task List

- [x] Add `weston weston-init` to IMAGE_INSTALL in kas/common.yaml
- [x] Create weston-init bbappend with kiosk-shell weston.ini + DSI output rotation
- [x] Set graphical.target as the default systemd target
- [ ] Build and validate on hardware
- [ ] Verify VT switching (Ctrl-Alt-F1 / Ctrl-Alt-F7)
