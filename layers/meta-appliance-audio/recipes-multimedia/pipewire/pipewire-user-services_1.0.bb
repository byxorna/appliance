SUMMARY = "Enable PipeWire audio stack as systemd user services"
DESCRIPTION = "Installs default.target.wants symlinks so PipeWire, WirePlumber \
and the PulseAudio compatibility daemon start as systemd user services in the \
weston compositor session (UID 800)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

RDEPENDS:${PN} = "pipewire wireplumber pipewire-pulse"

ALLOW_EMPTY:${PN} = "1"

do_install() {
    install -d ${D}${systemd_user_unitdir}/default.target.wants
    ln -sf ../pipewire.service ${D}${systemd_user_unitdir}/default.target.wants/pipewire.service
    ln -sf ../wireplumber.service ${D}${systemd_user_unitdir}/default.target.wants/wireplumber.service
    ln -sf ../pipewire-pulse.service ${D}${systemd_user_unitdir}/default.target.wants/pipewire-pulse.service
    ln -sf ../pipewire-pulse.socket ${D}${systemd_user_unitdir}/default.target.wants/pipewire-pulse.socket
}

FILES:${PN} = "${systemd_user_unitdir}/default.target.wants"
