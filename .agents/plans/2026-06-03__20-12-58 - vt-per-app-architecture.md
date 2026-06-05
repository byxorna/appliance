# VT-per-App Architecture — Revised Kiosk Model

Supersedes the iframe/shell/coordinator sections of the master plan
(`2026-05-23__18-02-43 - reterminal-feishin-appliance.md`). The partition
layout, RAUC, BSP, boot, persistent-data, audio, and update sections of the
master plan remain unchanged.

## Requirements

1. Each application runs as a native Wayland client under its own Weston
   (kiosk-shell) instance on a dedicated Linux VT.
2. App switching is VT switching — F4 cycles VTs round-robin.
3. Feishin runs as its native Electron build (not the web build). This gives
   MPV audio backend, MPRIS transport, and native Electron UI with no iframe
   shim layer.
4. Hardware buttons (F1-F3) send MPRIS D-Bus commands to the active media
   player. No custom playback coordinator.
5. No settings UI in MVP — all configuration is done over SSH.
6. No app-switcher overlay or now-playing bar in MVP.
7. Future apps (Home Assistant dashboard, etc.) are additional VTs with their
   own compositor instance.

## Detailed Implementation Plan + Reasoning

### Architecture: one Weston per VT

Each application gets:

```
VT N  →  weston@N.service (kiosk-shell)  →  app process (Electron, Chromium, GTK, etc.)
```

Weston's kiosk-shell makes the app fullscreen with no decorations. Each
Weston instance binds to its own VT and owns its own Wayland socket
(`$XDG_RUNTIME_DIR/wayland-N`). Apps are fully isolated at the process level.

Switching apps = `chvt N`. The F4 button daemon calls `chvt` to cycle
through active VTs round-robin.

### Why this is better than the iframe model

- **Any Wayland-capable app works.** Electron, GTK, Qt, a Cage+Chromium
  instance serving a web app, a terminal — anything that speaks Wayland.
- **No playback shim.** Feishin's Electron build already speaks MPRIS. The
  button daemon sends D-Bus method calls directly. Zero custom protocol.
- **No shell web app.** No kiosk-shell (our web app), no kiosk-httpd, no
  per-app nginx, no iframe lifecycle management, no per-app origin tricks.
- **Simpler RAM story.** One Electron instance (~300-500MB) instead of
  Chromium (~400-600MB) + Electron (~300-500MB) in the iframe model.
  Additional lightweight apps (GTK settings panel, etc.) are cheap.
- **Simpler crash recovery.** App crashes are per-VT. A crashed app's Weston
  restarts independently (`Restart=on-failure`). Other VTs are unaffected.

### What is removed from the master plan

| Component | Status |
|---|---|
| `kiosk-shell` (web app) | **Removed.** No iframe host, no app switcher overlay, no settings panel, no now-playing bar. |
| `kiosk-playd` (coordinator) | **Removed.** MPRIS over D-Bus replaces it entirely. |
| `kiosk-httpd` (per-app nginx) | **Removed.** No web apps to serve. |
| `playback-shim.js` | **Removed.** Feishin speaks MPRIS natively. |
| `kiosk-app.bbclass` | **Simplified.** No longer validates web manifests or port uniqueness. Becomes a simpler class that installs app metadata and wires up a systemd service. |
| `app.json` manifest | **Simplified.** No `port`, `entry`, `capabilities`, `env` fields. Just `name`, `display_name`, `icon`, `vt`, `exec_start`. |
| Per-app origin isolation (`app-<name>.kiosk.local`) | **Removed.** Process isolation replaces it. |
| Settings UI (WiFi, audio, updates) | **Deferred.** SSH-only for MVP. |

### What stays from the master plan

Everything outside the shell/coordinator/app-hosting model:

