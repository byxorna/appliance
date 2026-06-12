# appliance-app.bbclass — Common infrastructure for appliance kiosk apps
#
# Recipes that inherit this class ship a containerized app that runs under
# podman on a dedicated Weston VT.
#
# The recipe must provide an app.json in its SRC_URI, for example:
#
#   {
#     "name": "feishin",
#     "display_name": "Feishin",
#     "vt": 2,
#     "image": "ghcr.io/byxorna/appliance-feishin:latest"
#   }
#
# Required fields:
#   name          — machine-readable identifier (a-z0-9-), used for paths
#   display_name  — human-readable label
#   vt            — Linux VT number where the app's Weston runs
#   image         — OCI container image reference
#
# Optional fields:
#   mounts        — array of extra bind mount strings ("src:dst")
#   devices       — array of extra device paths (default: /dev/dri)
#   env           — object of extra environment variables
#   podman_args   — array of extra raw podman run flags
#
# What this class does:
#   1. Parses app.json at parse time for SYSTEMD_SERVICE / FILES
#   2. Installs app.json to /opt/<name>/app.json
#   3. Generates a systemd service unit: appliance-app-<name>.service
#      that launches the container via podman with Wayland, PipeWire,
#      and D-Bus passthrough
#   4. Creates a graphical.target.wants symlink for weston@<vt>.service
#   5. Sets up /data/apps/<name>/ via tmpfiles.d
#   6. Wires SYSTEMD_SERVICE so the image builder enables the unit

inherit systemd

APPLIANCE_APP_USER ?= "kiosk"
APPLIANCE_APP_UID  ?= "810"

# The Weston compositor user owns the Wayland socket under
# /run/user/<compositor_uid>/.  The container maps this into the app
# user's XDG_RUNTIME_DIR so the app process can connect to Wayland.
APPLIANCE_COMPOSITOR_UID ?= "800"

# The session user owns PipeWire, PulseAudio, D-Bus, and WirePlumber
# under /run/user/<session_uid>/.  With the kiosk-session split this
# equals APPLIANCE_APP_UID — no cross-UID socket mapping needed for
# audio or D-Bus.
APPLIANCE_SESSION_UID ?= "810"

# Supplementary groups the container process needs.  --group-add keep-groups
# does not work with rootful podman + --userns keep-id, so groups must be
# added explicitly by GID.  Defaults cover the wayland compositor socket,
# audio devices, and video/GPU devices.
APPLIANCE_APP_GROUPS ?= "801 29 44"

python () {
    import json, os

    src_uri = d.getVar('SRC_URI') or ''
    if 'file://app.json' not in src_uri:
        bb.fatal('appliance-app.bbclass: SRC_URI must include file://app.json')

    # Parse app.json at parse time so SYSTEMD_SERVICE and FILES are set
    # early enough for the systemd bbclass to create enable symlinks.
    filesdir = d.getVar('FILE_DIRNAME')
    manifest = None
    for subdir in ['files', '.', d.getVar('BPN'), '%s-%s' % (d.getVar('BPN'), d.getVar('PV'))]:
        candidate = os.path.join(filesdir, subdir, 'app.json')
        if os.path.exists(candidate):
            manifest = candidate
            break

    if not manifest:
        bb.fatal('appliance-app.bbclass: app.json not found in recipe file search path')

    with open(manifest) as f:
        app = json.load(f)

    name = app.get('name', '')
    vt = str(app.get('vt', ''))
    if not name or not vt:
        bb.fatal('appliance-app.bbclass: app.json must have name and vt fields')

    if 'image' not in app:
        bb.fatal('appliance-app.bbclass: app.json must have an image field')

    svc = 'appliance-app-%s.service' % name
    pn = d.getVar('PN')
    unitdir = d.getVar('systemd_system_unitdir')
    libdir = d.getVar('nonarch_libdir')

    # Set SYSTEMD_SERVICE early so the systemd class creates enable symlinks
    cur = d.getVar('SYSTEMD_SERVICE:%s' % pn) or ''
    if svc not in cur:
        d.setVar('SYSTEMD_SERVICE:%s' % pn, (cur + ' ' + svc).strip())

    # Set FILES early so packaging finds all generated outputs
    files = (d.getVar('FILES:%s' % pn) or '')
    files += ' /opt/%s' % name
    files += ' %s/%s' % (unitdir, svc)
    files += ' %s/graphical.target.wants/weston@%s.service' % (unitdir, vt)
    files += ' %s/tmpfiles.d/appliance-app-%s.conf' % (libdir, name)
    d.setVar('FILES:%s' % pn, files)
}

