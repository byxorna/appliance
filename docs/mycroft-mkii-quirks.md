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

The Mark II DevKit is a **stock Raspberry Pi 4B** (`raspberrypi4-64`). It
has **no eMMC**; the OS lives on the **microSD card**. Flashing is a plain
`bzcat … .wic.bz2 | dd` to the SD card; there is no `rpiboot` / boot-switch
dance (that is CM4-only). Boot device selection is governed by the Pi 4
EEPROM `BOOT_ORDER`, independent of the image (`rpi-eeprom-config --edit`).

The SJ201 daughterboard carries the audio and front-panel hardware:

| Component | Role | Status |
| --- | --- | --- |
| XMOS XVF-3510 | Far-field voice DSP / mic array; SPI firmware upload at boot | Gated proprietary blob, not implemented |
| TAS5806MD | I2S Class-D amplifier, I2C addr `0x2f` on bus 1, needs init to un-mute | ✅ `sj201-init` |
| RPi-family DSI panel | 800x480, Atmel-MCU backlight (`10-0045`); bound by `vc4-kms-dsi-7inch` (label only, physical diagonal is smaller) | ✅ weston |
| ft5x06 touch | Capacitive touch over I2C (`10-0038`, same DSI bus as backlight) | ✅ enumerated |
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
enumeration assigned p5 to /data and p6 to /home, the reverse of the WKS
intent. `x-systemd.growfs` grew the *wrong* partition (the 1G fixed /home
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
The `/root` -> `/home/root` symlink (persistent root home on the read-only
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
upload` and continues otherwise. Playback does not depend on it).

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

## 6. PipeWire is per-user; a root login shell steals the audio card

PipeWire/WirePlumber run as **user services** in the kiosk user's
`systemd --user` session (uid 810). The `kiosk-session.service` system
unit holds a logind session open for kiosk via PAM, which creates
`/run/user/810` and starts `systemd --user`. `ConditionUser=kiosk`
drop-ins on the PipeWire units prevent them from starting in other user
sessions (e.g. weston's).

Consequences when debugging from a **root** serial/SSH shell:

- `wpctl` / `speaker-test` as root **fail** (`Could not connect to
  PipeWire`, or `Playback open error: -13` / `-16 Device or resource
  busy`). Logging in as root spawns a *second* `systemd --user` PipeWire
  for root that competes for `hw:0,0`; this is harmless in normal
  operation (no root shell open) but blocks raw-ALSA testing.
- Test through the real session instead:

  ```sh
  su -s /bin/sh kiosk -c 'XDG_RUNTIME_DIR=/run/user/810 wpctl status'
  su -s /bin/sh kiosk -c 'XDG_RUNTIME_DIR=/run/user/810 speaker-test -c2 -twav -l1'
  ```

- `speaker-test -D hw:0,0` as root will always hit EBUSY while the kiosk
  session holds the card. This is **not** a fault.

The PipeWire sink currently shows as the generic "Built-in Audio Stereo"
rather than "SJ201"; cosmetic only (a WirePlumber alias could rename it).

---

## 7. Front-panel button mappings

The SJ201's four GPIO buttons are exposed as a `gpio-keys` input device by
the `sj201-buttons` DT overlay. `triggerhappy` (running as the `inputd`
user) maps key events to actions:

| GPIO | Key code | Action |
|------|----------|--------|
| 22 | KEY_VOLUMEUP | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+` |
| 23 | KEY_VOLUMEDOWN | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-` |
| 24 | KEY_VOICECOMMAND | MPRIS PlayPause via D-Bus |
| 25 | KEY_MICMUTE | `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle` |

Trigger config: `/etc/triggerhappy/triggers.d/sj201-buttons.conf`.
Helper scripts: `/usr/libexec/appliance/`.

The `inputd` user has `input` group (evdev access) and `pipewire` group
(PipeWire socket access). The PipeWire socket is configured with
group-readable permissions (`0770`, group `pipewire`) so `inputd` can
call `wpctl` without running as `weston` or root.

The TAS5806 hardware digital volume defaults to -24 dB (register 0x4c =
0x30). PipeWire's software volume operates on top of this ceiling, with
WirePlumber defaulting new sinks to 60%.

---

Yocto-version-specific workarounds shared with every BSP are documented in
[scarthgap-quirks.md](scarthgap-quirks.md).

---

## 8. DSI display blanks on a wedged I2C bus, not a software blank timer

The DSI panel intermittently goes dark while everything else keeps running.
This is **not** a compositor screensaver, logind idle action, or kernel
framebuffer console blank. All of those were ruled out:

- Weston `idle-time=0` (set in `weston.ini [core]`). Idle path disabled.
- logind `IdleAction=ignore`. No idle blanking.
- `consoleblank=0` (kernel). Fbcon blank timer off.
- `/sys/class/drm/card1-DSI-1/dpms` reads `On` when dark. The DRM
  connector is **not** in DPMS-off.

**Actual cause:** the panel's Atmel-MCU backlight/power-sequencer
(`10-0045`) and the ft5x06 touch (`10-0038`) sit on the **`fe205000.i2c`
DSI/CSI bus, which is shared between the ARM (Linux) and the VideoCore
firmware**, behind an i2c-mux (`i2c-22` -> `i2c-10`). When the firmware does
display housekeeping on that bus concurrently with Linux, the bus wedges:
the ARM logs `Got unexpected interrupt (from firmware?)`, clears it, and the
firmware mailbox times out, leaving the Atmel MCU unresponsive. Symptoms:

- Reads of `actual_brightness` and writes to `brightness`/`bl_power` **hang
  and time out** ("connection timed out").
- `i2cdetect -y 10` loses `0x38` (touch) even though it stays driver-bound.
- The backlight goes dark while DRM DPMS still reports `On`.
- A **touch event** wakes it (re-asserts the mux channel); a **warm reboot
  does not** clear it (the Atmel MCU isn't reset), but a **power cycle**
  does (cold-resets the MCU). This reboot-vs-power-pull asymmetry is the
  signature of the firmware/MCU bus lockup.

**Fix:** `disable_fw_kms_setup=1` in `config.txt` (added by
`rpi-config_git.bbappend`). Full KMS parses EDID itself, so the firmware no
longer does display setup on the shared bus, removing the contention. The
kernel side is already covered: 6.6.x carries the hardened
`rpi-panel-attiny-regulator` driver (I2C retries + longer Atmel POWERON
delays, upstream mid-2022), so no kernel bump is needed. No duplicate
touch/backlight overlays are present (`rpi-ft5406`/`rpi-backlight` would
double-bind the controllers and cause the same fight). Only
`vc4-kms-dsi-7inch` binds them.

> The `vc4-kms-dsi-7inch` overlay name is a label, not the panel size: this
> panel runs at **800×480** on a physically small diagonal. Reference:
> [raspberrypi/linux#5397](https://github.com/raspberrypi/linux/issues/5397).

**Manual recovery if already wedged (no reboot):**

```sh
rmmod rpi_panel_attiny_regulator && modprobe rpi_panel_attiny_regulator
```

---

Yocto-version-specific workarounds shared with every BSP are documented in
[scarthgap-quirks.md](scarthgap-quirks.md).
