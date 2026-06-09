# Mycroft Mark II DevKit BSP, HiFi Variant

## Requirements

1. A new `meta-appliance-bsp-mkii` layer providing hardware support for the
   Mycroft Mark II Developer Kit (RPi4 + SJ201 daughterboard).
2. A new kas variant file `kas/variant-mkii-hifi.yaml` that builds the same
   appliance image as the reTerminal variant but targeting the Mark II hardware.
3. The SJ201 audio subsystem must be fully operational: XMOS XVF-3510 DSP
   firmware loaded, TAS5806MD amplifier initialized, I2S audio working.
4. The Waveshare 4.3" DSI display must work with touch input (Goodix GT911).
5. GPIO buttons (vol up, vol down, wake, mic mute) must appear as evdev input
   devices via `gpio-keys` DT overlay.
6. PWM fan thermal management must be active.
7. No changes to common.yaml, meta-appliance-os, or the reTerminal variant.
8. Reuse the existing RAUC A/B update infrastructure (dual rootfs, U-Boot).

## Detailed Implementation Plan + Reasoning

### Hardware reference

| Component | Detail |
|---|---|
| SoC | Raspberry Pi 4B, 2GB (bcm2711) |
| Daughterboard | SJ201 (Rev10 assumed; Rev6 compat noted) |
| Audio DSP | XMOS XVF-3510 (SPI firmware upload, I2S audio, 24.576 MHz MCLK on GPIO 4) |
| Amplifier | TI TAS5806MD @ I2C 0x2F (I2S input, 32-bit, 48 kHz, mono PBTL) |
| Microphones | 2x Knowles SPK0641HT4H-1 digital MEMS (via XMOS DSP) |
| LEDs | 12x WS2812B-MINI NeoPixel on GPIO 12 (Rev10) or ATtiny I2C 0x04 (Rev6) |
| Display | Waveshare 4.3" DSI IPS, 800x480, Goodix GT911 touch (I2C 0x14) |
| Buttons | GPIO 22 (vol up), 23 (vol down), 24 (wake), 25 (mic mute) |
| Fan | PWM on GPIO 13, thermal-managed (Rev10) |
| Power | 12V/3A barrel jack on SJ201, regulated to 5V for Pi |
| WiFi/BT | Onboard BCM43455 (same as RPi4) |

GPIO pin map:

| GPIO | Function | Direction |
|---|---|---|
| 4 | GPCLK0, XMOS MCLK (24.576 MHz) | ALT0 |
| 12 | NeoPixel data (Rev10) | Output (PWM) |
| 13 | Fan PWM | ALT0 (PWM1) |
| 16 | XMOS power enable | Output |
| 22 | Volume Up button | Input |
| 23 | Volume Down button | Input |
| 24 | Wake / Voice Command button | Input |
| 25 | Microphone Mute switch | Input |
| 26 | XMOS boot_sel (SPI slave mode) | Output |
| 27 | XMOS reset (active-low) | Output |

I2C devices (bus 1):

| Address | Device | Notes |
|---|---|---|
| 0x04 | ATtiny LED controller | Rev6 only |
| 0x14 | Goodix GT911 touch | DSI display |
| 0x2C | XMOS XVF-3510 I2C control | Both revisions |
| 0x2F | TAS5806MD amplifier | Both revisions |

### Architecture: mirror the reTerminal BSP pattern

The reTerminal variant:
```
meta-raspberrypi (machine: raspberrypi4-64)
  +-- meta-seeed-cm4 (machine: seeed-reterminal, seeed DT overlays)
       +-- meta-appliance-bsp-reterminal (bbappends, config, wks)
```

The Mark II variant:
```
meta-raspberrypi (machine: raspberrypi4-64)
  +-- meta-appliance-bsp-mkii (machine: mycroft-mkii, DT overlays, SJ201 drivers)
```

No meta-seeed-cm4 dependency. The Mark II is a standard RPi4 with a
well-documented daughterboard. The machine conf `require`s
`raspberrypi4-64.conf` directly, same as seeed-reterminal.conf does.

### Why no meta-seeed-cm4?

The reTerminal depends on meta-seeed-cm4 for two things: its DSI panel driver
(`seeed-linux-dtoverlays`) and a 6.1.y kernel pin. Neither applies to the
Mark II. The Waveshare DSI display uses the standard `vc4-kms-dsi-7inch`
overlay. The SJ201 needs its own DT overlays from the OVOS VocalFusionDriver
project.

### Machine configuration: `mycroft-mkii.conf`

