SUMMARY = "Mycroft Mark II DevKit runtime configuration"
DESCRIPTION = "Installs SJ201 ALSA card-ordering rules (modprobe.d) so the \
SJ201 sound card is the default audio device on the Mark II DevKit."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://sj201-alsa.conf"

S = "${WORKDIR}"

COMPATIBLE_MACHINE = "^mycroft-mkii-rpi-devkit$"

inherit allarch

do_install() {
    install -d ${D}${sysconfdir}/modprobe.d
    install -m 0644 ${S}/sj201-alsa.conf ${D}${sysconfdir}/modprobe.d/sj201-alsa.conf
}

FILES:${PN} = "${sysconfdir}/modprobe.d/sj201-alsa.conf"
