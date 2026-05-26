# meta-raspberrypi scarthgap lists DT overlays that don't exist in the 6.1.y
# kernel branch pinned by meta-seeed-cm4 (PREFERRED_VERSION = "6.1.%").
# These are Pi 5 or post-6.1 additions. Remove them for our machine.
KERNEL_DEVICETREE:remove:seeed-reterminal = " \
    overlays/vc4-kms-dsi-ili9881-7inch.dtbo \
    overlays/vc4-kms-dsi-ili9881-5inch.dtbo \
    overlays/w1-gpio-pi5.dtbo \
    overlays/bcm2712d0.dtbo \
"
