# Mycroft Mark II DevKit Quirks

Collected workarounds needed to run Yocto **scarthgap (5.0)** on the
Mycroft Mark II DevKit (Raspberry Pi 4B + **SJ201** daughterboard) with
**meta-raspberrypi** (scarthgap branch).

All fixes live in `layers/meta-appliance-bsp-mycroft-mkii-rpi-devkit/`.

Hardware bring-up has been validated on an **SJ201 R10** DevKit unit
(boot, display, touch, buttons, fan, audio playback all confirmed). The
LED ring and XMOS mic array remain unimplemented.

---

## Board overview

The Mark II DevKit is a **stock Raspberry Pi 4B** (`raspberrypi4-64`) — it
has **no eMMC**; the OS lives on the **microSD card**. Flashing is a plain
`bzcat … .wic.bz2 | dd` to the SD card; there is no `rpiboot` / boot-switch
dance (that is CM4-only). Boot device selection is governed by the Pi 4
EEPROM `BOOT_ORDER`, independent of the image (`rpi-eeprom-config --edit`).

The SJ201 daughterboard carries the audio and front-panel hardware:

| Component | Role | Status |
| --- | --- | --- |
| XMOS XVF-3510 | Far-field voice DSP / mic array; SPI firmware upload at boot | Gated proprietary blob, not implemented |
| TAS5806MD | I2S Class-D amplifier, I2C addr `0x2f` on bus 1, needs init to un-mute | ✅ `sj201-init` |
| Waveshare 4.3" DSI display | Front panel (`vc4-kms-dsi-7inch`) | ✅ weston |
| ft5x06 touch | Capacitive touch over I2C (`10-0038`) | ✅ enumerated |
| GPIO buttons | VOLUMEUP/DOWN (22/23), VOICECOMMAND (24, wakeup), MICMUTE (25) | ✅ gpio-keys |
| WS2812B LED ring | 12× NeoPixel; **R10 = direct Pi GPIO12 PWM**, R6 = I2C 0x04 via ATtiny | Not implemented |
| PWM fan | GPIO13, thermal-zone driven | ✅ pwm-fan |

Buses enabled in the machine conf (`mycroft-mkii-rpi-devkit.conf`) are
I2C, SPI, and UART. `i2c-dev` is autoloaded so userspace init tooling can
reach the bus.

> **SJ201 revision matters.** This unit is **R10**: the LED ring is driven
> directly from the Pi's **GPIO12 (PWM0)** via `rpi_ws281x` NeoPixel, *not*
> over I2C. GPIO12 (LEDs) and GPIO13 (fan) share the PWM block, so a future
> LED implementation must coordinate the PWM clock divisor with the fan
> (OVOS uses an `HwPwmAwareLed` shim for exactly this). On older **R6**
> boards the ring is instead driven by an on-board ATtiny1614 over I2C
> address `0x04`. Check the board silkscreen before implementing LEDs.

### Physical access / disassembly

