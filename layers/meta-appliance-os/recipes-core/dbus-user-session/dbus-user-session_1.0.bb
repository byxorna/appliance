SUMMARY = "Enable the D-Bus user session bus as a systemd user service"
DESCRIPTION = "Installs a default.target.wants symlink so dbus.socket starts in \
the weston compositor's systemd --user session (UID 800). The upstream dbus \
recipe enables the user bus via sockets.target.wants, but this minimal user \
session does not reliably reach sockets.target. Mirroring the PipeWire pattern \
of an explicit default.target.wants symlink guarantees the session bus is up so \
containerized apps (e.g. Feishin MPRIS) can reach DBUS_SESSION_BUS_ADDRESS."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

RDEPENDS:${PN} = "dbus"

ALLOW_EMPTY:${PN} = "1"

do_install() {
    install -d ${D}${systemd_user_unitdir}/default.target.wants
    ln -sf ../dbus.socket ${D}${systemd_user_unitdir}/default.target.wants/dbus.socket
}

FILES:${PN} = "${systemd_user_unitdir}/default.target.wants"
