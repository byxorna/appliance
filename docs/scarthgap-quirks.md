# Scarthgap Quirks

Workarounds tied to Yocto **scarthgap (5.0)** or the specific upstream
component versions it ships. These should be re-evaluated when upgrading
to a newer Yocto release. Hardware-specific workarounds that are
independent of Yocto version live in [reterminal-quirks.md](reterminal-quirks.md).

---

## 1. systemd 255 userdb ENOMEDIUM bug (pam_systemd user resolution)

**Versions:** systemd 255.x (scarthgap ships 255.21)

**Symptom:** Weston service fails with `PAM failed: User not known to
the underlying authentication module` / exit code 224. Only affects
services with `PAMName=` in their unit file.

**Root cause:** When `pam_systemd.so` resolves a user through systemd's
userdb varlink Multiplexer, the `systemd-userwork` worker finds the
user record (via NSS or dropin) but then calls `build_user_json()`
to serialize the response. `build_user_json()` calls `add_nss_service()`,
which unconditionally reads `/etc/machine-id` via `sd_id128_get_machine()`
for any record that lacks a `"service"` JSON field. On a read-only rootfs
where `/etc/machine-id` hasn't been committed yet (empty or contains
"uninitialized"), this returns `-ENOMEDIUM` (errno 123), which propagates
as an `io.systemd.System` varlink error. The same issue affects
`build_group_json()`.

**Fix:** Ship userdb JSON dropin files (`weston.user`, `weston.group`)
in `/usr/lib/userdb/` with a `"service": "io.systemd.DropIn"` field.
The presence of the `"service"` field causes `add_nss_service()` to
return immediately without reading `/etc/machine-id`.

**Files:**
- `layers/meta-appliance-os/recipes-graphics/wayland/weston-init.bbappend`
- `layers/meta-appliance-os/recipes-graphics/wayland/weston-init/weston.user`
- `layers/meta-appliance-os/recipes-graphics/wayland/weston-init/weston.group`

**On upgrade:** If systemd >=256 fixes the ENOMEDIUM leak in
`build_user_json()` / `add_nss_service()`, the dropin files become
redundant (but harmless). Test by removing them and checking
`systemctl status weston` and `userdbctl user weston`.

---

## 2. Empty /etc/machine-id on read-only rootfs with /etc overlay

**Versions:** systemd 255.x (scarthgap ships 255.21)