To open the enclosure and reach the Pi and SJ201, follow the
[Mark II teardown guide](https://blog.graywind.org/posts/mark2-teardown/)
(good photos and diagrams of each step).

---

## 1. fstab must mount /home and /data by LABEL, not by device path

RAUC A/B layout (p1=boot FAT, p2=rootfs_A, p3=rootfs_B, p5=/home,
p6=/data) on mmcblk0 (SD card). p5/p6 are logical partitions inside an MBR
extended container (p4).

**A device-path fstab (`/dev/mmcblk0p5 /home`, `/dev/mmcblk0p6 /data`)
silently crosses the mounts.** On this hardware the logical-partition
enumeration assigned p5→/data and p6→/home — the reverse of the WKS intent
— so `x-systemd.growfs` grew the *wrong* partition (the 1G fixed /home
filled instead of /data). The partition table itself was correct
(p5 = 1024M fixed, p6 = grow); only the mount mapping was wrong.

**Fix:** mount by filesystem LABEL. The WKS already labels the partitions
(`--label homefs`, `--label data`), and WIC passes these to `mkfs.ext4 -L`,
so they resolve via `/dev/disk/by-label`:

```
LABEL=homefs   /home   ext4   defaults,nofail        0  0
LABEL=data     /data   ext4   x-systemd.growfs       0  0
```

The Mark II BSP ships this fstab via
`recipes-core/base-files/base-files_%.bbappend` (just `FILESEXTRAPATHS` +
`files/fstab`; base-files' own `SRC_URI` already lists `file://fstab`).
The `/root` → `/home/root` symlink (persistent root home on the read-only
rootfs) is **distro-wide policy and lives in `meta-appliance-os`**, not the
BSP. Reflash is required to fix an already-mis-grown card.

---

## 2. SJ201 DT overlays deployed to boot partition

The `sj201-dtoverlays` recipe (`recipes-kernel/sj201-dtoverlays/`) compiles the
three overlays (`sj201`, `sj201-buttons-overlay`, `sj201-rev10-pwm-fan-overlay`)
from the OpenVoiceOS VocalFusionDriver sources with `dtc-native` and deploys
the `.dtbo` files into `DEPLOY_DIR_IMAGE`. They are not picked up by
`IMAGE_BOOT_FILES` automatically, so the variant wires them explicitly:

```bitbake
IMAGE_BOOT_FILES:append = " sj201.dtbo;overlays/sj201.dtbo ..."
do_image_wic[depends] += "sj201-dtoverlays:do_deploy"
```

`config.txt` enables them (and the I2S/SPI/I2C buses + DSI display) via the
`rpi-config_git.bbappend` `do_deploy:append`.

TODO: confirm the boot symptom seen on real hardware before the overlays land
(silent card / no buttons / no fan).

---

## 3. TAS5806MD amplifier init

The TAS5806MD needs an I2C register init sequence to leave the mute/standby
state after power-on. Without it the card enumerates but stays silent.

The `sj201-init` service runs the sequence ordered before `sound.target`.
The amp is at **I2C address `0x2f` on bus 1** (`/dev/i2c-1`). The init tool
(`tas5806-init`) walks the register sequence ending in play mode; on
success it logs `tas5806-init: TAS5806MD initialized (play mode)`.

Verify: `systemctl status sj201-init` (should be `active (exited)`,
status 0). The card enumerates as `card 0: sj201` (`aplay -l`); the
playback device is the I2S SPDIF DIT path (`fe203000.i2s-dit-hifi`).

---

## 4. XMOS XVF-3510 firmware upload

The XVF-3510 boots without functional firmware, so the DSP image must be
uploaded at runtime before the mic array works.

Transport is **SPI**. The `xvf3510-firmware` recipe ships the blob +
`xvf3510-flash` tool, and `sj201-init` uploads it during boot **only if
both are present** (it logs `XMOS firmware/tool absent, skipping DSP
upload` and continues otherwise — playback does not depend on it).

The blob and tool are **proprietary and non-redistributable**, so the
recipe is gated behind `LICENSE_FLAGS = "xmos-xvf3510-firmware"` and the
files are not vendored. To enable the mic array, supply the files (see
`recipes-bsp/xvf3510-firmware/files/README.md`) and uncomment the
`LICENSE_FLAGS_ACCEPTED` + `IMAGE_INSTALL` lines in the variant.

---

## 5. No framebuffer console on the DSI display

meta-raspberrypi's default `cmdline.txt` only has
`console=serial0,115200`, so without `console=tty1` the kernel never
attaches `fbcon` and the screen stays blank. `console=tty1` is appended to
the kernel command line in layer.conf.

---

---

## 6. PipeWire is per-user; a root login shell steals the audio card

PipeWire/WirePlumber run as **user services** in the compositor's
`systemd --user` session. The compositor user is **`weston` (uid 800)**,
not `kiosk` — Feishin (Chromium, run as `kiosk`) connects to the weston
session's PipeWire as a *client*.

Consequences when debugging from a **root** serial/SSH shell:

- `wpctl` / `speaker-test` as root **fail** (`Could not connect to
  PipeWire`, or `Playback open error: -13` / `-16 Device or resource
  busy`). Logging in as root spawns a *second* `systemd --user` PipeWire
  for root that competes for `hw:0,0`; this is harmless in normal
  operation (no root shell open) but blocks raw-ALSA testing.
- Test through the real session instead:

  ```sh
  su -s /bin/sh weston -c 'XDG_RUNTIME_DIR=/run/user/800 wpctl status'
  su -s /bin/sh weston -c 'XDG_RUNTIME_DIR=/run/user/800 speaker-test -c2 -twav -l1'
  ```

- `speaker-test -D hw:0,0` as root will always hit EBUSY while the weston
  session holds the card — this is **not** a fault.

The PipeWire sink currently shows as the generic "Built-in Audio Stereo"
rather than "SJ201"; cosmetic only (a WirePlumber alias could rename it).

---

Yocto-version-specific workarounds shared with every BSP are documented in
[scarthgap-quirks.md](scarthgap-quirks.md).
