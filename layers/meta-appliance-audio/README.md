# meta-appliance-audio

Audio support for the appliance OS. Provides the PipeWire sound server stack so
containerized apps (e.g. Feishin/Electron) can reach the host's audio output.

This layer is optional and self-contained: omit it from a build to produce an
image with no audio stack.

## Architecture

PipeWire runs as **systemd user services** inside the weston compositor's user
session — the same session that already owns the display. Apps run in rootful
podman containers and reach audio by bind-mounting the compositor's per-user
runtime sockets.

Electron/Chromium prefers the PulseAudio backend, so `pipewire-pulse` provides a
Pulse-compatible socket alongside PipeWire's native socket. Both socket
directories are bind-mounted into the container by `appliance-app.bbclass`,
which sources the concrete UIDs and paths.

## User-service enablement

Yocto's `systemd.bbclass` only enables *system* units. The
`pipewire-user-services` recipe enables the user units by installing
`default.target.wants/` symlinks under `${systemd_user_unitdir}`. When
`pam_systemd` opens the compositor's user session, systemd `--user` starts the
wanted services automatically.

## Recipes

- **pipewire-user-services** — no-source recipe that pulls in `pipewire`,
  `wireplumber`, and `pipewire-pulse` and enables them as user services.

## Build integration

Add the `audio` `local_conf_header` block (see `kas/features/audio.yaml`) to install the
stack:

```
IMAGE_INSTALL:append = " pipewire wireplumber pipewire-pulse pipewire-user-services"
```

The `pulseaudio` DISTRO_FEATURE stays removed — `pipewire-pulse` supersedes the
standalone PulseAudio daemon and avoids running two competing sound servers.
