# Weston/Kiosk Session Split

## Intent

Separate the Weston compositor from the user session that owns PipeWire, D-Bus, and WirePlumber. Today `weston` (UID 800) owns everything. After this refactor, `weston` only runs the compositor, and `kiosk` (UID 810) owns the `systemd --user` session where PipeWire and D-Bus live. All consumers (container apps, `inputd`) connect to kiosk's session sockets, eliminating cross-UID hacks.

## Detailed Implementation Plan

### What changes

Today's architecture:

- `weston@.service` runs as `User=weston` (UID 800) with `PAMName=weston-autologin`
- `pam_systemd` creates `/run/user/800/` and starts `systemd --user` for UID 800
- PipeWire, WirePlumber, pipewire-pulse, and dbus.socket run as user services in weston's `systemd --user` session
- Container apps (UID 810) get sockets bind-mounted cross-UID: `/run/user/800/pipewire-0` -> `/run/user/810/pipewire-0`
- `inputd` (UID 820) needs `SupplementaryGroups=weston`, `PIPEWIRE_REMOTE=/run/user/800/pipewire-0`, and `chmod g+x /run/user/800` to access weston's session
- D-Bus session bus rejects cross-user connections via `SO_PEERCRED`, breaking MPRIS play/pause from `inputd`

Target architecture:

- `weston@.service` still runs as `User=weston` (UID 800), but with `PAMName=weston-login` (a stripped PAM config that gives weston a logind seat but does not start a full `systemd --user` session, or keeps it minimal)
- A new `kiosk-session.service` system unit runs before app services, triggers `pam_systemd` for `kiosk` (UID 810), creating `/run/user/810/` with a real `systemd --user` session
- PipeWire, WirePlumber, pipewire-pulse, and dbus.socket run as user services in kiosk's session (UID 810)
- Weston's Wayland socket (`/run/user/800/wayland-N`) is still owned by weston. App containers mount it from `/run/user/800/` into the container. This is the only remaining cross-UID path, and it's read-only from the app's perspective (Wayland is a client-server protocol).
- Container apps connect to PipeWire, D-Bus, and PulseAudio at `/run/user/810/` with no cross-UID mapping needed
- `inputd` connects to kiosk's session: `XDG_RUNTIME_DIR=/run/user/810`, sockets at UID 810. It joins the `kiosk` group instead of `weston`.
- D-Bus MPRIS works because `inputd` and the app both connect to the same D-Bus session bus owned by kiosk (UID 810). `SO_PEERCRED` auth still applies, but a D-Bus policy file can allow UID 820 (`inputd`) to send messages on kiosk's bus.

### kiosk-session.service

New system service unit. Runs a lightweight process as `User=kiosk` with `PAMName=kiosk-session`. The PAM stack calls `pam_systemd.so`, which creates the logind session and starts `systemd --user` for UID 810.

The process itself can be `sleep infinity` or a small shell that waits for a stop signal. It exists only to hold the logind session open. Without it, there's no PAM login for kiosk, so no `systemd --user`, so no user services.

```ini
[Unit]
Description=Kiosk user session (PipeWire, D-Bus, WirePlumber)
After=systemd-user-sessions.service dbus.socket
Before=graphical.target

[Service]
Type=simple
ExecStart=/bin/sleep infinity
User=kiosk
Group=kiosk
PAMName=kiosk-session

[Install]
WantedBy=graphical.target
```

### PAM config: kiosk-session

Similar to `weston-autologin` but for kiosk. Needs `pam_systemd.so` to create the user session.

```
auth      sufficient pam_permit.so
account   sufficient pam_permit.so
session   required  pam_env.so
session   required  pam_systemd.so class=user
-session  optional  pam_loginuid.so
```

No `type=wayland` or `desktop=weston` since this isn't a display session.

### Weston PAM (weston-autologin)

Weston still needs `pam_systemd.so` for VT/seat management (logind gives it DRM master, input device access). Keep the existing PAM config. Weston's `systemd --user` session will still start but we stop installing PipeWire/D-Bus user service symlinks into it. Those symlinks move to kiosk's session.

Alternatively, add `type=unmanaged` to weston's PAM config to suppress `systemd --user` entirely, but this needs testing. logind may still need a managed session for DRM/input. Safer to leave it managed and just not put anything in weston's user services.

### Move PipeWire user services to kiosk's session

`pipewire-user-services_1.0.bb` currently installs `default.target.wants` symlinks into a global user unit path (`/usr/lib/systemd/user/default.target.wants/`). These activate for every `systemd --user` instance. That's wrong now: they'd start in both weston's and kiosk's sessions.