- Partition layout (boot + rootfs-a + rootfs-b + data)
- RAUC A/B updates with U-Boot slot switching
- `kiosk-buttond` (hardware button daemon) — simplified, see below
- Persistent data model (`/data/platform/`, `/data/apps/<name>/`)
- Audio stack (PipeWire + WirePlumber + ALSA)
- BSP layer (`meta-appliance-bsp-reterminal`)
- First-boot WiFi provisioning (via `wifi.conf` file-drop on boot partition;
  no touchscreen UI in MVP since there's no settings shell)
- IR remote support (evdev → `kiosk-buttond`)
- Security model (locked root, no exposed services, RAUC signing)
- Crash handling (per-service `Restart=`, watchdog)
- Logging (volatile journald + persistent ring on `/data/`)

### kiosk-buttond (revised)

The button daemon is simplified. It reads evdev events from the reTerminal
GPIO buttons and the IR receiver, and dispatches actions:

| Button | Action | Implementation |
|---|---|---|
| F1 | Play/pause | `dbus-send` → `org.mpris.MediaPlayer2.Player.PlayPause` |
| F2 | Queue selected item | App-specific (see below) |
| F3 | Next track | `dbus-send` → `org.mpris.MediaPlayer2.Player.Next` |
| F4 | Cycle VTs | `chvt` to next active VT (round-robin) |
| Power (short) | Screen blank/wake | DRM DPMS toggle on `/dev/dri/card0` |
| Power (long >2s) | Shutdown | `systemctl poweroff` |

**MPRIS target resolution.** The daemon finds the active MPRIS player by
enumerating D-Bus names matching `org.mpris.MediaPlayer2.*`. If exactly one
player is registered, it gets all transport commands. If multiple players
exist, commands go to the one that most recently reported `Playing` status
(tracked by watching `PropertiesChanged` on each player's
`org.mpris.MediaPlayer2.Player` interface). This is the same heuristic
`playerctl` uses.

Alternatively, the daemon can just shell out to `playerctl` for transport
commands, which already implements this heuristic. For MVP, wrapping
`playerctl` is the simplest path — the daemon becomes:

```
F1 → playerctl play-pause
F2 → (queue action — app-specific, see below)
F3 → playerctl next
F4 → chvt <next>
```

**F2 (queue selected item).** This is not a standard MPRIS verb — MPRIS has
no concept of "queue the currently highlighted item." The implementation
depends on the foreground app:

- **Feishin:** Feishin's Electron build does not expose a "queue selected
  item" action via any IPC. Options for MVP: (a) send a synthetic keyboard
  shortcut that Feishin maps to its "add to queue" action (Feishin has
  configurable hotkeys), or (b) defer F2 queue functionality to post-MVP and
  leave the button unmapped initially. Option (a) is preferred — `kiosk-buttond`
  sends an `XDG_TOPLEVEL` keyboard event (via `wtype` or `ydotool`) with
  Feishin's configured queue hotkey.
- **Other apps:** Each app defines its own F2 behavior in its manifest or
  not at all. Non-media apps can ignore it.

The daemon itself is a small C or Python program reading evdev. The routing
table (`/etc/kiosk-buttond/routes.toml`) from the master plan still applies
for button-to-action mapping.

Long-press detection for F3 (volume up/down) and power (shutdown) uses the
same timing logic as the original plan.

**D-Bus session bus visibility.** MPRIS lives on the session bus, but
`kiosk-buttond` runs as a system service. Options:

1. **`playerctl` with `DBUS_SESSION_BUS_ADDRESS` pointed at the Weston
   session's bus.** The Weston session runs under a known user; the daemon
   reads the bus address from `/run/user/<uid>/bus` or the environment.
2. **Run `kiosk-buttond` as the same user as Weston** (e.g., the `weston`
   user), so it naturally inherits the session bus.
3. **Use `busctl --user --machine=weston@`** to reach the user bus from a
   system service (systemd 248+ supports this).

Option 2 is simplest for MVP.

### Weston multi-instance service architecture

A systemd template unit `weston@.service` launches one Weston per VT:

```ini
[Unit]
Description=Weston compositor on VT %i
After=systemd-user-sessions.service

[Service]
Type=simple
User=weston
Environment=XDG_RUNTIME_DIR=/run/user/800
Environment=WAYLAND_DISPLAY=wayland-%i
ExecStart=/usr/bin/weston --tty=%i --socket=wayland-%i
TTYPath=/dev/tty%i
StandardInput=tty
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=graphical.target
```

Each app gets a companion service that starts after its Weston instance:

```ini
[Unit]
Description=Feishin on VT %i
Requires=weston@%i.service
After=weston@%i.service

[Service]
Type=simple
User=weston
Environment=WAYLAND_DISPLAY=wayland-%i
Environment=XDG_RUNTIME_DIR=/run/user/800
ExecStart=/usr/bin/feishin --ozone-platform=wayland --enable-features=UseOzonePlatform
Restart=on-failure
RestartSec=2s
```

### VT assignment

Static assignment for MVP:

| VT | App | Notes |
|---|---|---|
| 1 | (reserved) | getty for emergency console access |
| 2 | Feishin | Primary app, default VT at boot |
| 7 | (future) | Next app slot |

`kiosk-buttond` tracks which VTs have active Weston instances and cycles F4
through them. VT 1 (getty) is excluded from the cycle — it's only reachable
via Ctrl-Alt-F1 or SSH.

After boot, `chvt 2` switches to Feishin's VT.

### Feishin recipe (revised)

The recipe changes from building the web bundle to packaging the Electron
AppImage or building from source as an Electron app.

**Option A: Repackage the upstream AppImage (MVP, fastest).**
Feishin publishes `Feishin-<version>-linux-arm64.AppImage` on GitHub releases.
The recipe downloads it, extracts the squashfs payload (`--appimage-extract`),
and installs the contents to `/opt/feishin/`. A wrapper script sets the
right environment and launches the Electron binary with Wayland flags.

Pros: no Node.js/pnpm build toolchain in Yocto, fast recipe, upstream binary.
Cons: not built from source (supply-chain trust concern), may bundle
glibc/libs that conflict with the Yocto rootfs.

**Option B: Build Electron app from source.**
Clone upstream, `pnpm install --frozen-lockfile`, `pnpm run build` (Electron
builder for linux/arm64). Install the unpacked output.

Pros: reproducible, same toolchain as everything else, can patch if needed.
Cons: Electron + Node.js native modules cross-compilation in Yocto is painful.
Needs `nodejs-native`, `pnpm-native`, and Electron's pre-built binaries for
arm64.

**Recommendation: Option A for MVP, migrate to Option B when supply-chain
hygiene or patching demands it.** The AppImage is signed by the upstream
maintainer and the recipe pins by exact version + SHA256. The rootfs is
read-only anyway, so a compromised binary can't persist across a re-flash.

### Persistent data (Feishin)

Feishin's Electron build stores config in `~/.config/feishin/` (via
`electron-store`). The platform binds `/data/apps/feishin/` to the weston
user's `~/.config/feishin/` directory so config survives rootfs updates.