```
require conf/machine/raspberrypi4-64.conf

# I2C for TAS5806MD, XMOS control, GT911 touch
ENABLE_I2C = "1"
# SPI for XMOS firmware upload
ENABLE_SPI_BUS = "1"
# UART for debug console
ENABLE_UART = "1"
# Autoload i2c-dev for userspace I2C access (tas5806-init, xvf3510-flash)
KERNEL_MODULE_AUTOLOAD:rpi += "i2c-dev"
```

Hardware-specific config.txt lines go in the `rpi-config` bbappend, same
pattern as the reTerminal BSP.

### DT overlays

Three custom overlays from the OVOS VocalFusionDriver project (MIT-licensed):

| Overlay | Purpose |
|---|---|
| `sj201.dts` | Audio card: I2S simple-audio-card with SPDIF codec in/out, MCLK on GPIO 4, power/reset on GPIO 16/27 |
| `sj201-buttons-overlay.dts` | GPIO keys: vol up (22), vol down (23), wake (24), mic mute (25) |
| `sj201-rev10-pwm-fan-overlay.dts` | PWM fan on GPIO 13, thermal trips at 40/50/55/60 C |

Two standard RPi overlays are also enabled in config.txt:

| Overlay | Purpose |
|---|---|
| `vc4-kms-v3d` | DRM/KMS (already default from meta-raspberrypi) |
| `vc4-kms-dsi-7inch` | DSI display + Goodix touch |

A `sj201-dtoverlays` recipe compiles `.dts` sources to `.dtbo` using the
kernel's DTC, then deploys to the boot partition.

### Kernel configuration

`CONFIG_SND_SOC_TAS5805M` is already in the RPi 6.6.y kernel tree
(`sound/soc/codecs/tas5805m.c`). Enable via a `.cfg` fragment.

`CONFIG_SND_BCM2708_SOC_XMOS_XVF3510` doesn't exist in the RPi kernel fork
(6.1.y, 6.6.y, or 6.12.y). The OVOS VocalFusionDriver project provides it
as an out-of-tree module. The module is ~100 LOC. It configures GPIO 4 as
GPCLK0 at 24.576 MHz, asserts power (GPIO 16) and reset (GPIO 27) to bring
up the XMOS, then releases the GPIOs back to userspace.

The actual sound card is a `simple-audio-card` defined entirely in the
`sj201.dts` overlay, using the kernel's built-in `spdif-dit`/`spdif-dir`
dummy codecs. No ALSA/ASoC callbacks or codec ops live in the C module.

Build the VocalFusionDriver as an out-of-tree kernel module recipe
(`vocalfusion-soundcard`). The kernel `.cfg` fragment enables only
`CONFIG_SND_SOC_TAS5805M=m`.

### XMOS XVF-3510 firmware upload

The XMOS DSP requires firmware uploaded via SPI at every boot. The OVOS
project uses `xvf3510-flash` (a C tool from XMOS) to send the binary.

Recipe `xvf3510-firmware` installs:
- `/usr/lib/firmware/xvf3510/app_xvf3510_int_spi_boot_v4_2_0.bin`
- `/usr/bin/xvf3510-flash`

A systemd service `xvf3510-firmware.service` runs early in boot:
1. Assert GPIO 16 high (power on XMOS)
2. Assert GPIO 27 low then high (reset XMOS)
3. Run `xvf3510-flash --direct /usr/lib/firmware/xvf3510/app_xvf3510_int_spi_boot_v4_2_0.bin`
4. Verify via I2C that XMOS is alive

### TAS5806MD amplifier initialization

The amp needs I2C register writes at boot to transition from deep sleep to
play mode. The OVOS project does this with Python + smbus2.

Recipe `sj201-init` installs:

| File | Purpose |
|---|---|
| `/usr/bin/tas5806-init` | Amp init script |
| `/usr/bin/sj201-init` | Wrapper running xvf3510-flash + tas5806-init |
| `sj201-init.service` | Systemd unit, `Before=sound.target`, `After=sys-subsystem-i2c-devices-i2c\x2d1.device` |

Init sequence (bus 1, addr 0x2F):
1. Reset: reg 0x01 = 0x11
2. Clear faults: reg 0x78 = 0x80
3. Remove reset: reg 0x01 = 0x00
4. 32-bit I2S mode: reg 0x33 = 0x03
5. SDOUT to DSP input: reg 0x30 = 0x01
6. Deep Sleep (0x03=0x00), then HiZ (0x03=0x02), then Play (0x03=0x03)
7. Set volume: reg 0x4C = 0x60

### ALSA / PipeWire configuration