# Shell helper: generate the podman run command and mount-source list from
# app.json.  Outputs two sections separated by a "---" line:
#   Section 1: host-side mount sources under /data/ that must be pre-created
#              (one path per line, may be empty)
#   Section 2: the podman run command (backslash-continued)
#
# Usage: appliance_app_podman_cmd <app.json> <app_uid> <compositor_uid> <session_uid> <groups>
appliance_app_podman_cmd() {
    python3 - "$1" "$2" "$3" "$4" "$5" <<'PYEOF'
import json, sys

manifest_path = sys.argv[1]
uid = sys.argv[2]
compositor_uid = sys.argv[3]
session_uid = sys.argv[4]
supplementary_groups = sys.argv[5].split()

with open(manifest_path) as f:
    app = json.load(f)

name = app['name']
vt = str(app['vt'])
image = app['image']
container_name = 'appliance-app-%s' % name

args = ['/usr/bin/podman', 'run']
args += ['--name', container_name]
args += ['--replace', '--rm']
args += ['--pull', 'missing']
args += ['--network', 'host']
args += ['--userns', 'keep-id:uid=%s,gid=%s' % (uid, uid)]
for gid in supplementary_groups:
    args += ['--group-add', gid]
args += ['--security-opt', 'label=disable']

# Work around podman bug: with rootful --userns keep-id + --network host,
# podman omits IsKeepID() from its isNewUserns check, causing it to generate
# a fresh sysfs mount instead of a bind mount. The kernel denies the fresh
# mount because the container's user namespace doesn't own the host network
# namespace. Explicitly bind-mounting /sys bypasses the broken OCI spec.
# Upstream: https://github.com/containers/podman/issues/21680
args += ['-v', '/sys:/sys:ro']

# GPU devices (default: /dev/dri)
devices = app.get('devices', ['/dev/dri'])
for dev in devices:
    args += ['--device', dev]

# Bind-mount the session user's runtime dir. PipeWire, PulseAudio, and
# D-Bus sockets all live here (owned by kiosk via kiosk-session.service).
# Since session_uid == uid, no cross-UID mapping is needed for audio/D-Bus.
args += ['-v', '/run/user/%s:/run/user/%s' % (session_uid, uid)]

# Wayland socket lives in the compositor's runtime dir (different UID).
# Bind-mount it on top of the session runtime dir mount so the app sees
# it at /run/user/<uid>/wayland-<vt>.
args += ['-v', '/run/user/%s/wayland-%s:/run/user/%s/wayland-%s' % (compositor_uid, vt, uid, vt)]
args += ['-e', 'WAYLAND_DISPLAY=wayland-%s' % vt]
args += ['-e', 'XDG_RUNTIME_DIR=/run/user/%s' % uid]
args += ['-e', 'GDK_BACKEND=wayland']

# Writable home directory for the container user.  A tmpfs avoids baking a
# host-specific UID into the container image.  Electron needs $HOME/.config
# for userData and Mesa needs $HOME/.cache for shader cache.  Persistent
# app config is bind-mounted over the tmpfs from /data/apps/<name>/.
args += ['--mount', 'type=tmpfs,dst=/home/kiosk,U=true']
args += ['-e', 'HOME=/home/kiosk']

# PulseAudio compatibility — Electron/Chromium prefers the PulseAudio
# backend.  libpulse's "secure directory" ownership check on
# $XDG_RUNTIME_DIR/pulse can fail depending on mount layering; pointing
# PULSE_SERVER directly at the socket bypasses that lookup.
args += ['-e', 'PULSE_SERVER=unix:/run/user/%s/pulse/native' % uid]

# D-Bus — system bus is global; session bus is in the session runtime dir
args += ['-v', '/run/dbus/system_bus_socket:/run/dbus/system_bus_socket']
args += ['-e', 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%s/bus' % uid]

# Persistent app data
args += ['-v', '/data/apps/%s:/data/apps/%s' % (name, name)]

# Extra mounts from app.json
for mnt in app.get('mounts', []):
    args += ['-v', mnt]

# Extra environment from app.json
for k, v in app.get('env', {}).items():
    args += ['-e', '%s=%s' % (k, v)]

# Extra raw podman args
for arg in app.get('podman_args', []):
    args.append(arg)

# Image reference
args.append(image)

# --- Section 1: mount sources to pre-create ---
# Collect host paths under /data/ from standard and extra mounts that the
# service's ExecStartPre should mkdir before podman runs.
precreate = ['/data/apps/%s' % name]
for mnt in app.get('mounts', []):
    src = mnt.split(':')[0]
    if src.startswith('/data/'):
        precreate.append(src)

for p in precreate:
    print(p)

print('---')

# --- Section 2: podman command ---
print(' \\\n    '.join(args))
PYEOF
}

do_install:append() {
    local manifest="${WORKDIR}/app.json"
    if [ ! -f "$manifest" ]; then
        bbfatal "appliance-app.bbclass: app.json not found in WORKDIR"
    fi

    local app_name=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['name'])" "$manifest")
    local app_display=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['display_name'])" "$manifest")
    local app_vt=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['vt'])" "$manifest")
    local app_image=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['image'])" "$manifest")

    if [ -z "$app_name" ] || [ -z "$app_vt" ] || [ -z "$app_image" ]; then
        bbfatal "appliance-app.bbclass: app.json must have name, vt, and image"
    fi

    local uid="${APPLIANCE_APP_UID}"
    local compositor_uid="${APPLIANCE_COMPOSITOR_UID}"
    local session_uid="${APPLIANCE_SESSION_UID}"
    local container_name="appliance-app-${app_name}"

    install -d ${D}/opt/${app_name}

    # --- Build the podman run command line ------------------------------------
    local raw_output
    raw_output=$(appliance_app_podman_cmd "$manifest" "$uid" "$compositor_uid" "$session_uid" "${APPLIANCE_APP_GROUPS}")

    local mount_section=$(echo "$raw_output" | sed '/^---$/,$d')
    local podman_cmd=$(echo "$raw_output" | sed '1,/^---$/d')

    # Build ExecStartPre lines to create mount-source directories
    local precmds=""
    if [ -n "$mount_section" ]; then
        echo "$mount_section" | while IFS= read -r mp; do
            [ -n "$mp" ] || continue
            precmds="${precmds}ExecStartPre=/bin/sh -c 'mkdir -p ${mp} && chown ${uid}:${uid} ${mp}'