### App manifest (simplified)

```json
{
  "name": "feishin",
  "display_name": "Feishin",
  "vt": 2,
  "exec": "/opt/feishin/feishin --ozone-platform=wayland --enable-features=UseOzonePlatform"
}
```

The manifest drives systemd unit generation at build time. No runtime
manifest discovery needed for MVP (apps are baked into the rootfs).

### What we lose vs. the iframe model

1. **No now-playing bar.** No shell overlay showing track info on top of
   another app. Acceptable for MVP — there's only one app anyway.
2. **No visual app switcher.** Just VT cycling. Fine for 1-2 apps.
3. **No settings UI.** SSH only. Acceptable for MVP.
4. **No playback shim API.** Apps must speak MPRIS natively to get button
   integration. Feishin does; a future web-only app would need a different
   approach (or just not get hardware button support).
5. **Multi-player arbitration is implicit.** `playerctl`'s heuristic picks
   the most recently active player. No explicit priority system. Fine until
   we have 3+ media apps.

All of these are addable later without architectural rework. The VT model
doesn't preclude adding a lightweight app-switcher overlay (on its own VT)
or a now-playing daemon in a future phase.

## Impact on Master Plan Phases

### Phases unchanged
- Phase 0 (scaffolding) — done
- Phase 1 (minimal bootable image) — done
- Phase 2 (reTerminal hardware) — done
- Phase 7 (RAUC A/B) — unchanged
- Phase 8 (persistent data) — bind-mount target changes from web config to
  Electron config dir, but mechanism is the same
- Phase 9 (update delivery) — unchanged
- Phase 10 (polish) — unchanged

### Phases modified

**Phase 3 (platform kiosk infra):**
- ~~meta-chromium~~ → not needed if Feishin is Electron (ships its own Chromium)
- ~~kiosk-app.bbclass (web manifest)~~ → simpler `appliance-app.bbclass`
- ~~kiosk-init (web app discovery)~~ → simpler init that wires bind-mounts and
  starts weston@N + app services
- ~~kiosk-httpd~~ → removed
- Weston multi-instance template unit → new
- Cage → removed (Weston kiosk-shell already implemented, see `2026-05-30__12-33-16`)

**Phase 4 (shell + button daemon):**
- ~~kiosk-shell web app~~ → removed entirely
- `kiosk-buttond` → simplified: evdev → playerctl + chvt
- ~~dual WebSocket client~~ → removed
- ~~shell.json generation~~ → removed

**Phase 4b (playback coordinator):**
- ~~Entire phase removed.~~ MPRIS over D-Bus replaces kiosk-playd.

**Phase 5 (Feishin):**
- ~~Web build recipe~~ → AppImage repackage recipe
- ~~settings.js generation~~ → not needed (Electron has its own config)
- ~~Playback shim adapter~~ → not needed (MPRIS is native)
- Feishin config persistence → bind-mount `~/.config/feishin/` to
  `/data/apps/feishin/`
