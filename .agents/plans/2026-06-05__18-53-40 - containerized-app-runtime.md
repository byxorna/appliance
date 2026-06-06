# Containerized App Runtime

Supersedes the app packaging/runtime sections of the app-bundle-updates plan
(`2026-06-04__14-01-36 - app-bundle-updates.md`). The partition layout, RAUC
A/B rootfs updates, VT-per-app architecture, button daemon, persistent data
model, and audio stack remain unchanged.

## Requirements

1. Apps run inside OCI containers managed by podman on the host. The host
   rootfs no longer ships app binaries or their library dependencies.
2. The container image is the unit of app delivery. Updating an app means
   pulling or loading a new container image. No rootfs rebuild, no bitbake.
3. The host rootfs is dramatically simplified: it carries the OS, podman,
   Wayland compositor, audio stack, and a thin app launcher. Not Electron,
   not GTK, not NSS, not cups-lib.
4. Downstream customizers can swap app container images at runtime without
   rebuilding the host OS. Different container images can carry different
   base distros (Ubuntu, Fedora, Alpine) and library stacks.
5. The AppImage is downloaded and run *inside* the container, using the
   container's userland libraries, eliminating the brittle `RDEPENDS` list
   in the Yocto recipe.
6. Persistent app data still lives on `/data/apps/<name>/` and is
   bind-mounted into the container.
7. The existing VT-per-app Weston architecture is preserved. Each app
   container connects to its dedicated Weston compositor via a shared
   Wayland socket.

## Detailed Implementation Plan + Reasoning

### Current pain

The Feishin recipe (`feishin_1.13.0.bb`) carries a long `RDEPENDS` list:

```
wayland libxkbcommon mesa libdrm pipewire wireplumber alsa-lib
nss nspr at-spi2-core pango cairo gdk-pixbuf glib-2.0 dbus cups-lib expat
```

Every time the AppImage's bundled Electron upgrades, its host-side library
requirements shift. Discovering which libraries are needed requires trial
and error (`ldd` on the binary, which itself is not in the image, hence the
`appliance shell` plan). The recipe also needs `INSANE_SKIP`, `SKIP_FILEDEPS`,
`INHIBIT_PACKAGE_STRIP`, and careful `LD_LIBRARY_PATH` management. This is
the most fragile part of the build.

### Target architecture

```
Host rootfs (immutable, RAUC-updated):
  Weston kiosk-shell (per-VT compositor)
  PipeWire + WirePlumber (audio server)
  podman + crun (container runtime)
  appliance-cli (appliance shell, selfupdate, version)
  appliance-app-<name>.service → podman run ...

Container image (OCI, pulled/loaded to /data):
  Ubuntu (or any distro) base userland
  All libraries Electron/the app needs (GTK, NSS, mesa, etc.)
  The AppImage payload (extracted or run directly)
  Wrapper script with Wayland/audio flags
```

### Why containers instead of bundles-on-data

The app-bundle-updates plan moved binaries to `/data` but still required the
host rootfs to ship all shared library dependencies. The container approach
goes one step further:

| Concern | Bundle-on-data | Container |
|---------|---------------|-----------|
| Host RDEPENDS | Still needed (wayland, mesa, nss, etc.) | None. Container carries everything. |
| Library version mismatches | Host libs must match what Electron expects | Container pins exact lib versions |
| Adding a new app | May need new host-side deps → rootfs rebuild | Just pull a new container image |
| Downstream customization | Must use Yocto to change deps | Swap container image (Dockerfile) |
| AppImage "just works" | Needs `LD_LIBRARY_PATH` hacks, `INSANE_SKIP` | Run the AppImage natively in Ubuntu, the distro it was built for |
| Update mechanism | Custom tarball + seed + rollback scripts | `podman pull` or `podman load` (standard OCI tooling) |
| Rollback | Custom `bundle.prev` directory scheme | `podman image tag` previous image, or keep two tags |
| Image size | Host rootfs still large (carries deps) | Host rootfs shrinks ~100-200MB (no app deps); container image is separate |
| Build complexity | Yocto recipe extracts AppImage, manages deps | Yocto recipe is trivial (just the launcher); Dockerfile is a standard Ubuntu container |

### How the container gets Wayland + audio

The container needs access to host hardware/sockets. This is the same
pattern used by Flatpak, Toolbx, and distrobox:

