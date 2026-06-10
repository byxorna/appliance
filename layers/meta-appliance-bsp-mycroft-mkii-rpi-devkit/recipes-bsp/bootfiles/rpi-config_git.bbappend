# Mycroft Mark II DevKit config.txt additions.
#
# Enables the buses the SJ201 needs (I2S audio, SPI for XMOS firmware upload,
# I2C on i2c-1 for the TAS5806MD amp / XMOS control), the Raspberry Pi DSI
# touchscreen panel (Atmel-MCU backlight + ft5x06 touch, bound by the
# vc4-kms-dsi-7inch overlay regardless of the panel's physical size), and the
# three SJ201 overlays built by sj201-dtoverlays.

do_deploy:append() {
    CONFIG=${DEPLOYDIR}/${BOOTFILES_DIR_NAME}/config.txt

    # I2S audio bus
    grep -q "^dtparam=i2s=on$" $CONFIG || echo "dtparam=i2s=on" >> $CONFIG

    # SPI bus for XMOS firmware upload
    grep -q "^dtparam=spi=on$" $CONFIG || echo "dtparam=spi=on" >> $CONFIG

    # I2C bus (i2c-1) for the TAS5806MD amp and XMOS control
    grep -q "^dtparam=i2c_arm=on$" $CONFIG || echo "dtparam=i2c_arm=on" >> $CONFIG
    grep -q "^dtparam=i2c_arm_baudrate=" $CONFIG || echo "dtparam=i2c_arm_baudrate=100000" >> $CONFIG

    # Raspberry Pi DSI touchscreen panel. The vc4-kms-dsi-7inch overlay binds
    # the panel's Atmel-MCU backlight/power-sequencer (i2c 0x45) and the ft5x06
    # touch controller (i2c 0x38); the "7inch" label is just the overlay name
    # and does not imply the panel's physical diagonal.
    grep -q "^dtoverlay=vc4-kms-dsi-7inch$" $CONFIG || echo "dtoverlay=vc4-kms-dsi-7inch" >> $CONFIG

    # The panel's Atmel MCU + ft5x06 sit on the fe205000.i2c DSI/CSI bus, which
    # is shared between the ARM (Linux) and the VideoCore firmware. When the
    # firmware does display housekeeping on that bus concurrently with Linux,
    # the bus wedges: backlight/touch transfers time out and the display goes
    # dark while DRM DPMS still reports "On". Letting KMS parse EDID itself and
    # keeping the firmware out of display setup avoids that contention.
    # See raspberrypi/linux#5397 and docs/mycroft-mkii-quirks.md.
    grep -q "^disable_fw_kms_setup=" $CONFIG || echo "disable_fw_kms_setup=1" >> $CONFIG

    # SJ201 audio card
    grep -q "^dtoverlay=sj201$" $CONFIG || echo "dtoverlay=sj201" >> $CONFIG

    # SJ201 GPIO buttons
    grep -q "^dtoverlay=sj201-buttons-overlay$" $CONFIG || echo "dtoverlay=sj201-buttons-overlay" >> $CONFIG

    # SJ201 rev10 PWM fan
    grep -q "^dtoverlay=sj201-rev10-pwm-fan-overlay$" $CONFIG || echo "dtoverlay=sj201-rev10-pwm-fan-overlay" >> $CONFIG

    # GPU memory for the DSI display
    grep -q "^gpu_mem=" $CONFIG || echo "gpu_mem=256" >> $CONFIG
}