- Test criteria: "Feishin launches under Weston on VT 2, plays audio via
  PipeWire, responds to F1-F3 via MPRIS, F4 cycles VTs"

**Phase 6 (audio):**
- Unchanged in substance. The audio path is now Feishin Electron → MPV →
  PipeWire → ALSA → output device, which is actually a better path than the
  Chromium Web Audio path in the original plan. MPV can do bit-perfect
  passthrough directly.

## Revised Task List

### Phase 3r: Platform kiosk infrastructure (revised)
- [x] Write `weston@.service` systemd template unit for multi-VT Weston instances
- [x] Write `appliance-app.bbclass` (simplified: installs app metadata, generates per-app systemd service from manifest)
- [x] Write `appliance-init` service (bind-mount wiring for `/data/platform/` and `/data/apps/*/`, VT default selection via `chvt`)
- [x] Configure default boot to VT 2 (Feishin VT)
- [x] Add `kiosk` user (uid 810) with userdb dropins, tmpfiles.d, static passwd/group entries
- [x] Fix `kiosk-user` useradd sysroot failure: use `--user-group` so staticids auto-injects primary group; add `-r wayland` to `GROUPADD_PARAM` so supplementary groups exist in sysroot
- [x] Fix Weston SIGHUP on startup: add `Conflicts=getty@tty%i.service` to `weston@.service`, set `TTYVHangup=no` and `TTYVTDisallocate=no`, disable logind autovt (`NAutoVTs=0`, `ReserveVT=0`)
- [x] Verify Weston kiosk-shell starts on VT 2 (DRM+GL init, DSI-1 output, kiosk-shell loaded — confirmed on hardware)
- [ ] Verify multi-VT Weston (start `weston@2` and `weston@7` simultaneously, switch with `chvt`)

### Phase 4r: Button daemon (revised)
- [ ] Write `kiosk-buttond` recipe: evdev reader for reTerminal buttons + IR receiver
- [ ] F1 → `playerctl play-pause`
- [ ] F2 → queue selected item (synthetic keypress via `wtype`/`ydotool` to Feishin's queue hotkey)
- [ ] F3 → `playerctl next`
- [ ] F4 → `chvt` round-robin through active app VTs (skip VT 1)
- [ ] Power short → DRM DPMS toggle
- [ ] Power long → `systemctl poweroff`
- [ ] Long-press F3 → volume up (repeat); long-press F2 → volume down (repeat)
- [ ] Test on hardware: F1 play/pause and F3 next via MPRIS, F2 queue via synthetic keypress, F4 VT cycling

### Phase 5r: Feishin app (revised)
- [x] Write `feishin_1.13.0.bb` recipe: download arm64 AppImage from upstream GitHub release, extract via `unsquashfs` (cross-arch safe), install to `/opt/feishin/`
- [x] Pin upstream version + SHA256 checksum (v1.13.0, sha256 `3cacc03e...`)
- [x] Write wrapper script with Wayland flags (`--ozone-platform=wayland`, `--enable-features=UseOzonePlatform`, `--no-sandbox`, `--disable-gpu`)
- [x] Set `LD_LIBRARY_PATH=$FEISHIN_DIR` in wrapper so Electron finds bundled GTK3/X11 client libs without requiring `x11` DISTRO_FEATURE
- [x] Write `app.json` manifest: `name: feishin`, `vt: 2`, `exec: /opt/feishin/feishin-wrapper`
- [x] Configure persistent config: bind-mount `/data/apps/feishin/` → `~/.config/feishin/` via systemd `.mount` unit + tmpfiles.d
- [x] Wire into build: `IMAGE_INSTALL` in `common.yaml`, `LAYERDEPENDS` on `meta-appliance-os`
- [x] Runtime deps: `cups-lib`, `expat` added to RDEPENDS; system libs (glib, nss, dbus, cairo, pango, mesa, etc.) via RDEPENDS; bundled libs (GTK3, X11 client) via `LD_LIBRARY_PATH`
- [x] Fix `SYSTEMD_SERVICE` parse-time assignment in `appliance-app.bbclass` (was set too late in `populate_packages:prepend`; moved to anonymous python function)
- [x] BBMASK three broken meta-seeed-cm4 recipes (`reterminalqt5example_git.bb`, `atecc-util.bb`, `python3-seeed-python-reterminal.bb`)
- [ ] Test: Feishin launches on VT 2, connects to Navidrome/Jellyfin, plays audio
- [ ] Test: F1 pauses/resumes, F2/F3 skip tracks (via MPRIS)
- [ ] Test: config survives simulated A/B update (write config, update rootfs, verify config intact)

### Phases 6-10: unchanged from master plan
