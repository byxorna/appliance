SUMMARY = "Appliance input handler (hardware button to PipeWire/D-Bus dispatcher)"
DESCRIPTION = "Configures triggerhappy to map hardware buttons (volume, media, \
mic mute) to PipeWire volume control and D-Bus MPRIS commands. BSP layers \
provide trigger config files that map device-specific key codes to the \
generic helper scripts installed here."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://volume-up \
    file://volume-down \
    file://media-play-pause \
    file://mic-mute-toggle \
    file://triggerhappy-override.conf \
"

S = "${WORKDIR}"

RDEPENDS:${PN} = "triggerhappy wireplumber-tools"

inherit useradd

USERADD_PACKAGES = "${PN}"
USERADD_PARAM:${PN} = "-u 820 -g inputd -G input,pipewire -r -d / -s /usr/sbin/nologin inputd"
GROUPADD_PARAM:${PN} = "-g 820 inputd"

do_install() {
    install -d ${D}${libexecdir}/appliance
    install -m 0755 ${S}/volume-up ${D}${libexecdir}/appliance/volume-up
    install -m 0755 ${S}/volume-down ${D}${libexecdir}/appliance/volume-down
    install -m 0755 ${S}/media-play-pause ${D}${libexecdir}/appliance/media-play-pause
    install -m 0755 ${S}/mic-mute-toggle ${D}${libexecdir}/appliance/mic-mute-toggle

    install -d ${D}${sysconfdir}/triggerhappy/triggers.d

    install -d ${D}${systemd_system_unitdir}/triggerhappy.service.d
    install -m 0644 ${S}/triggerhappy-override.conf \
        ${D}${systemd_system_unitdir}/triggerhappy.service.d/override.conf
}

FILES:${PN} = " \
    ${libexecdir}/appliance/ \
    ${sysconfdir}/triggerhappy/triggers.d/ \
    ${systemd_system_unitdir}/triggerhappy.service.d/ \
"
