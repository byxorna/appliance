# Hardware Button Input Handler

## Intent

Make the SJ201 front-panel buttons (volume up, volume down, action, mic mute) control PipeWire volume and app media playback. Use `triggerhappy` (already in meta-oe) as the evdev-to-action dispatcher. Keep the framework generic in `meta-appliance-os` so any variant can drop in its own key mappings.

## Detailed Implementation Plan

### Layer structure

triggerhappy integration lives in `meta-appliance-os` as a new recipe: `appliance-input-handler`. This recipe:

1. Adds `triggerhappy` as an `RDEPENDS`.
2. Installs small shell helper scripts under `/usr/libexec/appliance/` that triggerhappy configs call.
3. Overrides the upstream triggerhappy systemd service to run as a dedicated `inputd` user (UID 820) with `input` group for evdev access and environment pointing at the weston session's PipeWire/D-Bus sockets.
4. Registers `inputd` as a static UID/GID in the appliance-os passwd/group files.

BSP layers drop variant-specific `.conf` files into `/etc/triggerhappy/triggers.d/`. The mycroft-mkii BSP gets `sj201-buttons.conf` mapping its four GPIO keys.

### Dedicated user: `inputd`

UID 820, GID 820, in the 800-899 appliance accounts range. Supplementary groups:

- `input` (evdev access to `/dev/input/event*`)

PipeWire socket access: PipeWire's default socket permissions are `0700` owned by `weston`. Rather than adding `inputd` to the `weston` group and relaxing socket permissions, the systemd service unit uses `SupplementaryGroups=` and we configure PipeWire to create its socket with group `pipewire` readable (`0770`). `inputd` joins the `pipewire` group. This is how PipeWire upstream recommends cross-user access.

Alternatively, if PipeWire socket permission changes prove complex, a simpler approach: a tmpfiles.d rule that runs `setfacl` on the socket, or a small `ExecStartPre` in the triggerhappy service that waits for and chmod's the socket. The cleanest option is a PipeWire config drop-in that sets `socket.permissions = 0770` and `socket.group = pipewire`.

D-Bus session bus access: the weston session bus socket at `/run/user/800/bus` has mode `0777` (srw-rw-rw-), so no extra group needed.

### Helper scripts

Scripts live at `/usr/libexec/appliance/` and are called by triggerhappy trigger configs.

`volume-up`:
```sh
#!/bin/sh
exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
```

`volume-down`:
```sh
#!/bin/sh
exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
```

`media-play-pause`:
```sh
#!/bin/sh
exec dbus-send --session --type=method_call \
  --dest=org.mpris.MediaPlayer2.chromium.instance1 \
  /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.PlayPause
```

`mic-mute-toggle`:
```sh
#!/bin/sh
exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
```

The MPRIS destination for play/pause needs validation on the device. Chromium exposes MPRIS when media is playing, but the bus name may vary. A wildcard approach (find any `org.mpris.MediaPlayer2.*` destination) may be needed. Can iterate after basic wiring works.

### triggerhappy service override

The upstream service runs as `--user nobody`. We replace it with a drop-in that runs as `inputd`:

```ini
[Service]
ExecStart=
ExecStart=/usr/sbin/thd --triggers /etc/triggerhappy/triggers.d/ --socket /run/thd.socket --deviceglob /dev/input/event*
User=inputd
Group=inputd
SupplementaryGroups=input pipewire
Environment=XDG_RUNTIME_DIR=/run/user/800
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/800/bus
```

No `--user nobody` flag. `thd` itself runs as `inputd`. Child processes (helper scripts calling `wpctl`, `dbus-send`) inherit the environment and group memberships.

### PipeWire socket permissions

Add a PipeWire config drop-in in `meta-appliance-audio` that makes the PipeWire native socket group-accessible:

```
# /etc/pipewire/pipewire.conf.d/10-socket-permissions.conf
context.properties = {
    server.socket.permissions = 0770
    server.socket.group = pipewire
}
```

This lets any user in the `pipewire` group connect as a client. The `kiosk` user (container apps) connects via bind-mounted sockets so this doesn't affect them.

### TAS5806 default volume