Fix: use systemd's per-user override directory. Install symlinks into `/etc/systemd/user/810.conf.d/` ... except systemd doesn't support per-UID unit directories.

Correct approach: the global `default.target.wants` symlinks are fine. PipeWire in weston's session will fail to bind the ALSA device if kiosk's PipeWire already holds it. But two competing PipeWire instances is bad. Options:

1. Remove weston's `systemd --user` entirely (risky for logind seat management).
2. Use a systemd user unit drop-in with `ConditionUser=kiosk` on pipewire.service, wireplumber.service, pipewire-pulse.service. This makes them only activate for the kiosk user.
3. Mask the PipeWire units in weston's user session via a config management approach.

Option 2 is cleanest. Add drop-in files:

```
# /etc/systemd/user/pipewire.service.d/50-kiosk-only.conf
[Unit]
ConditionUser=kiosk
```

Same for `wireplumber.service` and `pipewire-pulse.service`/`pipewire-pulse.socket`.

### Move D-Bus user session to kiosk

Same approach. `dbus-user-session_1.0.bb` installs a global `default.target.wants/dbus.socket` symlink. D-Bus in weston's session is harmless (it's just a socket), but to be clean, add `ConditionUser=kiosk` to the dbus.socket user unit too.

Or leave D-Bus in both sessions. weston's D-Bus isn't the one apps connect to, so it's inert. Keep it simple: don't add conditions to dbus.socket since it's lightweight and harmless.

### Update appliance-app.bbclass

Container apps currently bind-mount from compositor UID 800 into app UID 810. After the split:

| Socket | Before | After |
|--------|--------|-------|
| Wayland | `/run/user/800/wayland-N` -> `/run/user/810/wayland-N` | Same (Wayland stays with weston) |
| PipeWire | `/run/user/800/pipewire-0` -> `/run/user/810/pipewire-0` | `/run/user/810/pipewire-0` -> `/run/user/810/pipewire-0` (same UID, no cross-mapping) |
| PulseAudio | `/run/user/800/pulse/native` -> `/run/user/810/pulse/native` | `/run/user/810/pulse/native` -> `/run/user/810/pulse/native` |
| D-Bus session | `/run/user/800/bus` -> `/run/user/810/bus` | `/run/user/810/bus` -> `/run/user/810/bus` |

For PipeWire, Pulse, and D-Bus, the host path and container path are the same UID. The bind mounts from `/run/user/810/` into the container's `/run/user/810/` become identity mounts. The container already has `-v /run/user/810:/run/user/810`, so the individual socket mounts for PipeWire, Pulse, and D-Bus from UID 800 can be removed. They're already available via the runtime dir mount.

