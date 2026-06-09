SUMMARY = "XMOS VocalFusion soundcard out-of-tree kernel module"
DESCRIPTION = "Platform driver matching the sj201 device tree overlay's \
vocalfusion-soundcard node. Sets the XMOS MCLK (GPCLK0) rate and pulses the \
power/reset GPIOs at probe so the SJ201 audio path comes up. Vendored from \
OpenVoiceOS/VocalFusionDriver and adapted for the Linux 6.6 platform_driver API."
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit module

SRC_URI = " \
    file://Makefile \
    file://vocalfusion-soundcard.c \
"

S = "${WORKDIR}"

COMPATIBLE_MACHINE = "^mycroft-mkii-rpi-devkit$"

# Autoload so the SJ201 audio path comes up without manual modprobe.
KERNEL_MODULE_AUTOLOAD += "vocalfusion-soundcard"

RPROVIDES:${PN} += "kernel-module-vocalfusion-soundcard"
