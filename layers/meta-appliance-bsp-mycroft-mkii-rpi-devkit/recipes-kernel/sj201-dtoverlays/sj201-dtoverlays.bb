SUMMARY = "SJ201 device tree overlays for the Mycroft Mark II DevKit"
DESCRIPTION = "Compiles the SJ201 daughterboard DT overlays (audio card, GPIO \
buttons, rev10 PWM fan) from the OpenVoiceOS VocalFusionDriver sources and \
deploys them to the boot partition's overlays/ directory."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://sj201.dts \
    file://sj201-buttons-overlay.dts \
    file://sj201-rev10-pwm-fan-overlay.dts \
"

DEPENDS = "dtc-native"

# These overlays are self-contained (compatible = "brcm,bcm2835", no kernel
# header includes), so a plain dtc invocation suffices — no kernel source tree.
COMPATIBLE_MACHINE = "^mycroft-mkii-rpi-devkit$"
PACKAGE_ARCH = "${MACHINE_ARCH}"

S = "${WORKDIR}"
B = "${WORKDIR}/build"

OVERLAYS = "sj201 sj201-buttons-overlay sj201-rev10-pwm-fan-overlay"

inherit deploy

do_compile() {
    mkdir -p ${B}
    for ovl in ${OVERLAYS}; do
        # -@ adds the __symbols__ node required for overlays;
        # -H epapr matches the format the RPi firmware expects.
        dtc -@ -H epapr -I dts -O dtb -Wno-unit_address_vs_reg \
            -o ${B}/${ovl}.dtbo ${S}/${ovl}.dts
    done
}

do_deploy() {
    install -d ${DEPLOYDIR}
    for ovl in ${OVERLAYS}; do
        install -m 0644 ${B}/${ovl}.dtbo ${DEPLOYDIR}/${ovl}.dtbo
    done
}
addtask deploy after do_compile before do_build
