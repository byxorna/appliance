# Phase 2: reTerminal Hardware Support

**Goal**: Verify that all reTerminal-specific hardware works under `appliance-os`
using the upstream `seeed-reterminal` machine directly: DSI display, capacitive touchscreen,
user buttons (F1-F4), power button, front-bezel LEDs, I2S WM8960 audio codec,
accelerometer, ambient light sensor, and IR receiver (GPIO 24, wired by us).
Write a `reterminal-config` recipe that owns the hardware-specific config.txt
fragments, module-load ordering, and the gpio-ir DT overlay. Strip all Qt/demo
packages pulled by meta-seeed-cm4's image bbappends.

**Depends on**: Phase 1 complete (bootable `core-image-minimal` with
`appliance-os` distro on SD card or eMMC).

## Requirements

1. All four user buttons (F1-F4) and the power button produce evdev events
   visible to `evtest`. The MCP23008 I/O expander at I2C 0x38 drives the user
   buttons via `gpio-keys`; the power button is on GPIO 13.
2. The DSI display shows a Linux console (or `fbcon` splash) in landscape
   1280x720 orientation. No compositor yet — Phase 2 validates the panel driver
   and DT overlay only; Cage + rotation is Phase 3.
3. The capacitive touchscreen is functional and emits correctly-oriented evdev
   events (touch coordinates map to the display, not mirrored/rotated). The
   reTerminal overlay's `tp_rotate=1` param handles this at the firmware level.
4. Front-bezel LEDs enumerate as `/sys/class/leds/usr_led0` (USR green),
   `/sys/class/leds/usr_led1` (STA red), `/sys/class/leds/usr_led2` (STA
   green). They can be toggled via sysfs `brightness`.
5. All four out-of-tree kernel modules load: `mipi_dsi` (DSI panel),
   `ltr30x` (ambient light sensor), `lis3lv02d` (accelerometer),
   `bq24179_charger` (charger IC). Sensor module failure is non-fatal but
   logged.
6. WM8960 I2S audio codec is visible to ALSA (`aplay -l` lists a card). Not
   the HiFi path — just confirming the hardware enumerates. PipeWire
   configuration is Phase 6.
7. The gpio-ir DT overlay is enabled on GPIO 24. An IR receiver wired to that
   pin creates an RC input device visible at `/dev/input/eventX`. Exact pin
   verified against the expansion-board schematic before soldering.
8. No Qt packages, no qtdemo, no seeed image-level bloat is present in the
   final rootfs.
9. Build continues to succeed with `make build` after all changes.

## Detailed Implementation Plan + Reasoning

### What meta-seeed-cm4 already provides

The pinned commit `a2f9438` in `kas/reterminal-hifi.yaml` provides:

- **Machine conf** (`seeed-reterminal.conf`): requires `raspberrypi4-64.conf`,
  adds `ENABLE_I2C = "1"`, `ENABLE_UART = "1"`, `KERNEL_MODULE_AUTOLOAD:rpi +=
  "i2c-dev"`, and a Qt packageconfig append (irrelevant to us).
- **DT overlays and kernel modules** (`seeed-linux-dtoverlays.bb`): builds all
  reTerminal overlays (`reTerminal.dtbo`, `reTerminal-bridge.dtbo`) and out-of-
  tree kernel modules from `Seeed-Studio/seeed-linux-dtoverlays`. Uses
  `SRCREV = "${AUTOREV}"` — see the pinning issue below.
- **config.txt bbappend** (`rpi-config_git.bbappend`): for `seeed-reterminal`
  machine, appends `dtoverlay=reTerminal,tp_rotate=1,addr=0x38`,
  `dtoverlay=i2c3,pins_4_5`, `dtparam=i2c_vc=on`,
  `dtoverlay=vc4-kms-v3d-pi4`, `dtoverlay=dwc2,dr_mode=host`,
  `enable_uart=1`, `dtparam=spi=on`. Note the `tp_rotate=1` is already there —
  the touchscreen rotation is handled at the DT overlay level.
- **Image bbappends**: `core-image-minimal.bbappend` sets root password to
  `seeed`. `core-image-base.bbappend` adds SSH, a pile of dev tools (vim, git,
  curl, nano, tmux, etc.), and `kernel-modules`. These are intrusive and will
  be masked or overridden.

