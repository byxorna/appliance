# PipeWire Audio Support

## Requirements

1. Audio output devices must be visible to Feishin (and any future app) inside containers.
2. PipeWire runs on the host under the weston user's session (UID 800), creating a real socket at `/run/user/800/pipewire-0`.
3. The existing socket passthrough in `appliance-app.bbclass` must work as-is — no changes to the app framework.
4. Audio dependencies live in a **separate layer** (`meta-appliance-audio`) so audio support can be included or excluded per variant.
5. WM8960 I2S codec on the reTerminal must be usable as an ALSA sink for PipeWire.
6. HDMI audio output should also be available (RPi handles this via the vc4 driver).

## Detailed Implementation Plan + Reasoning

### Problem analysis

The container infrastructure already plumbs `/run/user/800/pipewire-0` into app containers and the Feishin container has PipeWire client libraries. But no PipeWire daemon runs on the host — the socket is a zero-byte placeholder created by `ExecStartPre` in `appliance-app.bbclass`.

Weston runs as a system service (`weston@.service`) with `User=weston` and `PAMName=weston-autologin`. The PAM config includes `pam_systemd.so type=wayland class=user`, which creates a proper systemd user session (logind session) for UID 800. This means systemd user services **can** run under UID 800 — they just aren't installed.

### Architecture

```
┌─────────────────────────────────────────────────────┐
│ Host (UID 800 weston session)                       │
│                                                     │
│  weston@2.service                                   │
│       ↓ (PAM creates user session)                  │
│  pipewire.service (user)                            │
│       → creates /run/user/800/pipewire-0            │
│  wireplumber.service (user)                         │
│       → session manager, routes ALSA sinks          │
│  pipewire-pulse.service (user)                      │
│       → PulseAudio compat socket                    │
│                                                     │
│  ┌───────────────────────────────────────┐          │
│  │ Container (UID 810 kiosk)             │          │
│  │  /run/user/810/pipewire-0             │          │
│  │    ↑ bind-mount from host 800→810     │          │
│  │  Electron → libpipewire → socket      │          │
│  └───────────────────────────────────────┘          │
└─────────────────────────────────────────────────────┘
```

### Key design decisions

**User services, not system services.** PipeWire is designed to run per-user. The weston session already provides the right scope. Running PipeWire as a system service is possible but non-standard and complicates socket ownership.

**Enabling user services at build time.** Yocto's `systemd.bbclass` cannot enable user services — it only handles system units. The standard workaround is a recipe that creates `default.target.wants/` symlinks under `/usr/lib/systemd/user/` at image build time. This is what we'll do in the new layer's recipe.

**Separate layer (`meta-appliance-audio`).** Keeps audio concern isolated. The layer depends on `meta-appliance-os` (for the weston user) and `meta-multimedia` (for PipeWire/WirePlumber recipes). Variant configs that want audio add the layer and its packages to `IMAGE_INSTALL`.

**No changes to `appliance-app.bbclass`.** The existing socket passthrough and placeholder-touch logic already handles the case where PipeWire starts after the container (app gets no audio until PipeWire runs, then reconnects). Once PipeWire is actually running, the touch becomes a no-op because the real socket already exists.

