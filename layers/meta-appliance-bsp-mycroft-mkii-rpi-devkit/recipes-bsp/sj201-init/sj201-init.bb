SUMMARY = "SJ201 audio initialization (TAS5806MD amp + XMOS firmware upload)"
DESCRIPTION = "Initializes the SJ201 daughterboard's TAS5806MD Class-D amplifier \
over I2C at boot and, if the proprietary XMOS firmware/tool are present, uploads \
the XVF-3510 DSP image first. The amp init is a self-contained C tool against \
Linux i2c-dev, so no Python/smbus runtime is needed on the read-only rootfs."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://tas5806-init.c \
    file://sj201-init \
    file://sj201-init.service \
"

S = "${WORKDIR}"

COMPATIBLE_MACHINE = "^mycroft-mkii-rpi-devkit$"

inherit systemd

SYSTEMD_SERVICE:${PN} = "sj201-init.service"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} -o ${B}/tas5806-init ${S}/tas5806-init.c
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/tas5806-init ${D}${bindir}/tas5806-init
    install -m 0755 ${S}/sj201-init ${D}${bindir}/sj201-init

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/sj201-init.service ${D}${systemd_system_unitdir}/sj201-init.service
}

FILES:${PN} = " \
    ${bindir}/tas5806-init \
    ${bindir}/sj201-init \
    ${systemd_system_unitdir}/sj201-init.service \
"
