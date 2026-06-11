SUMMARY = "Enable PipeWire audio stack as systemd user services"
DESCRIPTION = "Installs default.target.wants symlinks so PipeWire, WirePlumber \
and the PulseAudio compatibility daemon start as systemd user services in the \
weston compositor session (UID 800)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/pipewire-user-services:"

SRC_URI = " \
    file://10-socket-permissions.conf \
    file://50-default-volume.conf \
"

inherit systemd

RDEPENDS:${PN} = "pipewire wireplumber pipewire-pulse"

ALLOW_EMPTY:${PN} = "1"

do_install() {
    install -d ${D}${systemd_user_unitdir}/default.target.wants
    ln -sf ../pipewire.service ${D}${systemd_user_unitdir}/default.target.wants/pipewire.service
    ln -sf ../wireplumber.service ${D}${systemd_user_unitdir}/default.target.wants/wireplumber.service
    ln -sf ../pipewire-pulse.service ${D}${systemd_user_unitdir}/default.target.wants/pipewire-pulse.service
    ln -sf ../pipewire-pulse.socket ${D}${systemd_user_unitdir}/default.target.wants/pipewire-pulse.socket

    install -d ${D}${sysconfdir}/pipewire/pipewire.conf.d
    install -m 0644 ${WORKDIR}/10-socket-permissions.conf \
        ${D}${sysconfdir}/pipewire/pipewire.conf.d/10-socket-permissions.conf

    install -d ${D}${sysconfdir}/wireplumber/wireplumber.conf.d
    install -m 0644 ${WORKDIR}/50-default-volume.conf \
        ${D}${sysconfdir}/wireplumber/wireplumber.conf.d/50-default-volume.conf
}

FILES:${PN} = " \
    ${systemd_user_unitdir}/default.target.wants \
    ${sysconfdir}/pipewire/pipewire.conf.d/ \
    ${sysconfdir}/wireplumber/wireplumber.conf.d/ \
"