```sh
podman run \
  --name feishin \
  --replace \
  --rm \
  --network host \
  --userns keep-id:uid=810,gid=810 \
  --security-opt label=disable \
  \
  # Wayland socket from the per-VT Weston
  -v /run/user/810/wayland-2:/run/user/810/wayland-2 \
  -e WAYLAND_DISPLAY=wayland-2 \
  -e XDG_RUNTIME_DIR=/run/user/810 \
  -e GDK_BACKEND=wayland \
  \
  # GPU access for hardware-accelerated rendering
  --device /dev/dri \
  \
  # Audio: PipeWire socket from the host
  -v /run/user/810/pipewire-0:/run/user/810/pipewire-0 \
  \
  # D-Bus (for MPRIS, accessibility)
  -v /run/dbus/system_bus_socket:/run/dbus/system_bus_socket \
  -v /run/user/810/bus:/run/user/810/bus \
  -e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/810/bus \
  \
  # Persistent app data
  -v /data/apps/feishin/config:/home/kiosk/.config/feishin \
  \
  ghcr.io/<org>/appliance-feishin:latest \
  /opt/feishin/feishin-wrapper
```

**Key design points:**

- **`--userns keep-id:uid=810,gid=810`**: Maps the container user to the
  host kiosk UID. The Wayland socket and PipeWire socket are owned by
  UID 810 on the host; the container process must present the same UID.
- **`--device /dev/dri`**: Passes GPU device nodes for mesa/DRM.
  Without this, Electron falls back to software rendering (fine for a music
  player but wastes CPU).
- **`--security-opt label=disable`**: Disables SELinux labeling. Not
  relevant on our systemd-based image, but prevents errors if SELinux
  support is compiled into podman.
- **`--network host`**: MPRIS D-Bus, mDNS/Avahi for Navidrome discovery,
  and any network access the app needs.
- **`--replace`**: If the container already exists (e.g. from a crash
  restart), replace it instead of erroring.

### Container image build

The container image is built with a standard Dockerfile, completely outside
of Yocto. This is the key simplification: app packaging becomes a normal
container build that any developer can do without a Yocto environment.

```dockerfile
FROM docker.io/library/ubuntu:24.04

# Install the libraries Electron/Feishin needs
RUN apt-get update && apt-get install -y --no-install-recommends \
    libwayland-client0 libwayland-cursor0 libwayland-egl1 \
    libxkbcommon0 libdrm2 libgbm1 \
    libegl1 libgl1 libgles2 \
    libgtk-3-0 libnss3 libnspr4 \
    libatk1.0-0 libatk-bridge2.0-0 \
    libpango-1.0-0 libcairo2 \
    libgdk-pixbuf-2.0-0 libglib2.0-0 \
    libdbus-1-3 libcups2 libexpat1 \
    libasound2t64 \
    libpipewire-0.3-0 pipewire-alsa \
    squashfs-tools \
    && rm -rf /var/lib/apt/lists/*

# Download and extract the AppImage
ARG FEISHIN_VERSION=1.13.0
ADD https://github.com/jeffvli/feishin/releases/download/v${FEISHIN_VERSION}/Feishin-linux-arm64.AppImage /tmp/feishin.AppImage
RUN chmod +x /tmp/feishin.AppImage && \
    cd /tmp && /tmp/feishin.AppImage --appimage-extract && \
    mv /tmp/squashfs-root /opt/feishin && \
    rm /tmp/feishin.AppImage

COPY feishin-wrapper /opt/feishin/feishin-wrapper

# Run as non-root (mapped to kiosk user via --userns keep-id)
USER 810:810
ENTRYPOINT ["/opt/feishin/feishin-wrapper"]
```

**Why this is better:**

- `apt-get install` is a solved problem. No `INSANE_SKIP`, no `SKIP_FILEDEPS`,
  no `INHIBIT_PACKAGE_STRIP`. Ubuntu's package manager handles library deps.
- `--appimage-extract` works natively because the container is the same
  arch+distro the AppImage was built for. No more `grep -aobP 'hsqs'` hacks.
- Upgrading Feishin means changing `FEISHIN_VERSION` and rebuilding the
  container. No Yocto rebuild. No `SRC_URI[sha256sum]` dance.
- The Dockerfile can be in this repo or in a separate app-images repo. Either
  way, it is a standard `docker build` / `podman build`.

### Container image delivery

Several options, roughly ordered by complexity:

1. **Pre-loaded in the WIC data partition.** At image build time, `podman save`
   the container image to a tarball, embed it in the WIC data partition. A
   first-boot oneshot runs `podman load` to import it. This is the equivalent
   of the seed mechanism from the bundle plan.

2. **`podman pull` from a registry.** On first boot or on demand, pull from
   GHCR, Docker Hub, or a self-hosted registry. Requires network. This is
   the steady-state update path.

3. **`podman load` from a file.** For airgapped deployments, scp a tarball
   to the device and `podman load -i <file>`. Same as the `appliance shell`
   airgapped model.