The SJ201 audio card registers as `sj201` via the simple-audio-card DT node.
A `mkii-config` recipe installs `/etc/modprobe.d/sj201-alsa.conf` to set
sj201 as card index 0 and bcm2835 as index 1.

PipeWire + WirePlumber from the appliance-os distro auto-discovers the ALSA
card. No PipeWire-specific config needed for MVP.

### Display configuration

The Waveshare 4.3" DSI display is driver-free with `vc4-kms-dsi-7inch`.
800x480 landscape, no rotation needed. Touch uses the kernel's built-in
`goodix` driver.

### Weston configuration

The reTerminal BSP's weston-init bbappend sets output transform for its
portrait panel. The Mark II doesn't need rotation.

Move rotation config to the BSP layer. The weston-init bbappend in
meta-appliance-os provides a base kiosk-shell config without rotation. The
reTerminal BSP adds rotation via its own bbappend. The Mark II BSP needs no
weston-init override at all.

This requires refactoring the existing weston-init bbappend: split base
config in appliance-os from rotation in the reTerminal BSP.

### config.txt additions (rpi-config bbappend)

```bash
# I2S audio bus
dtparam=i2s=on
# SPI bus for XMOS firmware upload
dtparam=spi=on
# I2C bus for TAS5806MD, XMOS control, GT911 touch
dtparam=i2c_arm=on
dtparam=i2c_arm_baudrate=100000
# DSI display
dtoverlay=vc4-kms-dsi-7inch
# SJ201 audio card
dtoverlay=sj201
# SJ201 buttons
dtoverlay=sj201-buttons-overlay
# SJ201 fan (Rev10)
dtoverlay=sj201-rev10-pwm-fan-overlay
# GPU memory for display
gpu_mem=256
```

### LED support (deferred)

NeoPixel LEDs on GPIO 12 require `rpi_ws281x` and root PWM access. Deferred
for MVP.

### WKS file (partition layout)

Reuse `appliance-dual-rootfs.wks.in` from the reTerminal BSP. The partition
layout (boot FAT32 + rootfs-a + rootfs-b + data ext4) is identical for any
RPi4-based appliance. The file should move to a shared location or be
referenced by both BSP layers.

### RAUC / U-Boot

Same as reTerminal: `RPI_USE_U_BOOT = "1"`, U-Boot slot switching for A/B.
The RAUC bundle recipe in common.yaml is machine-agnostic.

### kas/variant-mkii-hifi.yaml

```yaml
header:
  version: 14
  includes:
    - kas/common.yaml
    - kas/debug.yaml
    - kas/devtools.yaml

machine: mycroft-mkii

repos:
  meta-raspberrypi:
    url: "https://git.yoctoproject.org/meta-raspberrypi"
    path: build/repos/meta-raspberrypi
    branch: scarthgap
    commit: 2c646d29912dcc873469a57b1c207e1549c5094d  # same pin

  meta-rauc-community:
    url: "https://github.com/rauc/meta-rauc-community.git"
    path: build/repos/meta-rauc-community
    branch: scarthgap
    commit: 222c61275054974cdbd09bd5faa2b7a37ddbd840
    layers:
      meta-rauc-raspberrypi:

  meta-appliance-bsp-mkii:
    path: layers/meta-appliance-bsp-mkii

local_conf_header:
  mkii-hw: |
    IMAGE_INSTALL:append = " \
        sj201-dtoverlays \
        sj201-init \
        xvf3510-firmware \
        mkii-config \
        linux-firmware-rpidistro-bcm43455 \
        bluez-firmware-rpidistro-bcm4345c0-hcd \
        pi-bluetooth \
        bluez5 \
    "
    LICENSE_FLAGS_ACCEPTED:append = " synaptics-killswitch Firmware-cypress-rpidistro"
  rauc-bsp: |
    RPI_USE_U_BOOT = "1"
    WKS_FILE = "appliance-dual-rootfs.wks.in"
  identity: |
    hostname:pn-base-files = "mkii-hifi"
```

No `meta-seeed-cm4` dependency. The Mark II BSP is self-contained.

### Open questions

1. xvf3510-flash tool source is in the OVOS buildroot tree. Need to verify
   license and create a Yocto recipe. Fallback: the Python
   `send_image_from_rpi.py` from Mycroft's hardware-testing repo.

2. TAS5806MD DSP firmware. OVOS ships
   `tas5805m_dsp_mono_pbtl_48khz_sj201.bin`. Unclear if the I2C init
   sequence alone is sufficient or if this DSP blob must also be loaded.

3. Weston rotation refactor. Moving rotation from meta-appliance-os to
   meta-appliance-bsp-reterminal must not break the existing reTerminal build.

