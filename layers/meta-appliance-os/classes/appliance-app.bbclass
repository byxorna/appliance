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

# The Weston compositor user owns the Wayland socket, PipeWire socket,
# and D-Bus session bus under /run/user/<compositor_uid>/.  The container
# maps these host-side paths into the app user's runtime dir inside the
# container so the app process (running as APPLIANCE_APP_UID) can connect.
APPLIANCE_COMPOSITOR_UID ?= "800"

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
    files += ' /opt/%s/' % name
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
# Usage: appliance_app_podman_cmd <app.json> <app_uid> <compositor_uid>
appliance_app_podman_cmd() {
    python3 - "$1" "$2" "$3" <<'PYEOF'
import json, sys

manifest_path = sys.argv[1]
uid = sys.argv[2]
compositor_uid = sys.argv[3]

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
args += ['--security-opt', 'label=disable']
args += ['--cgroupns', 'host']

# GPU devices (default: /dev/dri)
devices = app.get('devices', ['/dev/dri'])
for dev in devices:
    args += ['--device', dev]

# Wayland socket — host path is under the compositor user (UID compositor_uid),
# mapped into the container at the app user's XDG_RUNTIME_DIR (UID uid).
args += ['-v', '/run/user/%s/wayland-%s:/run/user/%s/wayland-%s' % (compositor_uid, vt, uid, vt)]
args += ['-e', 'WAYLAND_DISPLAY=wayland-%s' % vt]
args += ['-e', 'XDG_RUNTIME_DIR=/run/user/%s' % uid]
args += ['-e', 'GDK_BACKEND=wayland']

# PipeWire audio — runs in the compositor's user session.
# ExecStartPre touches a placeholder if the socket is missing so podman
# doesn't refuse to start; the app simply gets no audio until PipeWire runs.
args += ['-v', '/run/user/%s/pipewire-0:/run/user/%s/pipewire-0' % (compositor_uid, uid)]

# D-Bus — system bus is global; session bus is from the compositor's session
args += ['-v', '/run/dbus/system_bus_socket:/run/dbus/system_bus_socket']
args += ['-v', '/run/user/%s/bus:/run/user/%s/bus' % (compositor_uid, uid)]
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
    local container_name="appliance-app-${app_name}"

    # --- Install the manifest -------------------------------------------------
    install -d ${D}/opt/${app_name}
    install -m 0644 "$manifest" ${D}/opt/${app_name}/app.json

    # --- Build the podman run command line ------------------------------------
    local raw_output
    raw_output=$(appliance_app_podman_cmd "$manifest" "$uid" "$compositor_uid")

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
Documentation=file:///opt/${app_name}/app.json

Requires=weston@${app_vt}.service
Wants=systemd-tmpfiles-setup.service
After=weston@${app_vt}.service systemd-tmpfiles-setup.service

[Service]
Type=simple
Delegate=yes

$(echo "$mount_section" | while IFS= read -r mp; do [ -n "$mp" ] && echo "ExecStartPre=/bin/sh -c 'mkdir -p ${mp} && chown ${uid}:${uid} ${mp}'"; done)
ExecStartPre=-/bin/sh -c '[ -e /run/user/${compositor_uid}/pipewire-0 ] || touch /run/user/${compositor_uid}/pipewire-0'

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
