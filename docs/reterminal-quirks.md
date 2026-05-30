# reTerminal Quirks

Collected workarounds needed to run Yocto **scarthgap (5.0)** on the
Seeed reTerminal (CM4 4GB, eMMC) with **meta-seeed-cm4** (commit `a2f9438`)
and **meta-raspberrypi** (scarthgap branch). Kernel is **6.1.77-v8**
(pinned by meta-seeed-cm4).

All fixes live in `layers/meta-appliance-bsp-reterminal/`.

---

## 1. Custom fstab for 5-partition A/B layout

**Context:** The image uses a 5-partition MBR layout for RAUC A/B
updates: p1=boot (FAT), p2=rootfs_A (ext4), p3=rootfs_B (ext4),
p5=/data (ext4), p6=/home (ext4). Partitions 4+ are logical partitions
inside an MBR extended container, so the 4th and 5th WKS entries map to
`mmcblk0p5` and `mmcblk0p6`.

**Why a custom fstab:** `meta-rauc-raspberrypi` (priority 6) ships an
fstab via `base-files` bbappend with partition sizing appropriate for its
reference image. Our BSP layer (priority 10) overrides the fstab to
match our WKS layout: larger boot partition (128M vs 100M), larger data
partition (1G vs 100M), and read-only rootfs mount. The `/home` mount
uses `x-systemd.growfs` so the filesystem expands to fill remaining
eMMC space at first boot (after `rauc-grow-data-part` resizes the
extended container and partition 6).

**Files:**
- `recipes-core/base-files/base-files_%.bbappend`
- `recipes-core/base-files/files/fstab`

---

## 2. Kernel DT overlays missing from boot partition

### 2a. `reTerminal.dtbo` not deployed

**Symptom:** DSI display is blank. `dmesg` shows `vc4-drm` reporting
`Cannot find any crtc or sizes`. The DSI node in the device tree is
`status = "disabled"`. The `mipi_dsi` module loads but never probes the
panel. `find / -name 'reTerminal*'` returns nothing.

**Root cause:** The `seeed-linux-dtoverlays` recipe builds
`reTerminal.dtbo` and puts it in `DEPLOYDIR` via `do_deploy`, but
meta-raspberrypi's `IMAGE_BOOT_FILES` only picks up overlays that are
listed in `KERNEL_DEVICETREE`. The Seeed overlays are out-of-tree and
not in that variable, so they never land on the FAT boot partition. The
firmware silently skips overlays it can't find — config.txt says
`dtoverlay=reTerminal` but the `.dtbo` file isn't there.

**Fix:** Explicitly add the Seeed overlay to `IMAGE_BOOT_FILES` in layer.conf:

```bitbake
IMAGE_BOOT_FILES:append = " reTerminal.dtbo;overlays/reTerminal.dtbo"
```

The `src;dest` syntax maps from `DEPLOYDIR` to the boot partition path.

### 2b. `i2c3.dtbo` not deployed

**Symptom:** I2C bus 3 (used by the touch panel at `addr=0x38`) doesn't
exist at runtime. `i2cdetect -y 3` returns nothing.

**Root cause:** `meta-seeed-cm4`'s `seeed-reterminal.conf` machine
config does not add `i2c3.dtbo` to `RPI_KERNEL_DEVICETREE_OVERLAYS`,
even though its own rpi-config bbappend writes `dtoverlay=i2c3,pins_4_5`
to config.txt. Other Seeed machine configs (reComputer) do add it. The
overlay is a standard kernel overlay — it gets built but never deployed
to the boot partition.

**Fix:** Append it to the overlay list in layer.conf:

```bitbake
RPI_KERNEL_DEVICETREE_OVERLAYS:append = " overlays/i2c3.dtbo"
```

---

## 3. Kernel 6.1 incompatible overlay references

**Symptom:** Build fails when meta-raspberrypi tries to compile DT
overlays that don't exist in the 6.1 kernel source tree.