**`pipewire-pulse` for PulseAudio compat.** Many Electron apps (including Chromium's audio backend) try PulseAudio first. `pipewire-pulse` provides a PulseAudio-compatible socket. However, the container currently only bind-mounts `pipewire-0`, not the PulseAudio socket at `/run/user/800/pulse/`. Two options:
  - (a) Also bind-mount the pulse socket in `appliance-app.bbclass` — but we said no framework changes.
  - (b) Set `PULSE_SERVER=unix:/run/user/810/pipewire-0` in the container — PipeWire's native protocol can handle PulseAudio clients if they connect to the right socket. Actually, this won't work — libpulse expects the PulseAudio protocol, not PipeWire's native protocol.
  - (c) Install `pipewire-pulse` on the host so it creates `/run/user/800/pulse/native`, and add a pulse socket bind-mount to `appliance-app.bbclass`.

Decision: We **will** need a small `appliance-app.bbclass` change to also bind-mount the PulseAudio compat socket. This is the most robust approach — Electron/Chromium strongly prefers PulseAudio as its audio backend. The alternative (forcing Electron to use ALSA directly via env vars) is fragile.

**Revised: minimal `appliance-app.bbclass` change.** Add a bind-mount for the PulseAudio socket directory (`/run/user/800/pulse/` → `/run/user/810/pulse/`). This is a one-line addition parallel to the existing PipeWire socket mount.

### Layer structure

```
layers/meta-appliance-audio/
├── conf/
│   └── layer.conf
├── recipes-multimedia/
│   └── pipewire/
│       ├── pipewire-user-services_1.0.bb    # enables PipeWire user services
│       └── files/
│           └── pipewire-user-enable.conf     # tmpfiles.d or preset (see below)
└── README.md
```

### Enabling user services

The cleanest approach for enabling systemd user services at image build time:

Create symlinks in the image filesystem:
```
/usr/lib/systemd/user/default.target.wants/pipewire.service → ../pipewire.service
/usr/lib/systemd/user/default.target.wants/wireplumber.service → ../wireplumber.service
/usr/lib/systemd/user/default.target.wants/pipewire-pulse.service → ../pipewire-pulse.service
/usr/lib/systemd/user/default.target.wants/pipewire-pulse.socket → ../pipewire-pulse.socket
```

These go in a simple recipe (`pipewire-user-services_1.0.bb`) that `RDEPENDS` on `pipewire`, `wireplumber`, and `pipewire-pulse`.

### PulseAudio socket passthrough

The PulseAudio compat socket lives at `/run/user/800/pulse/native` on the host. The container needs it at `/run/user/810/pulse/native`. We can bind-mount the whole `pulse/` directory.

In `appliance-app.bbclass`, add after the PipeWire line:
```python
args += ['-v', '/run/user/%s/pulse:/run/user/%s/pulse' % (compositor_uid, uid)]
```

And a corresponding `ExecStartPre` placeholder for the directory (not file):
```
ExecStartPre=-/bin/sh -c '[ -d /run/user/<compositor_uid>/pulse ] || mkdir -p /run/user/<compositor_uid>/pulse'
```

## Task List

- [x] **Create `layers/meta-appliance-audio/conf/layer.conf`**
  - Collection: `meta-appliance-audio`
  - Priority: 10
  - `LAYERDEPENDS`: `meta-appliance-os meta-multimedia`
  - `LAYERSERIES_COMPAT`: `scarthgap`

- [x] **Create `layers/meta-appliance-audio/recipes-multimedia/pipewire/pipewire-user-services_1.0.bb`**
  - Simple recipe, no source — just installs symlinks
  - `do_install` creates `default.target.wants/` symlinks for:
    - `pipewire.service`
    - `wireplumber.service`
    - `pipewire-pulse.service`
    - `pipewire-pulse.socket`
  - `RDEPENDS`: `pipewire wireplumber pipewire-pulse`
  - `FILES:${PN}` covers `${systemd_user_unitdir}/default.target.wants/`

- [x] **Update `appliance-app.bbclass`** — add PulseAudio socket passthrough
  - Add `-v /run/user/<compositor_uid>/pulse:/run/user/<uid>/pulse` bind-mount
  - Add `ExecStartPre` to mkdir the pulse directory placeholder
  - Keep parallel structure with existing PipeWire socket passthrough

- [x] **Register the layer in `kas/common.yaml`**
  - Add `meta-appliance-audio` under local repos
  - Add `pipewire-user-services` to `IMAGE_INSTALL` in a new `audio:` local_conf_header

- [x] **Verify `DISTRO_FEATURES`** — confirm `pipewire` feature is not needed
  - `meta-multimedia`'s `pipewire` recipe should build with just `alsa` in DISTRO_FEATURES
  - `pulseaudio` is removed — confirm this doesn't conflict with `pipewire-pulse` (it shouldn't; `pipewire-pulse` replaces PulseAudio, it doesn't depend on it)

- [ ] **Test on hardware**
  - Confirm `pipewire.service` starts in the weston user session
  - Confirm `/run/user/800/pipewire-0` is a real socket
  - Confirm Feishin sees audio output devices
  - Confirm audio plays through WM8960 (I2S) and/or HDMI
  - Confirm the D-Bus MPRIS errors are not related (separate issue)

- [x] **Document** — add a brief section to the layer README explaining the audio architecture
