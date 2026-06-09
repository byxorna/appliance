# Mycroft Mark II DevKit config.txt additions.
#
# Enables the buses the SJ201 needs (I2S audio, SPI for XMOS firmware upload,
# I2C for the TAS5806MD amp / XMOS control / GT911 touch), the Waveshare 4.3"
# DSI display, and the three SJ201 overlays built by sj201-dtoverlays.

do_deploy:append() {
    CONFIG=${DEPLOYDIR}/${BOOTFILES_DIR_NAME}/config.txt

    # I2S audio bus
    grep -q "^dtparam=i2s=on$" $CONFIG || echo "dtparam=i2s=on" >> $CONFIG

    # SPI bus for XMOS firmware upload
    grep -q "^dtparam=spi=on$" $CONFIG || echo "dtparam=spi=on" >> $CONFIG

    # I2C bus for TAS5806MD, XMOS control, GT911 touch
    grep -q "^dtparam=i2c_arm=on$" $CONFIG || echo "dtparam=i2c_arm=on" >> $CONFIG
    grep -q "^dtparam=i2c_arm_baudrate=" $CONFIG || echo "dtparam=i2c_arm_baudrate=100000" >> $CONFIG

    # Waveshare 4.3" DSI display + Goodix GT911 touch
    grep -q "^dtoverlay=vc4-kms-dsi-7inch$" $CONFIG || echo "dtoverlay=vc4-kms-dsi-7inch" >> $CONFIG

    # SJ201 audio card
    grep -q "^dtoverlay=sj201$" $CONFIG || echo "dtoverlay=sj201" >> $CONFIG

    # SJ201 GPIO buttons
    grep -q "^dtoverlay=sj201-buttons-overlay$" $CONFIG || echo "dtoverlay=sj201-buttons-overlay" >> $CONFIG

    # SJ201 rev10 PWM fan
    grep -q "^dtoverlay=sj201-rev10-pwm-fan-overlay$" $CONFIG || echo "dtoverlay=sj201-rev10-pwm-fan-overlay" >> $CONFIG

    # GPU memory for the DSI display
    grep -q "^gpu_mem=" $CONFIG || echo "gpu_mem=256" >> $CONFIG
}