**Root cause:** meta-raspberrypi scarthgap's `rpi-base.inc` lists
overlays added after 6.1 (Pi 5 support, new DSI panel variants).
meta-seeed-cm4 pins the kernel to 6.1.y, so these `.dts` sources are
missing.

**Fix:** Remove them at layer.conf scope (not in a bbappend) so the fix
is visible to both the kernel recipe and image recipes that read
`IMAGE_BOOT_FILES` at parse time:

```bitbake
KERNEL_DEVICETREE:remove = " \
    overlays/vc4-kms-dsi-ili9881-7inch.dtbo \
    overlays/vc4-kms-dsi-ili9881-5inch.dtbo \
    overlays/w1-gpio-pi5.dtbo \
    overlays/bcm2712d0.dtbo \
"
```

---

## 4. Broken rpi-bootfiles bbappend (404 download)

**Symptom:** Build fails fetching `dt-blob-disp1-cam2.bin`.

**Root cause:** meta-seeed-cm4's `rpi-bootfiles.bbappend` downloads a
`dt-blob` binary from `datasheets.raspberrypi.org` that is permanently
404. `dt-blob.bin` is a legacy mechanism — the reTerminal display is
configured via DT overlays in config.txt, not via dt-blob.

**Fix:** BBMASK the broken bbappend:

```bitbake
BBMASK += "meta-seeed-cm4/recipes-bsp/bootfiles/rpi-bootfiles.bbappend"
```

---

## 5. No framebuffer console on the DSI display

**Symptom:** Even with the display pipeline working, the screen shows
nothing — no kernel messages, no login prompt.

**Root cause:** meta-raspberrypi's default `cmdline.txt` only has
`console=serial0,115200`. Without `console=tty1`, the kernel doesn't
attach `fbcon` to the framebuffer, and systemd's `getty@tty1` has
nothing to render to.

**Fix:** Append `console=tty1` to the kernel command line in layer.conf:

```bitbake
CMDLINE:append = " console=tty1"
```

---

## 6. meta-seeed-cm4 image bbappends override appliance config

**Symptom:** Root password gets set, unwanted dev tools (vim, git, curl,
tmux) are pulled into the image, overriding the appliance's minimal
package set.

**Root cause:** meta-seeed-cm4 ships bbappends for `core-image-minimal`
and `core-image-base` that set a root password and add packages. These
run at the same priority as any other bbappend and silently modify the
image.

**Fix:** BBMASK both:

```bitbake
BBMASK += "meta-seeed-cm4/recipes-core/images/core-image-minimal.bbappend"
BBMASK += "meta-seeed-cm4/recipes-core/images/core-image-base.bbappend"
```

---

## 7. `seeed-linux-dtoverlays` uses AUTOREV

**Symptom:** Builds are non-reproducible; fetching can fail if upstream
force-pushes.

**Root cause:** The upstream recipe uses `SRCREV = "${AUTOREV}"` which
resolves to `master` HEAD at fetch time.

**Fix:** Pin SRCREV in a bbappend:

```bitbake
SRCREV = "c336085a3a60a39afcc64fd784ec27dca71dbed2"
```

(`recipes-kernel/seeed-linux-dtoverlays/seeed-linux-dtoverlays.bbappend`)

---

## 8. `zsh` license breaks SPDX generation

**Symptom:** `do_create_spdx` fails with "Cannot find any text for
license zsh".

**Root cause:** The `zsh` recipe in meta-oe declares `LICENSE = "zsh"`
but Yocto has no matching file in `common-licenses/`. The SPDX tooling
requires a license text file for every declared license.

**Fix:** bbappend that maps the license to the source tree's `LICENCE`
file:

```bitbake
LICENSE = "MIT-like"
NO_GENERIC_LICENSE[MIT-like] = "LICENCE"
```

(`layers/meta-appliance-os/recipes-shells/zsh/zsh_%.bbappend` — this one lives
in the OS layer since it's not hardware-specific.)