Separate from triggerhappy. The `tas5806-init.c` sets register 0x4c to `0x60` (-48 dB). Bump to `0x30` (-24 dB) so software volume at 100% is a reasonable listening level. Users control perceived volume through PipeWire (0-100%).

### Default PipeWire volume

PipeWire defaults to 0.40 (40%) for new sinks. Add a WirePlumber config file in the audio layer that sets the default sink volume to 1.0 (100%), letting the TAS5806 hardware level be the ceiling.

## Reasoning

**Dedicated `inputd` user, not root or weston.** Root is unnecessary privilege for a daemon that only reads evdev and calls `wpctl`/`dbus-send`. Running as `weston` couples the input handler to the compositor's identity. A dedicated user with only `input` and `pipewire` groups is the minimum privilege needed.

**PipeWire socket group access via `pipewire` group.** The `pipewire` group (GID 906) already exists in the static ID table but has no members. Adding `inputd` to it and configuring PipeWire to set socket group to `pipewire` is clean and follows PipeWire's intended multi-user access model.

**triggerhappy over custom C.** Packaged, maintained, handles device hotplug via udev, trivial config format.

**Helper scripts, not inline commands.** Keeps trigger config clean, makes commands testable independently, lets BSP layers override behavior without changing trigger mappings.

**Config split (OS layer vs BSP layer).** Helper scripts are hardware-agnostic (`wpctl`/`dbus-send`). Trigger config mapping specific key codes is hardware-specific (SJ201 buttons vs reTerminal buttons). Splitting lets variants share action scripts.

**TAS5806 volume bump.** -48 dB hardware floor means PipeWire at 100% is still quiet. -24 dB gives a reasonable range without clipping risk.

## Task List

- [x] Add `inputd` user (UID 820, GID 820) to `layers/meta-appliance-os/files/passwd` and `layers/meta-appliance-os/files/group`
  - Supplementary groups: `input`, `pipewire`

- [x] Create `layers/meta-appliance-os/recipes-support/appliance-input-handler/appliance-input-handler.bb`
  - RDEPENDS on `triggerhappy`
  - Creates `inputd` user via `inherit useradd` with `input` and `pipewire` supplementary groups
  - Installs helper scripts to `/usr/libexec/appliance/`
  - Installs triggerhappy systemd service drop-in

- [x] Create helper scripts: `volume-up`, `volume-down`, `media-play-pause`, `mic-mute-toggle`

- [x] Create triggerhappy systemd drop-in to run as `inputd` with correct groups and PipeWire/D-Bus env
  - Also added `weston` to `SupplementaryGroups` and `PIPEWIRE_REMOTE` env var for socket access

- [x] Add PipeWire socket permissions config drop-in in `meta-appliance-audio`
  - Set `server.socket.permissions = 0770`, `server.socket.group = pipewire`

- [x] Create `layers/meta-appliance-bsp-mycroft-mkii-rpi-devkit/recipes-support/appliance-input-handler/appliance-input-handler.bbappend`
  - Installs `sj201-buttons.conf` into `/etc/triggerhappy/triggers.d/`
  - Maps KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_VOICECOMMAND, KEY_MICMUTE

- [x] Bump TAS5806 digital volume from 0x60 to 0x48 in `tas5806-init.c`
  - Revised from 0x30 (-24 dB) to 0x48 (-36 dB) after first attempt was too loud

- [x] Add WirePlumber default volume config (set default sink volume to 0.2)
  - Revised from 1.0 to 0.6, then to 0.2 after testing

- [x] Add `appliance-input-handler` to `IMAGE_INSTALL` in `kas/common.yaml`

- [x] Update docs: add section to `docs/mycroft-mkii-quirks.md` about button mappings
  - Also fixed pre-existing emdash/unicode arrow violations in the file

- [ ] Make `/run/user/800/` group-traversable for `inputd`
  - Added `ExecStartPost=/bin/chmod g+x /run/user/800` to `weston@.service`

- [ ] Test on hardware
  - triggerhappy runs as `inputd`, buttons fire, but wpctl still fails with "Could not connect to PipeWire"
  - Root cause: `/run/user/800/` is 0700, `inputd` can't traverse it
  - Fix deployed (chmod g+x), awaiting rebuild and retest
