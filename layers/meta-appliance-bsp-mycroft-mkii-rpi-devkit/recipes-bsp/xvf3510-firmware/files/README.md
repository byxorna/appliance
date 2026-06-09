# XMOS XVF-3510 firmware and flash tool — proprietary, supply locally

The `xvf3510-firmware` recipe is **disabled by default** (gated behind
`LICENSE_FLAGS = "xmos-xvf3510-firmware"`). The two files it installs are XMOS
proprietary ("All rights reserved") and carry **no open-source / redistribution
license**, so they are deliberately **not** vendored in this repository and are
**not** fetched automatically.

To enable XMOS DSP support you must obtain the files from the XMOS
registered-user channel (or the OpenVoiceOS buildroot tree) and place them here:

    files/app_xvf3510_int_spi_boot_v4_1_0.bin   # XMOS XVF-3510 INT SPI-boot image
    files/xvf3510-flash                          # XMOS SPI upload tool (python3)

Then accept the license flag and add the recipe in your build, e.g. in the
variant's `local_conf_header`:

    LICENSE_FLAGS_ACCEPTED:append = " xmos-xvf3510-firmware"
    IMAGE_INSTALL:append = " xvf3510-firmware"

Without these files the image still builds and boots; `sj201-init` detects the
missing firmware/tool and skips the DSP upload, initializing only the TAS5806MD
amplifier. The far-field mic array will be inactive until the firmware is
supplied.

Upstream references:
  - Flash tool: xmos/vocalfusion-rpi-setup (send_image_from_rpi.py)
  - Firmware + tool vendored in: OpenVoiceOS/ovos-buildroot
    (buildroot-external/package/xvf3510/)
