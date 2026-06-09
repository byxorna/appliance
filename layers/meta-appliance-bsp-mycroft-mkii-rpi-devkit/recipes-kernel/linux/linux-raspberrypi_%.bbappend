# Mark II SJ201 audio kernel config.
# Enables the TAS5806MD codec (tas5805m), the simple-audio-card machine driver,
# and SPDIF dummy codecs that the sj201 DT overlay's simple-audio-card binds to.
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:mycroft-mkii-rpi-devkit = " file://sj201-audio.cfg"