Wayland is the exception. The Wayland socket lives at `/run/user/800/wayland-N` (weston's session) and must be mapped into the container at `/run/user/810/wayland-N`. This cross-UID mount stays.

Changes to `appliance-app.bbclass`:

- Add a new variable `APPLIANCE_SESSION_UID ?= "810"` (the session owner). Initially this equals `APPLIANCE_APP_UID`.
- PipeWire, Pulse, D-Bus bind mounts change from `compositor_uid` to `session_uid` source paths.
- `ExecStartPre` touch/mkdir for PipeWire/Pulse sockets changes from `/run/user/<compositor_uid>/` to `/run/user/<session_uid>/`.
- The `DBUS_SESSION_BUS_ADDRESS` inside the container points to `/run/user/<uid>/bus` (already correct since `uid` = 810).
- Remove the `PULSE_SERVER=unix:/run/user/810/pulse/native` override. With same-UID mounts, libpulse's default `$XDG_RUNTIME_DIR/pulse/native` lookup should work. Test this. If the directory ownership check still fails, keep the override.
- The `Requires=weston@N.service` dependency stays. Add `Requires=kiosk-session.service` and `After=kiosk-session.service` so PipeWire is up before the app starts.

### Update kiosk-user recipe

`kiosk-runtime.conf` currently creates `/run/user/810` via tmpfiles.d. With `kiosk-session.service` using `PAMName=kiosk-session`, `pam_systemd` creates `/run/user/810` automatically. The tmpfiles.d rule becomes redundant and should be removed to avoid a race (tmpfiles creates it before pam_systemd, pam_systemd overwrites it or errors).

Add `pipewire` to kiosk's supplementary groups (needed for PipeWire socket group permissions, though this may no longer be needed since kiosk owns the socket).

Update `kiosk.user` userdb dropin to include `pipewire` in `memberOf` if needed.

### Update inputd / triggerhappy

`triggerhappy-override.conf` changes:

```ini
Environment=XDG_RUNTIME_DIR=/run/user/810
Environment=PIPEWIRE_REMOTE=/run/user/810/pipewire-0
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/810/bus
SupplementaryGroups=input pipewire kiosk
```

Replace `weston` with `kiosk` in supplementary groups. `inputd` needs traverse access to `/run/user/810/`. Since kiosk's session is created by `pam_systemd` with mode 0700, the same `chmod g+x` hack is needed, but now on `/run/user/810/` owned by kiosk.

Move the `ExecStartPost=/bin/chmod g+x` from `weston@.service` to `kiosk-session.service`. weston no longer needs its runtime dir group-traversable.

### D-Bus policy for inputd

The D-Bus session bus default policy only allows connections from the bus owner's UID. `inputd` (UID 820) connecting to kiosk's bus (UID 810) needs an explicit allowlist entry.

The dbus-daemon man page is clear: `<allow user="...">` and `<allow group="...">` rules inside `<policy context="default">` control **connection-level** access, not just message routing. From the man page: "Rules with the `user` or `group` attribute are checked when a new connection to the message bus is established, and control whether the connection can continue." EXTERNAL auth still applies (kernel verifies UID via `SO_PEERCRED`), but the policy allowlist determines which UIDs the server accepts.

Drop-in at `/etc/dbus-1/session.d/10-appliance.conf`:

```xml
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy context="default">
    <allow user="inputd"/>
  </policy>
</busconfig>
```

`inputd` also needs filesystem access to the socket at `/run/user/810/bus`. The `chmod g+x /run/user/810` on `kiosk-session.service` plus `inputd` membership in the `kiosk` group handles directory traversal. The socket itself inherits default permissions (0755) from dbus-daemon, so group traversal of the parent dir is sufficient.

Install from `appliance-input-handler` recipe (it owns the inputd integration).

### PipeWire socket permissions after the split

Today `10-socket-permissions.conf` sets `server.socket.permissions = 0770` and `server.socket.group = pipewire` so `inputd` can reach it. After the split, PipeWire runs as kiosk (UID 810). `inputd` still needs access. The socket permissions config still applies, but the group should be `kiosk` (or keep `pipewire` if `inputd` is in `pipewire` group).

Keep `pipewire` group. It's the standard PipeWire group name. `inputd` is already in it. No change needed.

### Wayland socket access for containers

Containers still need the Wayland socket from `/run/user/800/`. Weston still runs as UID 800. The `ExecStartPost` in `weston@.service` that chgrps/chmods the Wayland socket stays. But the `chmod g+x /run/user/800` can be removed if no other service needs to traverse weston's runtime dir. Containers bind-mount the socket file directly, not the directory. But bind-mounting a specific file requires the parent directory to be traversable by the mounting process (which runs as root via podman), so it's fine.

Remove the `chmod g+x /run/user/800` from `weston@.service`. Root can traverse 0700 dirs.

### weston@.service ordering

Add `Wants=kiosk-session.service` and `After=kiosk-session.service` to `weston@.service` so the kiosk session is up before apps start. Actually, this should go on the app services, not weston. Weston doesn't depend on kiosk's session. Apps do.

The `appliance-app-<name>.service` generated by the bbclass gets `After=kiosk-session.service` so PipeWire/D-Bus are ready before the container starts.

### Summary of file changes

| File | Change |
|------|--------|
| `weston-init/weston@.service` | Remove `chmod g+x /run/user/800` ExecStartPost. Keep Wayland socket chgrp/chmod. |
| `weston-init.bbappend` | Install `kiosk-session.service` and `kiosk-session` PAM config. Or put these in `kiosk-user` recipe. |
| `kiosk-user_1.0.bb` | Add `kiosk-session.service`, `kiosk-session` PAM config. Remove `/run/user/810` from tmpfiles.d (pam_systemd creates it). Add `pipewire` to kiosk's supplementary groups. |
| `kiosk-runtime.conf` | Remove the `/run/user/810` line. |
| `pipewire-user-services_1.0.bb` | Add `ConditionUser=kiosk` drop-ins for pipewire, wireplumber, pipewire-pulse. |
| `dbus-user-session_1.0.bb` | No change (D-Bus in weston's session is inert). |
| `appliance-app.bbclass` | Change PipeWire/Pulse/D-Bus source paths from `compositor_uid` to `session_uid` (810). Add `After=kiosk-session.service`. Remove redundant same-UID bind mounts for PipeWire/Pulse/D-Bus (they're already in `/run/user/810/`). Keep the Wayland cross-UID mount. |
| `triggerhappy-override.conf` | Change all `/run/user/800` to `/run/user/810`. Replace `weston` with `kiosk` in SupplementaryGroups. |
| `appliance-input-handler.bb` | Install D-Bus session drop-in `/etc/dbus-1/session.d/10-appliance.conf` with `<allow user="inputd"/>` for cross-user MPRIS access. |
| `kiosk.user` userdb dropin | Add `pipewire` to `memberOf`. |
| `weston.user` userdb dropin | Remove `input` from `memberOf` (weston doesn't need evdev access after the split, though Weston itself uses it for the compositor... actually, weston needs `input` for touchscreen/keyboard. Keep it.) |

## Reasoning

### Why not just run inputd as kiosk?

This would be the smallest change and would fix the immediate D-Bus problem. But `inputd` is a system service that reads raw evdev input. Running it as kiosk means kiosk has `input` group membership, which grants access to all input devices (keylogger-equivalent on a multi-user system). On this single-purpose appliance the risk is academic, but the split is cheap and keeps the privilege separation clean for when/if the appliance runs untrusted app containers.

### Why a dedicated kiosk-session.service instead of PAM on each app service?

Each app service runs `podman run`, not a direct user process. Adding `PAMName=` to the podman system unit would create a logind session for root (since podman runs as root), not for kiosk. A dedicated session-holder service is the standard pattern for headless user sessions that need `systemd --user`.

### Why ConditionUser= instead of per-user unit directories?

systemd doesn't support per-UID unit install paths. `ConditionUser=` on a drop-in is the documented way to restrict a user unit to a specific user.

### Why `<allow user="inputd"/>` instead of anonymous auth?

The dbus-daemon man page documents that `<allow user="...">` rules inside `<policy context="default">` control connection-level access, not just message routing. EXTERNAL auth still applies (kernel verifies UID via `SO_PEERCRED`), but the policy allowlist determines which authenticated UIDs the server accepts. This is more precise than `<auth>ANONYMOUS</auth>` + `<allow_anonymous/>`, which would let any process with socket access connect regardless of identity.

## Task List

- [x] Create `kiosk-session.service` system unit in `kiosk-user` recipe
  - Type=simple, ExecStart=/bin/sleep infinity, User=kiosk, PAMName=kiosk-session
  - ExecStartPost=/bin/chmod g+x /run/user/810 (moved from weston@.service)
  - WantedBy=graphical.target, Before=graphical.target

- [x] Create `kiosk-session` PAM config in `kiosk-user` recipe
  - pam_permit for auth/account, pam_systemd.so for session (class=user)

- [x] Update `kiosk-user_1.0.bb` recipe
  - Add SRC_URI for kiosk-session.service and kiosk-session PAM file
  - Install kiosk-session.service to systemd_system_unitdir
  - Install kiosk-session PAM to /etc/pam.d/
  - Enable via graphical.target.wants symlink
  - Add SYSTEMD_SERVICE for kiosk-session.service
  - Add `pipewire` to kiosk's supplementary groups

- [x] Update `kiosk-runtime.conf` tmpfiles.d
  - Remove the `/run/user/810` line (pam_systemd creates it now)

- [x] Update `kiosk.user` userdb dropin
  - Add `pipewire` to `memberOf`

- [x] Add ConditionUser=kiosk drop-ins for PipeWire user services
  - Single `50-kiosk-only.conf` drop-in with `ConditionUser=kiosk`
  - Installed for pipewire.service, wireplumber.service, pipewire-pulse.service, pipewire-pulse.socket
  - Installed from `pipewire-user-services_1.0.bb` via a loop

- [x] Update `weston@.service`
  - Remove `ExecStartPost=/bin/chmod g+x /run/user/800` (moved to kiosk-session)
  - Keep Wayland socket chgrp/chmod ExecStartPost lines

- [x] Update `appliance-app.bbclass`
  - Add `APPLIANCE_SESSION_UID ?= "810"`
  - Add `session_uid` parameter to `appliance_app_podman_cmd`
  - Bind-mount `/run/user/<session_uid>` as the runtime dir (PipeWire, Pulse, D-Bus all live here)
  - Remove individual PipeWire/Pulse/D-Bus cross-UID bind mounts (redundant with session runtime dir mount)
  - Keep `PULSE_SERVER` env override (libpulse secure-dir check can still fail with mount layering)
  - Add `Requires=kiosk-session.service` and `After=kiosk-session.service` to generated unit
  - Update `ExecStartPre` touch/mkdir paths from compositor_uid to session_uid

- [x] Update `triggerhappy-override.conf`
  - Change `XDG_RUNTIME_DIR` to `/run/user/810`
  - Change `PIPEWIRE_REMOTE` to `/run/user/810/pipewire-0`
  - Change `DBUS_SESSION_BUS_ADDRESS` to `unix:path=/run/user/810/bus`
  - Replace `weston` with `kiosk` in SupplementaryGroups

- [x] Create D-Bus session config for cross-user access
  - Install `/etc/dbus-1/session.d/10-appliance.conf` with `<allow user="inputd"/>` inside `<policy context="default">`
  - Installed from `appliance-input-handler` recipe

- [x] Update docs
  - Update `docs/mycroft-mkii-quirks.md` section 6: PipeWire now runs in kiosk session (UID 810), test commands updated
  - Update AGENTS.md gotcha about PipeWire session UID
  - Update `scripts/diag-display.sh` to check PipeWire/D-Bus in `/run/user/810`

- [x] Update TODO.md
  - Remove the "Separate compositor user from session user" refactor item (done)
  - D-Bus MPRIS cookie-auth issue kept (separate from cross-UID problem)

- [x] Build and test
  - Verified: volume keys work (inputd -> kiosk session PipeWire)
  - Verified: Feishin audio playback works
  - Verified: networking works
  - Verified: weston still has DRM master and input access (display, touch working)
  - Not yet tested: media-play-pause (MPRIS over kiosk's D-Bus)
  - Not yet tested: wpctl status via kiosk session

## Release Summary

Separated the Weston compositor from the user session that owns PipeWire,
D-Bus, and WirePlumber. Before this change, `weston` (UID 800) owned
everything and other services needed cross-UID hacks to access sockets in
`/run/user/800/`.

After:
- `weston` (UID 800) runs the compositor only. Its Wayland socket is the
  only remaining cross-UID path.
- `kiosk` (UID 810) owns the `systemd --user` session via
  `kiosk-session.service` + PAM. PipeWire, WirePlumber, pipewire-pulse,
  and D-Bus run here.
- Container apps mount `/run/user/810` directly (same UID, no cross-UID
  mapping for audio or D-Bus). Wayland socket still bind-mounted from
  `/run/user/800/`.
- `inputd` connects to kiosk's session at `/run/user/810/`, with a D-Bus
  policy drop-in allowing cross-user MPRIS access.
- `ConditionUser=kiosk` drop-ins prevent PipeWire from starting in
  weston's `systemd --user` session.

### Files changed

| File | Change |
|------|--------|
| `kiosk-user/files/kiosk-session.service` | New. Holds kiosk's logind session open. |
| `kiosk-user/files/kiosk-session` | New. PAM config for kiosk-session (pam_systemd class=user). |
| `kiosk-user/kiosk-user_1.0.bb` | Install kiosk-session.service + PAM config; add pipewire to supplementary groups; inherit systemd. |
| `kiosk-user/files/kiosk-runtime.conf` | Remove `/run/user/810` tmpfiles line (pam_systemd creates it). |
| `kiosk-user/files/kiosk.user` | Add `pipewire` to `memberOf`. |
| `pipewire-user-services/50-kiosk-only.conf` | New. `ConditionUser=kiosk` drop-in. |
| `pipewire-user-services_1.0.bb` | Install 50-kiosk-only.conf for 4 units; update description. |
| `weston-init/weston@.service` | Remove `chmod g+x /run/user/800` (moved to kiosk-session). |
| `appliance-app.bbclass` | Add APPLIANCE_SESSION_UID; refactor podman mounts to use session_uid; add kiosk-session.service dependency. |
| `appliance-input-handler/files/triggerhappy-override.conf` | Point all paths at `/run/user/810`; replace `weston` with `kiosk` in groups. |
| `appliance-input-handler/files/10-appliance.conf` | New. D-Bus session policy allowing inputd cross-user connection. |
| `appliance-input-handler.bb` | Install 10-appliance.conf to `/etc/dbus-1/session.d/`. |
| `docs/mycroft-mkii-quirks.md` | Update section 6 for kiosk session (UID 810). |
| `AGENTS.md` | Update PipeWire gotcha for kiosk session. |
| `scripts/diag-display.sh` | Check PipeWire/D-Bus in `/run/user/810`. |
| `TODO.md` | Remove completed refactor item. |