**Recommendation:** Combine (1) for first boot and (2) for updates. The
image build pre-loads the container image so the appliance works out of the
box without network. Updates use `podman pull` (or `podman load` for
airgapped). This mirrors how the bundle plan used seed tarballs + manual
update scripts, but with standard OCI tooling instead of custom scripts.

### Host-side recipe changes

The `feishin` Yocto recipe becomes extremely thin:

```python
SUMMARY = "Feishin music player (containerized)"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "..."

inherit appliance-app

SRC_URI = " \
    file://app.json \
    file://feishin-config.conf \
    file://home-kiosk-.config-feishin.mount \
"

# No RDEPENDS on wayland, mesa, nss, etc. The container carries them.
# No INSANE_SKIP, no SKIP_FILEDEPS, no INHIBIT_PACKAGE_STRIP.
# No AppImage download, no unsquashfs.

do_install() {
    # Persistent config plumbing (unchanged)
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/feishin-config.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/feishin-config.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/home-kiosk-.config-feishin.mount \
        ${D}${systemd_system_unitdir}/home-kiosk-.config-feishin.mount
}

SYSTEMD_SERVICE:${PN}:append = " home-kiosk-.config-feishin.mount"
FILES:${PN} += " \
    ${nonarch_libdir}/tmpfiles.d/feishin-config.conf \
    ${systemd_system_unitdir}/home-kiosk-.config-feishin.mount \
"
```

The `appliance-app.bbclass` generated service unit changes `ExecStart` from
a direct binary invocation to a `podman run` command. The bbclass reads a
new `image` field from `app.json`:

```json
{
  "name": "feishin",
  "display_name": "Feishin",
  "vt": 2,
  "image": "ghcr.io/<org>/appliance-feishin:latest",
  "mounts": [
    "/data/apps/feishin/config:/home/kiosk/.config/feishin"
  ]
}
```

### app.json schema evolution

| Field | Old | New | Notes |
|---|---|---|---|
| `name` | required | required | Unchanged |
| `display_name` | required | required | Unchanged |
| `vt` | required | required | Unchanged |
| `exec` | required | **removed** | Container ENTRYPOINT replaces this |
| `image` | n/a | **required** | OCI image reference |
| `mounts` | n/a | optional | Extra bind mounts beyond the standard set |
| `devices` | n/a | optional | Extra device passthrough (default: `/dev/dri`) |
| `env` | n/a | optional | Extra environment variables |
| `podman_args` | n/a | optional | Escape hatch for extra raw `podman run` flags |

The `exec` field is removed because the container image's ENTRYPOINT (or CMD)
defines what runs. If an app needs to override the entrypoint, it can use
`podman_args: ["--entrypoint", "/custom/cmd"]`.

### Generated systemd service unit

The `appliance-app.bbclass` generates a service like:

```ini
[Unit]
Description=Feishin (appliance app on VT 2)
Documentation=file:///opt/feishin/app.json
Requires=weston@2.service
After=weston@2.service

[Service]
Type=simple
ExecStart=/usr/bin/podman run \
    --name appliance-app-feishin \
    --replace \
    --rm \
    --network host \
    --userns keep-id:uid=810,gid=810 \
    --security-opt label=disable \
    --device /dev/dri \
    -v /run/user/810/wayland-2:/run/user/810/wayland-2 \
    -v /run/user/810/pipewire-0:/run/user/810/pipewire-0 \
    -v /run/dbus/system_bus_socket:/run/dbus/system_bus_socket \
    -v /run/user/810/bus:/run/user/810/bus \
    -e WAYLAND_DISPLAY=wayland-2 \
    -e XDG_RUNTIME_DIR=/run/user/810 \
    -e GDK_BACKEND=wayland \
    -e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/810/bus \
    -v /data/apps/feishin/config:/home/kiosk/.config/feishin \
    ghcr.io/<org>/appliance-feishin:latest
ExecStop=/usr/bin/podman stop -t 10 appliance-app-feishin

Restart=on-failure
RestartSec=3s

[Install]
WantedBy=graphical.target
```

The service no longer has `User=kiosk`. Podman runs as root on the host
(rootful podman is simpler for device access and socket permissions). The
container process itself runs as UID 810 inside the container via
`--userns keep-id`. Rootless podman for the kiosk user is a future
optimization; rootful is simpler for MVP and typical for kiosk/embedded
deployments.

### Update workflow

**Online update:**
```sh
appliance app update feishin          # pulls :latest tag
appliance app update feishin v1.14.0  # pulls specific tag
```