**Symptom:** `pam_systemd.so` returns `PAM_SESSION_ERR` ("Cannot
make/remove an entry for the specified session"), blocking any
`PAMName=` service. logind is running but `/run/user/<uid>` is never
created. `/etc/machine-id` is 0 bytes.

**Root cause:** On a read-only rootfs, systemd PID 1 detects the empty
`/etc/machine-id` very early and bind-mounts a tmpfs over it to hold a
transient ID. Because the rootfs is read-only at that point, the tmpfs
inherits a read-only mount and PID 1 silently fails to write a transient
ID. Later, `etc.mount` overlays `/etc` with a writable overlayfs, but
the tmpfs on `/etc/machine-id` is stacked *above* the overlay:

```
/etc/machine-id  ←  tmpfs (ro, 0 bytes)  ←  VISIBLE
/etc             ←  overlay (rw)          ←  HIDDEN under tmpfs
```

`systemd-machine-id-commit.service` cannot help because the transient
ID was never generated. The machine-id stays empty forever, breaking
logind sessions, journald persistent logs, and the userdb
`add_nss_service()` code path (quirk #1).

**Fix:** A `machine-id-init.service` oneshot runs `After=etc.mount`. It
unmounts the stale tmpfs from `/etc/machine-id` (exposing the writable
overlay beneath), then calls `systemd-machine-id-setup` to generate and
persist a machine-id. The ID is written to the overlay upper dir, so it
survives reboots and is not overwritten by OTA rootfs updates.

**Files:**
- `layers/meta-appliance-os/recipes-core/etc-overlay/files/machine-id-init.service`
- `layers/meta-appliance-os/recipes-core/etc-overlay/etc-overlay_1.0.bb`

**On upgrade:** systemd 256+ changes the transient machine-id behavior
on read-only rootfs images. Re-evaluate whether PID 1 correctly handles
the case where an overlay makes `/etc` writable after initial mount. If
so, the service can be dropped.

---

## 3. GCC 13 parallel build race (aarch64 cross-compiler)

**Versions:** GCC 13.x (scarthgap ships 13.3)

**Symptom:** `gcc-cross` build fails intermittently with
undefined-reference errors when linking `cc1`/`cc1plus`. Auto-generated
source files (`insn-recog.cc`, `insn-output.cc`, etc.) aren't ready
when the linker runs.

**Root cause:** A Makefile dependency ordering bug in GCC 13's build
system that manifests under high parallelism on aarch64.

**Fix:** Limit `PARALLEL_MAKE` for the `gcc-cross` recipe:

```bitbake
PARALLEL_MAKE = "-j 2"
```

**Files:**
- `layers/meta-appliance-os/recipes-devtools/gcc/gcc-cross_%.bbappend`

**On upgrade:** GCC 14+ may fix this. Try removing the bbappend and
building with full parallelism. If it builds cleanly 3+ times, drop it.

---

## 4. meta-raspberrypi DT overlays missing from kernel 6.1

**Versions:** meta-raspberrypi scarthgap branch + meta-seeed-cm4
(pins kernel to 6.1.y)

**Symptom:** Build fails compiling DT overlays that don't exist in the
6.1 kernel source tree (Pi 5 overlays, newer DSI panel variants).

**Root cause:** meta-raspberrypi scarthgap's `rpi-base.inc` lists
overlays added after 6.1 for Pi 5 support. meta-seeed-cm4 pins the
kernel to 6.1.y.

**Fix:** Remove the incompatible overlays at layer.conf scope:

```bitbake
KERNEL_DEVICETREE:remove = " \
    overlays/vc4-kms-dsi-ili9881-7inch.dtbo \
    overlays/vc4-kms-dsi-ili9881-5inch.dtbo \
    overlays/w1-gpio-pi5.dtbo \
    overlays/bcm2712d0.dtbo \
"
```

**Files:**
- `layers/meta-appliance-bsp-reterminal/conf/layer.conf`

**On upgrade:** If the kernel moves to 6.6+ (or meta-seeed-cm4 unpins),
these sources will exist and the `:remove` can be dropped. Verify by
grepping the kernel tree for each `.dts` filename.

---

## 5. zsh license SPDX generation failure

**Versions:** meta-oe scarthgap (zsh recipe declares `LICENSE = "zsh"`)

**Symptom:** `do_create_spdx` fails with "Cannot find any text for
license zsh".

**Root cause:** Yocto's SPDX tooling requires a matching file in
`common-licenses/` for every declared license string. meta-oe's zsh
recipe uses a custom license identifier with no corresponding text file.

**Fix:** Map the license to the source tree's license file:

```bitbake
LICENSE = "MIT-like"
NO_GENERIC_LICENSE[MIT-like] = "LICENCE"
```

**Files:**
- `layers/meta-appliance-os/recipes-shells/zsh/zsh_%.bbappend`

**On upgrade:** Check if meta-oe fixes the license declaration upstream
(e.g., maps to `Zsh` SPDX identifier or provides a common-licenses
entry). If so, drop the bbappend.

---

## 6. meta-seeed-cm4 broken rpi-bootfiles download (404)

**Versions:** meta-seeed-cm4 (commit `a2f9438`)

**Symptom:** Build fails fetching `dt-blob-disp1-cam2.bin` from
`datasheets.raspberrypi.org` (permanently 404).

**Root cause:** The bbappend downloads a legacy `dt-blob.bin` binary
that is no longer hosted. `dt-blob.bin` is a pre-DT mechanism; the
reTerminal uses DT overlays.

**Fix:** BBMASK the broken bbappend:

```bitbake
BBMASK += "meta-seeed-cm4/recipes-bsp/bootfiles/rpi-bootfiles.bbappend"
```

**Files:**
- `layers/meta-appliance-bsp-reterminal/conf/layer.conf`

**On upgrade:** If meta-seeed-cm4 updates its bbappend to remove the
broken download (or if we move away from meta-seeed-cm4 entirely),
drop the BBMASK line.

---

## 7. meta-seeed-cm4 image bbappends override appliance config

**Versions:** meta-seeed-cm4 (commit `a2f9438`)

**Symptom:** Root password gets set, unwanted dev tools appear in image.

**Root cause:** meta-seeed-cm4 ships bbappends for `core-image-minimal`
and `core-image-base` that set passwords and install packages.

**Fix:** BBMASK both:

```bitbake
BBMASK += "meta-seeed-cm4/recipes-core/images/core-image-minimal.bbappend"
BBMASK += "meta-seeed-cm4/recipes-core/images/core-image-base.bbappend"
```

**Files:**
- `layers/meta-appliance-bsp-reterminal/conf/layer.conf`

**On upgrade:** Persists until meta-seeed-cm4 changes or we switch to a
custom image recipe (at which point the bbappends won't match).

---

## 8. seeed-linux-dtoverlays AUTOREV

**Versions:** meta-seeed-cm4 (commit `a2f9438`)

**Symptom:** Non-reproducible builds; fetches can fail if upstream
force-pushes.

**Root cause:** The upstream recipe uses `SRCREV = "${AUTOREV}"`.

**Fix:** Pin SRCREV in a bbappend:

```bitbake
SRCREV = "c336085a3a60a39afcc64fd784ec27dca71dbed2"
```

**Files:**
- `layers/meta-appliance-bsp-reterminal/recipes-kernel/seeed-linux-dtoverlays/seeed-linux-dtoverlays.bbappend`

**On upgrade:** Must be re-evaluated on every meta-seeed-cm4 or kernel
update. The SRCREV may need to move forward to pick up new fixes. The
AUTOREV policy is an upstream meta-seeed-cm4 problem, not Yocto-specific.

---

## Known bugs (not yet fixed)

### kas alphabetical block ordering breaks EXTRA_USERS_PARAMS

**Versions:** kas (any version)

**Symptom:** The `kiosk` user is never created.

**Root cause:** kas emits `local_conf_header` blocks alphabetically.
The `kiosk` block in `kas/common.yaml` uses `+=` to append a
`useradd` command to `EXTRA_USERS_PARAMS`, but the `utilities` block
uses bare `=` which overwrites the accumulated value. Since
`k` sorts before `u`, the kiosk useradd runs first, then gets clobbered.

**Fix needed:** Either rename blocks to control sort order, merge into a
single block, or switch the `utilities` block to `+=`.
