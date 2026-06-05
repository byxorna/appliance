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
p5=/home (ext4), p6=/data (ext4). Partitions 4+ are logical partitions
inside an MBR extended container, so the 4th and 5th WKS entries map to
`mmcblk0p5` and `mmcblk0p6`.

**Why a custom fstab:** `meta-rauc-raspberrypi` (priority 6) ships an
fstab via `base-files` bbappend with partition sizing appropriate for its
reference image. Our BSP layer (priority 10) overrides the fstab to
match our WKS layout: larger boot partition (128M vs 100M), and
read-only rootfs mount. The `/data` mount uses `x-systemd.growfs` so the
filesystem expands to fill remaining eMMC space at first boot (after
`rauc-grow-data-part` resizes the extended container and partition 6).
`/data` is the last partition and holds container images, app state, and
platform config — it needs the bulk of the eMMC (~30 GB on a 32 GB
device).

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

See [scarthgap-quirks.md §4](scarthgap-quirks.md#4-meta-raspberrypi-dt-overlays-missing-from-kernel-61). Caused by meta-seeed-cm4 pinning the kernel to 6.1; fix lives in `layers/meta-appliance-bsp-reterminal/conf/layer.conf`.

---

## 4. Broken rpi-bootfiles bbappend (404 download)

See [scarthgap-quirks.md §6](scarthgap-quirks.md#6-meta-seeed-cm4-broken-rpi-bootfiles-download-404).

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

Additional meta-seeed-cm4 workarounds (image bbappend overrides,
AUTOREV pinning) and the zsh SPDX fix are documented in
[scarthgap-quirks.md](scarthgap-quirks.md) since they are
Yocto-version-specific rather than hardware-specific.
