# appliance-app.bbclass — Common infrastructure for appliance kiosk apps
#
# Recipes that inherit this class ship a self-contained app under
# /opt/<name>/ together with a systemd service unit that launches the app
# on the correct Weston VT.
#
# The recipe must provide an app.json in its SRC_URI, for example:
#
#   {
#     "name": "feishin",
#     "display_name": "Feishin",
#     "vt": 2,
#     "exec": "/opt/feishin/feishin --ozone-platform=wayland"
#   }
#
# Required fields:
#   name          — machine-readable identifier (a-z0-9-), used for paths
#   display_name  — human-readable label
#   vt            — Linux VT number where the app's Weston runs
#   exec          — absolute command line to launch the app
#
# What this class does:
#   1. Parses app.json at do_install time
#   2. Installs app.json to /opt/<name>/app.json
#   3. Generates a systemd service unit: appliance-app-<name>.service
#   4. Creates a graphical.target.wants symlink for weston@<vt>.service
#      (ensures the Weston instance the app needs is enabled)
#   5. Sets up /data/apps/<name>/ bind-mount target via tmpfiles.d
#   6. Wires SYSTEMD_SERVICE so the image builder enables the unit
#
# The generated service runs as the unprivileged `kiosk` user with
# WAYLAND_DISPLAY=wayland-<vt> to reach the per-VT compositor socket.

inherit systemd

APPLIANCE_APP_USER ?= "kiosk"
APPLIANCE_APP_UID  ?= "810"

python () {
    import json, os

    src_uri = d.getVar('SRC_URI') or ''
    if 'file://app.json' not in src_uri:
        bb.fatal('appliance-app.bbclass: SRC_URI must include file://app.json')

    # Parse app.json at parse time so SYSTEMD_SERVICE and FILES are set
    # early enough for the systemd bbclass to create enable symlinks.
    # file:// URIs for local files resolve to the recipe's FILESDIR search
    # path, so we can find app.json in the recipe's files/ directory.
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

# Shell helper: read a key from the JSON manifest.
# Usage: app_json_get <file> <key>
# Requires python3 on the build host (always present in Yocto).
appliance_app_json_get() {
    python3 -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$1" "$2"
}

do_install:append() {
    local manifest="${WORKDIR}/app.json"
    if [ ! -f "$manifest" ]; then
        bbfatal "appliance-app.bbclass: app.json not found in WORKDIR"
    fi

    local app_name=$(appliance_app_json_get "$manifest" name)
    local app_display=$(appliance_app_json_get "$manifest" display_name)
    local app_vt=$(appliance_app_json_get "$manifest" vt)
    local app_exec=$(appliance_app_json_get "$manifest" exec)

    if [ -z "$app_name" ] || [ -z "$app_vt" ] || [ -z "$app_exec" ]; then
        bbfatal "appliance-app.bbclass: app.json must have name, vt, and exec"
    fi

    # --- Install the manifest -------------------------------------------------
    install -d ${D}/opt/${app_name}
    install -m 0644 "$manifest" ${D}/opt/${app_name}/app.json

    # --- Generate the systemd service unit ------------------------------------
    local svc="appliance-app-${app_name}.service"
    install -d ${D}${systemd_system_unitdir}

    cat > ${D}${systemd_system_unitdir}/${svc} <<EOF
[Unit]
Description=${app_display} (appliance app on VT ${app_vt})
Documentation=file:///opt/${app_name}/app.json

Requires=weston@${app_vt}.service
After=weston@${app_vt}.service

[Service]
Type=simple
ExecStart=${app_exec}

User=${APPLIANCE_APP_USER}
Group=${APPLIANCE_APP_USER}

# Connect to the per-VT Weston compositor socket.
Environment=WAYLAND_DISPLAY=wayland-${app_vt}
Environment=XDG_RUNTIME_DIR=/run/user/${APPLIANCE_APP_UID}
Environment=GDK_BACKEND=wayland

# Prevent the app from accessing input devices directly
# (it should go through Wayland).
SupplementaryGroups=wayland audio video

Restart=on-failure
RestartSec=3s

[Install]
WantedBy=graphical.target
EOF

    # --- Ensure the Weston VT instance is also enabled ------------------------
    # The weston-init bbappend enables weston@2 by default.  Additional VTs
    # need their own .wants symlink.  Creating it here is idempotent —
    # if weston@2 already has a symlink, another one is harmless.
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

# All app recipes depend on the kiosk user infrastructure and weston
RDEPENDS:${PN}:append = " kiosk-user"
