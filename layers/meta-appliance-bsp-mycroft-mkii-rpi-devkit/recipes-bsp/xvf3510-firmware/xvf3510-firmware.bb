SUMMARY = "XMOS XVF-3510 DSP firmware and SPI flash tool for the SJ201"
DESCRIPTION = "Installs the proprietary XMOS XVF-3510 DSP firmware image and the \
xvf3510-flash SPI upload tool used by sj201-init at boot. Both the firmware blob \
and the upstream XMOS flash tool are XMOS proprietary ('All rights reserved') and \
are NOT redistributable under an open-source license, so this recipe is gated \
behind LICENSE_FLAGS and the integrator must supply the files locally."
HOMEPAGE = "https://www.xmos.com/"

# Proprietary XMOS firmware/tool. Gate behind explicit acceptance so it never
# ships unless the integrator opts in and has supplied the files.
LICENSE = "Proprietary"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Proprietary;md5=0557f9d92cf58f2ccdd50f62f8ac0b28"
LICENSE_FLAGS = "xmos-xvf3510-firmware"

# The integrator must place the proprietary files alongside this recipe:
#   files/app_xvf3510_int_spi_boot_v4_1_0.bin   (XMOS DSP image)
#   files/xvf3510-flash                          (XMOS SPI upload tool)
# Obtain them from the XMOS registered-user channel; they are not fetched
# automatically because they carry no redistribution license.
SRC_URI = " \
    file://app_xvf3510_int_spi_boot_v4_1_0.bin \
    file://xvf3510-flash \
"

S = "${WORKDIR}"

COMPATIBLE_MACHINE = "^mycroft-mkii-rpi-devkit$"

# The XMOS flash tool is a Python 3 script using spidev/RPi.GPIO; pull those in.
RDEPENDS:${PN} = " \
    python3-core \
    python3-spidev \
"

FW_DIR = "${nonarch_base_libdir}/firmware/xvf3510"

do_install() {
    install -d ${D}${FW_DIR}
    install -m 0644 ${S}/app_xvf3510_int_spi_boot_v4_1_0.bin \
        ${D}${FW_DIR}/app_xvf3510_int_spi_boot_v4_1_0.bin

    install -d ${D}${sbindir}
    install -m 0755 ${S}/xvf3510-flash ${D}${sbindir}/xvf3510-flash
}

FILES:${PN} = " \
    ${FW_DIR}/app_xvf3510_int_spi_boot_v4_1_0.bin \
    ${sbindir}/xvf3510-flash \
"

# The firmware blob is opaque; skip stripping/ELF checks.
INHIBIT_PACKAGE_STRIP = "1"
INSANE_SKIP:${PN} += "arch"
