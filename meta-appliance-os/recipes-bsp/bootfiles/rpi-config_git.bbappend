# Appliance-specific config.txt additions beyond the upstream reTerminal BSP.
# The base reTerminal overlays (reTerminal, i2c3, i2c_vc, vc4-kms-v3d-pi4,
# dwc2, uart, spi) are handled by meta-seeed-cm4's bbappend since we now use
# MACHINE = "seeed-reterminal" directly.

do_deploy:append() {
    CONFIG=${DEPLOYDIR}/${BOOTFILES_DIR_NAME}/config.txt

    # I2S audio (WM8960 codec)
    grep -q "^dtparam=i2s=on$" $CONFIG || echo "dtparam=i2s=on" >> $CONFIG

    # IR receiver on GPIO 24
    grep -q "^dtoverlay=gpio-ir,gpio_pin=24$" $CONFIG || echo "dtoverlay=gpio-ir,gpio_pin=24" >> $CONFIG
}