We use `MACHINE = "seeed-reterminal"` directly (no derived machine conf).
`KERNEL_DEVICETREE:remove` for 6.1-missing overlays lives in
`meta-appliance-os/conf/layer.conf` where it's visible to both kernel and
image recipes. Our `rpi-config_git.bbappend` only adds the lines upstream
doesn't have (`i2s=on`, `gpio-ir`); the upstream bbappend's machine guard
fires correctly since `MACHINE` matches `seeed-reterminal`.

### The AUTOREV problem in seeed-linux-dtoverlays

`seeed-linux-dtoverlays.bb` uses `SRCREV = "${AUTOREV}"`, which violates our
convention (AGENTS.md: "Never use `${AUTOREV}`"). On every `bitbake` invocation,
AUTOREV triggers a `git ls-remote` to HEAD of the `master` branch. This means:
- Builds are not reproducible.
- A bad upstream push silently breaks the build.
- Offline builds fail.

**Resolution**: Write a `seeed-linux-dtoverlays.bbappend` in `meta-appliance-os`
that overrides `SRCREV` with a pinned commit hash. The commit must be the latest
tag or commit on `master` that is compatible with the 6.1 kernel (the kernel
version pinned by meta-seeed-cm4). We resolve this hash during Phase 2
implementation by checking the upstream repo's recent commits.

### Masking meta-seeed-cm4's image bbappends

`core-image-minimal.bbappend` sets a root password. `core-image-base.bbappend`
pulls in SSH, dev tools, and all kernel modules. For `core-image-minimal`:
- The root password bbappend is harmless for now (dev image), but we will want
  to control this ourselves later. Leave it for Phase 2; override in the
  `appliance-os-image` recipe in Phase 3.
- The `core-image-base.bbappend` only fires for `core-image-base`, not
  `core-image-minimal`, so it doesn't affect us today.

For cleanliness: add `BBMASK` entries in `meta-appliance-os/conf/layer.conf`
to mask both image bbappends. This prevents meta-seeed-cm4 from injecting
packages into any image we build, regardless of the image recipe name.

### reterminal-config recipe

A new recipe `reterminal-config` in `meta-appliance-os/recipes-bsp/` that owns
the hardware-level platform configuration not covered by meta-seeed-cm4's DT
overlay recipe. Responsibilities:

1. **`/etc/modules-load.d/reterminal.conf`**: Ensures `mipi_dsi` is loaded
   early (before display init). Other modules (`ltr30x`, `lis3lv02d`,
   `bq24179_charger`) load via udev when their I2C devices appear; we don't
   force them here. Listing `mipi_dsi` ensures the DSI panel is driven even if
   udev ordering is late.

2. **gpio-ir overlay for IR receiver**: Adds a `config.txt` fragment via
   `rpi-config` bbappend (or a direct file-drop to the deploy dir) containing
   `dtoverlay=gpio-ir,gpio_pin=24`. This overlay is part of the upstream
   meta-raspberrypi kernel (not a seeed overlay), so it's already built. We
   just need to enable it in config.txt. GPIO 24 is free on the standard
   reTerminal pinout — GPIOs 18-21 are I2S (WM8960), GPIO 13 is power button,
   GPIOs 0-3/4-5/6-7/14-15 are I2C/SPI/UART.

3. **I2S audio enablement**: Adds `dtparam=i2s=on` to config.txt if not already
   present. The WM8960 codec is wired to GPIOs 18-21 (BCLK, LRCLK, DIN, DOUT)
   via the `reTerminal-bridge.dtbo` overlay (already enabled by
   `seeed-linux-dtoverlays`). The `dtparam=i2s=on` kernel param is the master
   switch that enables the I2S peripheral. Without it, the WM8960 doesn't
   enumerate in ALSA.

**Implementation approach**: Use a `rpi-config` bbappend that adds our
config.txt lines in the `do_deploy:append()` function, using the same
grep-then-echo pattern that meta-seeed-cm4 uses. This keeps all config.txt
management in one idiom. Alternatively, use `RPI_EXTRA_CONFIG` if
meta-raspberrypi supports it cleanly — check during implementation.

### No derived machine conf

Originally planned a derived `appliance-reterminal` machine, but this caused
the upstream `rpi-config_git.bbappend` machine guards to miss (they check
`MACHINE = "seeed-reterminal"` literally). Using the upstream machine name
directly avoids duplicating all upstream config.txt lines and makes upstream
updates automatic. The only fixup needed is `KERNEL_DEVICETREE:remove` in
`layer.conf` for 6.1-missing overlays.