Under the hood:
```sh
podman pull ghcr.io/<org>/appliance-feishin:v1.14.0
podman tag ghcr.io/<org>/appliance-feishin:v1.14.0 \
           ghcr.io/<org>/appliance-feishin:latest
systemctl restart appliance-app-feishin.service
```

**Rollback:**
```sh
appliance app rollback feishin
```

Under the hood:
```sh
podman tag ghcr.io/<org>/appliance-feishin:previous \
           ghcr.io/<org>/appliance-feishin:latest
systemctl restart appliance-app-feishin.service
```

Tag management: before each update, the current `:latest` is retagged to
`:previous`. This gives one-step rollback with no custom directory schemes.

**Airgapped update:**
```sh
# On build host:
podman save ghcr.io/<org>/appliance-feishin:v1.14.0 -o feishin-v1.14.0.tar

# On device:
podman load -i feishin-v1.14.0.tar
appliance app update feishin v1.14.0
```

### Container image storage

Podman stores images under `/var/lib/containers/` by default. On our system,
`/var` is on the rootfs (read-only). Options:

1. **Symlink `/var/lib/containers` → `/data/platform/containers`** at
   first boot. Simple, works, uses the persistent data partition.
2. **Configure `graphroot` in `/etc/containers/storage.conf`** to point to
   `/data/platform/containers`. More explicit.
3. **Overlay `/var/lib/containers`** with a writable layer (like etc-overlay).

**Recommendation: Option 2.** Set `graphroot = "/data/platform/containers"`
in `storage.conf` shipped by the devtools or a new `appliance-containers`
recipe. This cleanly uses the persistent partition and survives rootfs A/B
updates.

### Impact on the appliance-shell plan

The `appliance shell` plan (`2026-06-05__18-40-39`) is complementary and
unchanged. `appliance shell` is a developer debugging tool (ad-hoc
container). Containerized app runtime is the production app execution model.
They share podman infrastructure and the `appliance` CLI multiplexer.

The `appliance` CLI gains a new subcommand namespace:

```
appliance app list                        # list running app containers
appliance app update <name> [version]     # pull new image, restart
appliance app rollback <name>             # revert to previous image
appliance app logs <name>                 # podman logs
appliance app exec <name> [cmd...]        # podman exec into running container
appliance app status <name>               # image version, uptime, health
```

### What stays on the host rootfs

| Component | Why it stays |
|---|---|
| Kernel + DTBs | Hardware |
| systemd | Init, service management |
| Weston (kiosk-shell) | Compositor must own the DRM device and VTs directly |
| PipeWire + WirePlumber | Audio server must own ALSA devices directly |
| podman + crun | Container runtime |
| Connectivity (ssh, wpa_supplicant, dhcpcd) | Network must work before containers |
| RAUC | Rootfs A/B updates |
| appliance-cli | System management commands |
| appliance-app-*.service units | Systemd units that launch podman |
| Container storage.conf | Podman configuration |

### What moves into the container

| Component | Was on host | Now in container |
|---|---|---|
| Electron/Feishin binaries | `/opt/feishin/` (~300MB) | Container image layer |
| GTK3, cairo, pango, gdk-pixbuf | `RDEPENDS` | `apt-get install` in Dockerfile |
| NSS, NSPR, cups-lib | `RDEPENDS` | `apt-get install` in Dockerfile |
| mesa (client libs) | `RDEPENDS` | `apt-get install` in Dockerfile |
| wayland client libs | `RDEPENDS` | `apt-get install` in Dockerfile |
| AppImage extraction logic | `do_install()` | Dockerfile `RUN` |

### Risks and mitigations

| Risk | Mitigation |
|---|---|
| GPU acceleration may not work through container | `--device /dev/dri` passes the GPU. Mesa in the container must match the host kernel's DRM driver. The RPi VC4 driver is well-supported in Ubuntu's mesa packages. Fall back to `--disable-gpu` (already the default). |
| PipeWire version mismatch | PipeWire's Unix socket protocol is stable. Container's pipewire client libs do not need to match the host server version exactly. If issues arise, pin the container's pipewire client to the same major version as the host. |
| Wayland protocol version mismatch | Wayland is forward-compatible. Weston on the host advertises protocol versions; the container's client libs negotiate down. Not a practical concern. |
| Container startup latency | Podman run with a local image adds ~1-2s. Acceptable for an appliance that boots in 15-30s anyway. Image layers are cached on `/data`. |
| Disk space (container image + rootfs) | The rootfs shrinks by ~300MB (no app payload + deps). The container image is ~400-500MB. Net increase ~100-200MB. Acceptable on 16GB+ eMMC. Container image layers are shared across apps if they use the same base. |
| Podman/crun OCI overhead | Minimal. crun is a lightweight runtime. CPU overhead is negligible. Memory overhead is the container metadata, not the process itself (no VM). |
| Rootless vs rootful podman complexity | Start with rootful (simpler device access). Rootless is a future optimization. |

