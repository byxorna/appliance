SUMMARY = "Feishin music player (Electron, repackaged from upstream AppImage)"
DESCRIPTION = "Feishin is a music player frontend for Navidrome and Jellyfin. \
This recipe repackages the upstream arm64 AppImage release for use as a \
native Wayland app under the appliance kiosk compositor."
HOMEPAGE = "https://github.com/jeffvli/feishin"

LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-3.0-only;md5=c84c1a1bfc0863b1019ec3d5bcf4f1ca"

inherit appliance-app

SRC_URI = " \
    https://github.com/jeffvli/feishin/releases/download/v${PV}/Feishin-linux-arm64.AppImage;name=appimage \
    file://feishin-wrapper \
    file://app.json \
    file://feishin-config.conf \
    file://home-kiosk-.config-feishin.mount \
"
SRC_URI[appimage.sha256sum] = "3cacc03ed06ba08c06936f2ef3d5753ae9e27a34777a5b5a221f83735a048e70"

# The AppImage bundles its own Electron/Chromium and native libraries.
# Skip Yocto's QA checks that complain about bundled shared libs,
# pre-stripped binaries, and rpaths inside /opt.
INSANE_SKIP:${PN} = " \
    already-stripped \
    file-rdeps \
    dev-so \
    libdir \
    ldflags \
    useless-rpaths \
    textrel \
"

# Don't try to split debug symbols or strip the bundled binaries — they
# ship pre-stripped and the debugger won't have sources anyway.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"

# AppImage contents are all aarch64 binaries; restrict to that arch.
COMPATIBLE_HOST = "aarch64.*-linux"

do_install() {
    local appimage="${WORKDIR}/Feishin-linux-arm64.AppImage"

    # AppImages are an ELF stub prepended to a squashfs filesystem.
    # We can't run --appimage-extract because the AppImage is aarch64
    # and the build host is typically x86_64.  Instead, find the
    # squashfs offset and extract it directly with unsquashfs.
    local offset=$(grep -aobP 'hsqs' "$appimage" | head -1 | cut -d: -f1)
    if [ -z "$offset" ]; then
        bbfatal "Could not find squashfs magic in AppImage"
    fi

    dd if="$appimage" of="${WORKDIR}/feishin.squashfs" bs=1 skip="$offset"
    unsquashfs -d ${WORKDIR}/squashfs-root ${WORKDIR}/feishin.squashfs

    # Install the extracted tree to /opt/feishin/
    install -d ${D}/opt/feishin
    cp -a ${WORKDIR}/squashfs-root/* ${D}/opt/feishin/

    # Install our wrapper script
    install -m 0755 ${WORKDIR}/feishin-wrapper ${D}/opt/feishin/feishin-wrapper

    # Persistent config: tmpfiles.d creates the mount point, systemd .mount
    # unit bind-mounts /data/apps/feishin/ over it.
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/feishin-config.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/feishin-config.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/home-kiosk-.config-feishin.mount \
        ${D}${systemd_system_unitdir}/home-kiosk-.config-feishin.mount
}

DEPENDS += "squashfs-tools-native"

# Runtime dependencies: Wayland/GL libs the bundled Electron needs from
# the system, plus PipeWire/ALSA for audio output.
# The AppImage bundles its own X11/Xwayland client libs (libX11, libXfixes,
# etc.) so we do NOT pull system X11 packages — our distro has no x11
# feature and those recipes are unbuildable.
RDEPENDS:${PN} += " \
    wayland \
    libxkbcommon \
    mesa \
    libdrm \
    pipewire \
    wireplumber \
    alsa-lib \
    nss \
    nspr \
    at-spi2-core \
    pango \
    cairo \
    gdk-pixbuf \
    glib-2.0 \
    dbus \
    playerctl \
"

SYSTEMD_SERVICE:${PN}:append = " home-kiosk-.config-feishin.mount"

FILES:${PN} += " \
    ${nonarch_libdir}/tmpfiles.d/feishin-config.conf \
    ${systemd_system_unitdir}/home-kiosk-.config-feishin.mount \
"