4. SJ201 revision detection. Rev6 uses ATtiny for LEDs and has different fan
   control. MVP assumes Rev10 (the devkit version). Runtime detection via I2C
   probe of 0x04 can be added later.

## Task List

### Phase 0: Investigation
- [x] Check if `CONFIG_SND_BCM2708_SOC_XMOS_XVF3510` exists in the RPi 6.6.y kernel tree. Not in-tree.
- [x] Check if `CONFIG_SND_SOC_TAS5805M` exists in the RPi 6.6.y kernel tree. In-tree.
- [x] Locate the XMOS kernel driver from OVOS and assess portability. Trivial ~100 LOC init shim, out-of-tree module recipe.
- [ ] Locate `xvf3510-flash` source code and check license
- [ ] Determine if TAS5806MD DSP firmware blob is needed or if I2C init suffices

> **Naming note:** the implementation uses `mycroft-mkii-rpi-devkit` (machine,
> hostname) and the layer `meta-appliance-bsp-mycroft-mkii-rpi-devkit`, not the
> shorter `mycroft-mkii` / `meta-appliance-bsp-mkii` used earlier in this plan.
> SJ201 recipe names below (`sj201-dtoverlays`, `sj201-init`, `xvf3510-firmware`)
> are still placeholders; the config recipe is `mycroft-mkii-rpi-devkit-config`.

### Phase 1: BSP layer scaffolding
- [x] Create `layers/meta-appliance-bsp-mycroft-mkii-rpi-devkit/conf/layer.conf` (incl. `CMDLINE:append console=tty1 ro`)
- [x] Create `conf/machine/mycroft-mkii-rpi-devkit.conf` (require raspberrypi4-64; I2C/SPI/UART, i2c-dev autoload)
- [x] Create `kas/variant-mycroft-mkii-rpi-devkit-hifi.yaml`
- [x] Copy `wic/appliance-dual-rootfs.wks.in` into the BSP layer
- [ ] Verify the layer parses (`kas shell variant-mycroft-mkii-rpi-devkit-hifi.yaml -c "bitbake-layers show-layers"`) — pending current build

### Phase 2: DT overlays (DONE — overlays compiled + wired, `bitbake -p` clean)
- [x] Create `sj201-dtoverlays` recipe with sj201.dts, sj201-buttons-overlay.dts, sj201-rev10-pwm-fan-overlay.dts (standalone `dtc-native` recipe, `inherit deploy`)
- [x] Add rpi-config bbappend for config.txt (I2S, SPI, I2C, DSI, overlays) via `do_deploy:append`
- [x] Deploy overlays to boot partition via `IMAGE_BOOT_FILES:append` + `do_image_wic[depends]` in the variant

### Phase 3: Kernel config + out-of-tree module (NOT STARTED)
- [ ] Add kernel .cfg fragment enabling `CONFIG_SND_SOC_TAS5805M=m`
- [ ] Create `vocalfusion-soundcard` recipe building the OVOS out-of-tree XMOS init module
- [ ] Verify modules build cleanly

### Phase 4: SJ201 initialization (NOT STARTED; commented out in variant IMAGE_INSTALL)
- [ ] Create `xvf3510-firmware` recipe (firmware blob + flash tool)
- [ ] Create `sj201-init` recipe (TAS5806MD I2C init + systemd service)
- [ ] Create `mycroft-mkii-rpi-devkit-config` recipe (modprobe.d ALSA ordering, modules-load.d)
- [ ] Wire systemd ordering: sj201-init.service Before=sound.target

### Phase 5: Weston refactor
- [x] Move reTerminal rotation from meta-appliance-os weston-init bbappend to meta-appliance-bsp-reterminal
- [x] Verify reTerminal build still works after refactor (bitbake -p passes; only pre-existing feishin-wrapper error)
- [ ] Verify Mark II build gets rotation-free weston.ini

### Phase 6: Build and validate
- [x] `make VARIANT=mycroft-mkii-rpi-devkit-hifi build` — base image built 2026-06-08 (commit c4cac79, dirty). Artifacts: `.wic.bz2` (374 MB) + `.manifest` in `artifacts/`. No `.raucb` bundle yet; SJ201 recipes still commented out.
- [ ] Image boots on RPi4 (DSI display + basic rootfs, even without SJ201 initially)
- [ ] With SJ201: audio plays through TAS5806MD amp
- [ ] Buttons appear as /dev/input/event* devices
- [ ] Fan spins under thermal load
- [ ] Weston kiosk-shell shows on DSI display with touch working