### Display rotation: what Phase 2 validates vs. what Phase 3 does

The DSI panel is 720x1280 portrait. For final landscape display:
- **DT overlay `tp_rotate=1`**: rotates the *touchscreen input coordinates*
  90° to match a landscape display. Already set by meta-seeed-cm4's
  rpi-config bbappend for `seeed-reterminal` machine.
- **Cage `transform 270`**: rotates the *compositor output* to landscape. This
  is Phase 3 (Cage doesn't exist in Phase 2).

In Phase 2, the display will show a portrait-oriented console (720 wide, 1280
tall) because there's no compositor to rotate output. That's expected. The
validation is: "DSI panel lights up and shows something". Rotation alignment
testing happens in Phase 3 when Cage is added.

**Updated from top-level plan**: The Phase 2 task list in the top-level plan
included "Rotation alignment test" — that's moved to Phase 3 because it
requires Cage. Phase 2 validates: panel works, touch events fire, touch
coordinates are at least internally consistent (we can check raw evdev
coordinates from `evtest` to confirm the `tp_rotate` param is applied).

### IR receiver pin verification

GPIO 24 was chosen in the top-level plan as the IR receiver data pin. Before
soldering:

1. Check the reTerminal expansion-board schematic (published by Seeed at
   https://files.seeedstudio.com/wiki/ReTerminal/reTerminal-v1.3_SCH.pdf or
   in the wiki). Confirm GPIO 24 is:
   - Not routed to any on-board peripheral.
   - Available on the 40-pin header.
   - Not conflicting with any overlay we enable (I2C3 uses pins 4/5, I2S uses
     18-21, SPI uses 7-11, UART uses 14/15).

2. If GPIO 24 is occupied, fall back to GPIO 25 or another free pin and update
   the `gpio-ir` overlay param.

3. Document the final pin choice and verification result in this plan.

### Qt stripping

`meta-seeed-cm4` does **not** have `LAYERDEPENDS` on `meta-qt5` (confirmed:
`conf/layer.conf` only depends on `core`). The `seeed-reterminal.conf` machine
conf has `PACKAGECONFIG:append:pn-qtbase = " eglfs "`, which is a no-op if
`qtbase` is never built (it just sets a config flag on a recipe that doesn't
exist in our layer stack). No Qt recipes are in our layer stack, so no Qt
packages will be built.

The only Qt presence is the `recipes-qtdemo/` directory and the
`PACKAGECONFIG:append:pn-qtbase` line. Neither causes any packages to be
installed. No action needed beyond masking the image bbappends (which could
theoretically pull Qt-related IMAGE_INSTALL in future meta-seeed-cm4 commits).

### Hardware smoke test procedure

After building and flashing, run these tests on the device via serial console
(115200 8N1, GPIO 14/15 UART on the 40-pin header or USB-C debug):

```
# 1. Kernel modules
lsmod | grep -E 'mipi_dsi|ltr30x|lis3lv02d|bq24179'

# 2. Display (should see /dev/fb0 or /dev/dri/card0)
ls /dev/fb* /dev/dri/*

# 3. Input devices (buttons + touchscreen + optional IR)
cat /proc/bus/input/devices

# 4. Button test (press each button, observe output)
evtest /dev/input/eventX   # pick the gpio-keys device

# 5. Touchscreen test (tap screen, observe coordinates)
evtest /dev/input/eventX   # pick the goodix-ts device

# 6. LEDs
echo 1 > /sys/class/leds/usr_led0/brightness   # USR green on
echo 0 > /sys/class/leds/usr_led0/brightness   # off
echo 1 > /sys/class/leds/usr_led1/brightness   # STA red on
echo 1 > /sys/class/leds/usr_led2/brightness   # STA green on

# 7. Audio (WM8960 ALSA card)
aplay -l

# 8. IR receiver (if wired)
# With an IR LED or remote pointed at the receiver:
ir-keytable -t -s rc0

# 9. I2C devices (MCP23008 at 0x38, ambient light, accelerometer)
i2cdetect -y 1
i2cdetect -y 3
```

### What packages need to be in the image

`core-image-minimal` is very bare — no `evtest`, no `i2c-tools`, no
`alsa-utils`, no `v4l-utils`. For Phase 2 hardware validation we need
diagnostic tools. Two approaches:

**Option A**: Temporarily add packages to `local.conf` (or a kas include)
for the test image, without polluting the permanent image recipe.

**Option B**: Create a `core-image-minimal` bbappend in `meta-appliance-os`
that adds hardware-test packages, gated by a `MACHINE_FEATURES` or
`IMAGE_FEATURES` flag.

**Decision**: Use Option A — a kas include file `kas/test-tools.yaml` that
appends diagnostic packages to `IMAGE_INSTALL`. This keeps the base image clean
and the test tools opt-in (`kas build kas/reterminal-hifi.yaml:kas/test-tools.yaml`).
The test-tools include adds: `evtest`, `i2c-tools`, `alsa-utils`, `ir-keytable`,
`v4l-utils`, `devmem2`, `kernel-modules` (loads all built modules, not just
the auto-loaded ones).

## Task List

### Preparation

- [x] Resolve the pinned SRCREV for `seeed-linux-dtoverlays` (check upstream
      repo for latest 6.1-compatible commit on `master` branch)
      **Result**: Pin to `c336085a3a60a39afcc64fd784ec27dca71dbed2` (master
      HEAD, 2026-05-26). Initially considered pinning to `e9d88eb` (2025-08-02,
      the scarthgap build fix) to avoid post-tag 6.12/6.18 compat patches.
      Tested master HEAD instead — builds cleanly against the 6.1 kernel.
      The 6.12/6.18 patches use `#if` version guards and are harmless on 6.1.
      Pinning to HEAD gives us all upstream fixes including the panel crash
      fix, scarthgap build fix, ch343 driver update, and newer overlay
      support.
- [x] Verify GPIO 24 is free on the reTerminal expansion-board schematic
      **Result**: Confirmed free. GPIO 24 (BCM) / physical pin 18 is routed
      through to the 40-pin header via a series resistor and is not consumed
      by any on-board peripheral. The only potential conflict is the
      `reTerminal-bridge` overlay's MCP251xFD CAN controller interrupt pin,
      but that overlay is (a) not enabled in config.txt by default, and
      (b) only relevant when the E10-1 expansion module is attached (we don't
      use it). No conflicts with i2c3 (4/5), I2S (18-21), SPI (7-11),
      UART (14/15), or the base reTerminal overlay (6, 13).

### Recipes and configuration

- [x] Create `meta-appliance-os/recipes-kernel/seeed-linux-dtoverlays/seeed-linux-dtoverlays.bbappend`
      — override `SRCREV` with pinned commit `c336085a3a60a39afcc64fd784ec27dca71dbed2`
- [x] Create `meta-appliance-os/recipes-bsp/reterminal-config/reterminal-config.bb`
      — installs `/etc/modules-load.d/reterminal.conf` (lists `mipi_dsi`)
- [x] Switch from derived `appliance-reterminal` to upstream `seeed-reterminal`
      machine. Deleted `conf/machine/appliance-reterminal.conf`. Moved
      `KERNEL_DEVICETREE:remove` to `layer.conf`. Slimmed `rpi-config_git.bbappend`
      to only `i2s=on` and `gpio-ir` (upstream handles all base reTerminal lines).
      Updated kas, Makefile (now derives MACHINE/IMAGE from kas YAML), docs.
- [x] Create `meta-appliance-os/recipes-bsp/bootfiles/rpi-config_git.bbappend`
      — adds `dtparam=i2s=on` and `dtoverlay=gpio-ir,gpio_pin=24` to config.txt
- [x] Add `BBMASK` entries to `meta-appliance-os/conf/layer.conf` masking
      `meta-seeed-cm4/recipes-core/images/core-image-minimal.bbappend` and
      `meta-seeed-cm4/recipes-core/images/core-image-base.bbappend`
- [x] Create `kas/test-tools.yaml` — kas include adding `evtest`, `i2c-tools`,
      `alsa-utils`, `ir-keytable`, `v4l-utils`, `devmem2`, `kernel-modules`
- [x] Add `seeed-linux-dtoverlays` and `reterminal-config` to `IMAGE_INSTALL`
      via `local_conf_header` in `kas/reterminal-hifi.yaml`

### Build and verify (host-side)

- [x] `make build` succeeds with the new recipes and bbappends
- [x] Verify the generated `config.txt` in the deploy dir contains the
      expected overlays (`reTerminal,tp_rotate=1,addr=0x38`, `gpio-ir,gpio_pin=24`,
      `i2c3,pins_4_5`, `i2s=on`, `vc4-kms-v3d-pi4`) — confirmed all present
- [x] Verify the rootfs manifest does not contain any Qt packages — confirmed.
      Only `qt` matches are kernel modules (`mi0283qt`, `qt1010` tuner driver).
- [x] Verify `seeed-linux-dtoverlays` built against the pinned SRCREV (check
      build log for the fetched commit) — confirmed `c336085a3a60a39afcc64fd784ec27dca71dbed2`

### Hardware validation (on-device)

- [ ] Flash image to SD card, boot on reTerminal, get serial console
- [ ] Verify all 4 kernel modules load: `mipi_dsi`, `ltr30x`, `lis3lv02d`,
      `bq24179_charger`
- [ ] Verify DSI display lights up and shows console output
- [ ] Verify touchscreen emits evdev events (`evtest`) — confirm `tp_rotate=1`
      is applied by checking coordinate orientation
- [ ] Verify all 4 user buttons (F1-F4) emit distinct evdev key events
- [ ] Verify power button emits an evdev event (GPIO 13)
- [ ] Verify front-bezel LEDs enumerate as `/sys/class/leds/usr_led{0,1,2}`
      and toggle via sysfs `brightness`
- [ ] Verify WM8960 codec enumerates in `aplay -l`
- [ ] Verify I2C devices visible: `i2cdetect -y 1`, `i2cdetect -y 3`
      (expect MCP23008 at 0x38 on one bus, ambient light + accelerometer on
      the other)
- [ ] Wire IR receiver to GPIO 24 and verify RC input device appears; send
      test NEC commands, confirm `ir-keytable -t` shows decoded scancodes.
      If GPIO 24 is problematic, document the alternate pin and update the
      rpi-config bbappend.
- [ ] Flash image to eMMC via rpiboot (per flash catalog procedure), verify
      same hardware behavior as SD card boot

### Documentation

- [ ] Update `docs/building.md` with the `kas/test-tools.yaml` usage
- [ ] Document final GPIO pin assignment for IR receiver in this plan
- [ ] Record image size, boot time (to login prompt), and any issues
      discovered during hardware validation

## Architecture Decisions

### Config.txt management via rpi-config bbappend

We use the same `do_deploy:append` + grep-then-echo pattern as meta-seeed-cm4
rather than `RPI_EXTRA_CONFIG`. Reason: `RPI_EXTRA_CONFIG` is a single
variable that gets appended wholesale, and multiple layers writing to it would
concatenate unpredictably. The grep-then-echo pattern is idempotent and allows
multiple bbappends to add lines independently.

### kas include for test tools (not a permanent image change)

Diagnostic packages are opt-in via `kas/test-tools.yaml` rather than baked
into the image recipe. Reasons: (a) the production image should be minimal,
(b) test tools add ~20MB to rootfs, (c) the same include can be used for any
future hardware-debug session without changing committed recipes.

### Masking image bbappends rather than overriding individual variables

meta-seeed-cm4's image bbappends set root passwords and install dozens of
dev packages. Rather than surgically `IMAGE_INSTALL:remove`-ing each one
(fragile if upstream adds more), we `BBMASK` the entire bbappend files. This
is the same pattern already used for the broken `rpi-bootfiles.bbappend`.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| seeed-linux-dtoverlays HEAD is incompatible with 6.1 kernel | Low (Seeed tracks 6.1) | Build failure | Pin to a known-good commit from the 6.1 era; test before pinning |
| GPIO 24 is routed to an expansion-board peripheral | Low (schematic suggests it's free) | Must pick alternate pin | Check schematic; GPIO 25/26 are alternates |
| mipi_dsi module doesn't load on 6.1 kernel | Low (meta-seeed-cm4 targets 6.1) | No display | Serial console for debug; check dmesg for probe errors |
| meta-seeed-cm4 image bbappends pull in unexpected deps we don't mask | Medium | Image bloat | `wic ls` and manifest review after build |
| WM8960 doesn't enumerate without `dtoverlay=reTerminal-bridge` | Medium | No onboard audio | Verify reTerminal-bridge.dtbo is deployed; add explicit overlay enablement if needed |

## Dependencies

- Phase 1: bootable image with serial console
- Hardware: reTerminal unit, USB-C cable, microSD card or rpiboot setup
- IR receiver module: TSOP38238 or equivalent (3.3V, 38kHz), 3 wires to
  GPIO header (VCC 3.3V pin 1, GND pin 6, data pin 18 = GPIO 24)