"
        done
    fi

    # --- Generate the systemd service unit ------------------------------------
    local svc="appliance-app-${app_name}.service"
    install -d ${D}${systemd_system_unitdir}

    cat > ${D}${systemd_system_unitdir}/${svc} <<SVCEOF
[Unit]
Description=${app_display} (appliance app on VT ${app_vt})

Requires=weston@${app_vt}.service kiosk-session.service
After=weston@${app_vt}.service kiosk-session.service systemd-tmpfiles-setup.service

[Service]
Type=simple

$(echo "$mount_section" | while IFS= read -r mp; do [ -n "$mp" ] && echo "ExecStartPre=/bin/sh -c 'mkdir -p ${mp} && chown ${uid}:${uid} ${mp}'"; done)
ExecStartPre=-/bin/sh -c '[ -e /run/user/${session_uid}/pipewire-0 ] || touch /run/user/${session_uid}/pipewire-0'
ExecStartPre=-/bin/sh -c 'mkdir -p /run/user/${session_uid}/pulse; [ -e /run/user/${session_uid}/pulse/native ] || touch /run/user/${session_uid}/pulse/native'

ExecStart=${podman_cmd}
ExecStop=/usr/bin/podman stop -t 10 ${container_name}

Restart=on-failure
RestartSec=3s

[Install]
WantedBy=graphical.target
SVCEOF

    # --- Ensure the Weston VT instance is also enabled ------------------------
    install -d ${D}${systemd_system_unitdir}/graphical.target.wants
    ln -sf ../weston@.service \
        ${D}${systemd_system_unitdir}/graphical.target.wants/weston@${app_vt}.service

    # --- tmpfiles.d: create persistent data dir on /data ----------------------
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    cat > ${D}${nonarch_libdir}/tmpfiles.d/appliance-app-${app_name}.conf <<EOF
# Persistent data directory for ${app_display}
d /data/apps/${app_name} 0750 ${APPLIANCE_APP_USER} ${APPLIANCE_APP_USER} -
EOF
}

# All app recipes depend on the kiosk user infrastructure
RDEPENDS:${PN}:append = " kiosk-user"
