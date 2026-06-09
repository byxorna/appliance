# Mycroft Mark II DevKit Quirks

Collected workarounds needed to run Yocto **scarthgap (5.0)** on the
Mycroft Mark II DevKit (Raspberry Pi 4B + **SJ201** daughterboard) with
**meta-raspberrypi** (scarthgap branch).

All fixes live in `layers/meta-appliance-bsp-mycroft-mkii-rpi-devkit/`.

`TODO` marks an unverified assumption to fill in as Phases 2-4 land.

---

## SJ201 daughterboard overview

The SJ201 carries the audio and front-panel hardware:

| Component | Role | TODO |
| --- | --- | --- |
| XMOS XVF-3510 | Far-field voice DSP / mic array front end, needs firmware upload at boot | Confirm interface (SPI/I2C) and firmware blob |
| TAS5806MD | I2S Class-D amplifier, needs I2C init to un-mute | Confirm I2C address and register sequence |
| Waveshare 4.3" DSI display | Front panel | Confirm panel timing / overlay |
| GT911 touch | Capacitive touch over I2C | Confirm bus and address |
| GPIO buttons / LEDs | Front-panel controls | Enumerate GPIOs |

Buses enabled in the machine conf (`mycroft-mkii-rpi-devkit.conf`) are
I2C, SPI, and UART. `i2c-dev` is autoloaded so userspace init tooling can
reach the bus.

---

## 1. Custom fstab for 5-partition A/B layout

RAUC A/B layout (p1=boot FAT, p2=rootfs_A, p3=rootfs_B, p5=/home,
p6=/data) on mmcblk0 (SD card).

TODO: confirm whether a Mark II-specific fstab override is needed or
whether the `meta-rauc-raspberrypi` default suffices. The WKS lives at
`wic/appliance-dual-rootfs.wks.in`; an fstab override would go under
`recipes-core/base-files/`.

---

## 2. SJ201 DT overlays not deployed to boot partition

Out-of-tree overlays built by the `sj201-dtoverlays` recipe (Phase 2) land
in `DEPLOYDIR` but are not picked up by `IMAGE_BOOT_FILES` unless added
explicitly:

```bitbake
IMAGE_BOOT_FILES:append = " <overlay>.dtbo;overlays/<overlay>.dtbo"
```

TODO: enumerate the exact overlays (display, TAS5806, XMOS, touch) and the
boot symptom seen before they land.

---

## 3. TAS5806MD amplifier init

The TAS5806MD needs an I2C register init sequence to leave the mute/standby
state after power-on. Without it the card enumerates but stays silent.

The `sj201-init` service (Phase 4) runs the sequence ordered before audio
comes up. TODO: document the register sequence and I2C address.

---

## 4. XMOS XVF-3510 firmware upload

The XVF-3510 boots without functional firmware, so the DSP image must be
uploaded at runtime before the mic array works.

The `xvf3510-firmware` recipe (Phase 4) ships the blob and `sj201-init`
uploads it during boot. TODO: confirm transport (SPI vs I2C), tooling, and
firmware licensing.

---

## 5. No framebuffer console on the DSI display

meta-raspberrypi's default `cmdline.txt` only has
`console=serial0,115200`, so without `console=tty1` the kernel never
attaches `fbcon` and the screen stays blank. `console=tty1` is appended to
the kernel command line in layer.conf.

---

Yocto-version-specific workarounds shared with every BSP are documented in
[scarthgap-quirks.md](scarthgap-quirks.md).