### Phasing

This plan can be implemented incrementally:

**Phase 1: Infrastructure.** Set up container storage on `/data`, configure
`storage.conf`, add the `appliance app` subcommands to the CLI.

**Phase 2: Feishin container image.** Write the Dockerfile, build the
container image, test Wayland+audio passthrough manually via
`appliance shell`-style podman commands.

**Phase 3: bbclass integration.** Update `appliance-app.bbclass` to generate
container-launching service units from the new `app.json` schema. Update the
Feishin recipe to the thin skeleton.

**Phase 4: First-boot seeding.** Pre-load the container image into the WIC
data partition so the appliance works out of the box.

**Phase 5: Update/rollback CLI.** Implement `appliance app update/rollback`.

## Task List

### Phase 1: Container infrastructure on host
- [x] Create `storage.conf` with `graphroot = "/data/platform/containers/storage"`, shipped via `container-host-config.bbappend`
- [x] Create `containers.conf` with `image_copy_tmp_dir = "/data/platform/containers/tmp"` for podman load/pull temp space (also shipped via `container-host-config.bbappend`)
- [x] Ensure `/data/platform/containers` and `/data/platform/containers/tmp` are created by `appliance-init.service` (mkdir -p at boot)
- [x] Verify podman works with the custom graphroot (verified on device: `podman images` runs clean, no warnings)
- [ ] Add `appliance app` subcommand namespace to the `appliance` CLI multiplexer (from the appliance-shell plan)

### Phase 2: Feishin container image
- [x] Write `Dockerfile` for Feishin (Ubuntu 24.04 base, apt-get deps, AppImage extraction, wrapper script) — `containers/feishin/Dockerfile`
- [x] Write `feishin-wrapper` script — `containers/feishin/feishin-wrapper`
- [x] Build arm64 container image — Makefile targets `build-container-feishin` / `save-container-feishin` working
- [ ] Test Wayland passthrough: container → host Weston (manual `podman run`)
- [ ] Test PipeWire audio passthrough: container → host PipeWire
- [ ] Test MPRIS D-Bus: container process visible to host `playerctl`
- [ ] Test GPU (`/dev/dri`) passthrough and rendering
- [ ] Push image to GHCR (deferred — using local-only tags `appliance-feishin:latest` for now)

### Phase 3: bbclass + recipe integration
- [x] Update `app.json` schema: add `image` field, remove `exec` — `feishin/files/app.json` has `"image": "appliance-feishin:latest"`
- [x] Update `appliance-app.bbclass`: generate `podman run` service units from `app.json` (225-line bbclass, full Wayland/PipeWire/D-Bus/DRI passthrough)
- [x] Handle standard mounts (Wayland socket, PipeWire, D-Bus, DRI) in bbclass based on VT number
- [x] Handle custom `mounts`, `devices`, `env`, `podman_args` from `app.json`
- [x] Slim down `feishin_1.13.0.bb`: now only installs tmpfiles.d config + bind mount unit; no AppImage, no RDEPENDS, no INSANE_SKIP
- [x] Remove `feishin-wrapper` from the recipe (lives in container image at `containers/feishin/feishin-wrapper`)
- [ ] Test: build image, boot, verify Feishin launches via container (firmware building; container image load + launch not yet tested on device)

### Phase 4: First-boot container seeding
- [ ] Design seeding mechanism: embed `podman save` tarball in WIC data partition or in rootfs `/usr/share/appliance/images/`
- [ ] Write `appliance-app-seed@.service` template: `podman load -i <tarball>` if image not present
- [ ] Integrate seed tarball creation into the Yocto build (deploy task or post-image script)
- [ ] Test: fresh flash → first boot → container loads → app starts without network

### Phase 5: Update/rollback CLI
- [ ] Implement `appliance app update <name> [version]` (pull, retag :previous, retag :latest, restart)
- [ ] Implement `appliance app rollback <name>` (retag :previous → :latest, restart)
- [ ] Implement `appliance app list` (show running app containers, image versions)
- [ ] Implement `appliance app logs <name>` (`podman logs`)
- [ ] Implement `appliance app exec <name> [cmd...]` (`podman exec`)
- [ ] Implement `appliance app status <name>` (image, uptime, version)
- [ ] Write `docs/apps.md` manpage covering container architecture, update workflow, custom images, airgapped delivery
