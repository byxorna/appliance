# OTA Updates

The appliance uses [RAUC](https://rauc.io/) for atomic A/B rootfs updates. The eMMC has two rootfs slots (A and B). Updates are installed to the inactive slot; on reboot, U-Boot switches to it. If the new slot fails to boot three times, U-Boot automatically rolls back to the previous slot.

## How it works

1. U-Boot reads `BOOT_ORDER` and per-slot attempt counters (`BOOT_A_LEFT`, `BOOT_B_LEFT`) from its environment.
2. On each boot, it picks the first slot with attempts remaining and decrements the counter.
3. After a successful boot, `appliance-mark-good.service` calls `rauc status mark-good`, which resets the counter and confirms the slot.
4. If mark-good never runs (crash, hang, critical service failure), the counter reaches zero and U-Boot falls back to the other slot on the next reboot.

## Checking slot status

On the target device:

```bash
rauc status
```

This shows which slot is active (booted), whether it is marked good, and the version installed in each slot.

## Building an update bundle

The update bundle is a signed `.raucb` file containing an ext4 rootfs image.

### From the host

```bash
make VARIANT=reterminal-hifi build-update
```

This builds the bundle and copies it to `artifacts/`. The image must already be built (`make build`) since the bundle embeds the rootfs ext4.

### From a kas shell

If you're already inside `make kas-shell`:

```bash
bitbake update-bundle
```

### Output

The bundle appears at:

```
artifacts/<variant>-<image>-<machine>.raucb
```

Inside the container, the raw artifact is at `build/tmp/deploy/images/<machine>/update-bundle-<machine>.raucb`. For the reTerminal, `<machine>` is `seeed-reterminal`.

### Bundle metadata

The bundle version and description are set automatically:

| Field | Value | Source |
|---|---|---|
| `compatible` | `seeed-reterminal` | `MACHINE` (must match target's `/etc/rauc/system.conf`) |
| `version` | distro version (e.g. `0.1.0`) | `DISTRO_VERSION` via `update-bundle.bbappend` |
| `description` | `Appliance OS <variant> update for <machine>` | `APPLIANCE_VARIANT` + `MACHINE` |

### Signing

Bundles are signed with the development keypair from `meta-rauc-community`. These keys are **not suitable for production** — any device flashed with the dev CA certificate will accept bundles signed by anyone with access to the same public dev key.

Before shipping to real devices, generate a production keypair and override `RAUC_KEY_FILE` / `RAUC_CERT_FILE` in the bundle recipe.

## Installing an update

Copy the `.raucb` file to the target device (e.g. via `scp` to `/tmp`), then install it:

```bash
rauc install /tmp/update-bundle-seeed-reterminal.raucb
```

RAUC writes the rootfs image to the inactive slot, updates U-Boot's environment to boot from it, and sets the attempt counter. The active (running) slot is never modified.

Reboot to activate:

```bash
reboot
```

After reboot, verify the new slot is active:

```bash
rauc status
```

If the system booted successfully, `appliance-mark-good.service` will have already marked the slot as good. Confirm with:

```bash
systemctl status appliance-mark-good.service
```

## Rollback

Rollback is automatic. If the new slot fails to reach `multi-user.target` three times in a row (the mark-good service never runs), U-Boot exhausts the slot's attempt counter and reverts to the previous slot.

To manually force a rollback without waiting for three failed boots:

```bash
# From a serial console or recovery shell on the failing slot:
rauc status mark-bad
reboot
```

## Partition layout reference

The 5-partition eMMC layout used by the A/B update system:

| Partition | Device | Mount | Type | Size | Purpose |
|---|---|---|---|---|---|
| 1 | mmcblk0p1 | `/boot` | vfat | 128M | RPi firmware, U-Boot, config.txt, DTB overlays |
| 2 | mmcblk0p2 | `/` | ext4 | auto | Rootfs slot A (read-only) |
| 3 | mmcblk0p3 | `/` | ext4 | auto | Rootfs slot B (read-only) |
| 4 | mmcblk0p4 | — | — | — | MBR extended container |
| 5 | mmcblk0p5 | `/data` | ext4 | 1G | Persistent platform and app data |
| 6 | mmcblk0p6 | `/home` | ext4 | 500M+ | User home dirs (grows to fill eMMC) |

Slots A and B are identically sized. Only the inactive slot is written during an update — the running system is never modified. `/data` and `/home` survive updates.
