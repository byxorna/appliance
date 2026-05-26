# Firstboot Provisioning Service

**Goal**: A systemd service (`kiosk-firstboot`) that applies install-time configuration
from the boot FAT partition on first boot, covering WiFi, hostname, SSH keys, and timezone.
Runs once, deletes consumed config files, and disables itself.

## Requirements

1. After flashing a `.wic` image, the user can mount the boot FAT partition on any OS
   and drop config files before first boot — no special tooling required.
2. Config files are plain-text, one concern per file, easy to create by hand or script.
3. The service runs early (before NetworkManager, before kiosk-shell) on first boot only.
4. Consumed config files are deleted from the boot partition after processing.
5. If no config files are present, the service is a no-op (the on-device touch flow
   handles WiFi provisioning instead — see private plan "First-time WiFi provisioning").
6. The same mechanism serves as the recovery/headless escape hatch when the touch UI
   is unreachable.

## Detailed Implementation Plan + Reasoning

### Config file format

Files live at the root of the boot FAT partition (`/boot/firmware/` or wherever
the firmware partition is mounted). Each file is optional:

| File | Format | Purpose |
|------|--------|---------|
| `wifi.conf` | `ssid=...\npsk=...\nhidden=true\npriority=N` | WiFi credentials |
| `hostname` | Single line, plain text | Set system hostname |
| `ssh_authorized_keys` | Standard `authorized_keys` format | Root/builder SSH access |
| `timezone` | IANA tz string, e.g. `America/New_York` | System timezone |

**Why not a single YAML/JSON file?** Individual files are easier to create from any OS
(echo a line into a file vs. getting YAML indentation right on a phone). They're also
independently optional — drop just `wifi.conf` if that's all you need.

**Why not rpi-imager `custom.toml`?** rpi-imager's format is tightly coupled to
Raspberry Pi OS's firstrun service and userconf hooks. Parsing it gains compatibility
with rpi-imager's GUI but adds complexity for a format we don't fully control. We can
add rpi-imager compat as a future enhancement (parse `custom.toml` if present).

### Boot partition mount point

The RPi firmware partition is mounted read-only by default on Yocto/meta-raspberrypi.
`kiosk-firstboot` remounts it read-write to delete consumed files, then remounts
read-only when done. The mount point is `/boot/firmware` (or `/boot` depending on
meta-raspberrypi version — the service checks both).

### Service ordering

```
[Unit]
Description=Kiosk firstboot provisioning
DefaultDependencies=no
Before=NetworkManager.service systemd-hostnamed.service
After=local-fs.target
ConditionPathExists=/boot/firmware/wifi.conf
# Also trigger on any other config file:
# ConditionPathExistsGlob would be nice but doesn't exist.
# Use a wrapper script that checks for any config file presence.
```

Actually, since `ConditionPathExists` is a single file, the service script itself
checks for any of the config files and exits 0 immediately if none are found.
The service is `Type=oneshot` with `RemainAfterExit=no`.

**First-boot-only semantics:** The service always runs (it's enabled in the image),
but is a fast no-op when no config files exist. After first boot, the config files
are deleted, so subsequent boots skip processing. This is simpler and more robust
than a "ran once" stamp file — if the user re-drops config files later (e.g., to
change WiFi), the service picks them up on next reboot.

### Processing logic (`kiosk-firstboot.sh`)

```
1. Check if any config files exist on the boot partition. Exit 0 if none.
2. Remount boot partition read-write.
3. For each config file found:
   a. wifi.conf → parse key=value lines, write NetworkManager keyfile to
      /data/platform/network/system-connections/, chmod 600
   b. hostname → write to /etc/hostname (bind-mount from /data/platform/hostname
      on read-only rootfs), call hostnamectl
   c. ssh_authorized_keys → mkdir -p /data/platform/ssh/, copy file,
      ensure sshd_config points AuthorizedKeysFile at this path
   d. timezone → timedatectl set-timezone or symlink /etc/localtime
4. Delete each processed config file from the boot partition.
5. Remount boot partition read-only.
6. Exit 0.
```

### Persistent data integration

All config lands in `/data/platform/` (the persistent partition that survives RAUC
updates), not in the read-only rootfs. The rootfs has bind-mount units or symlinks
for paths like `/etc/hostname` and `/etc/localtime` that point into `/data/platform/`.

### Recipe structure

```
meta-kiosk-os/
  recipes-core/kiosk-firstboot/
    kiosk-firstboot.bb
    files/
      kiosk-firstboot.sh
      kiosk-firstboot.service
```

The recipe installs the script to `/usr/libexec/kiosk-firstboot.sh` and enables
the systemd service via `SYSTEMD_SERVICE`.

### Future enhancements (not in scope now)

- Parse rpi-imager `custom.toml` for GUI-based provisioning compat
- On-device touch WiFi provisioning (kiosk-shell first-time setup mode)
- QR-code scanning for WiFi creds via the DSI touchscreen camera (if present)
- USB stick provisioning (read config from removable media)

## Task List

- [ ] Create `meta-kiosk-os/recipes-core/kiosk-firstboot/files/kiosk-firstboot.sh`
- [ ] Create `meta-kiosk-os/recipes-core/kiosk-firstboot/files/kiosk-firstboot.service`
- [ ] Create `meta-kiosk-os/recipes-core/kiosk-firstboot/kiosk-firstboot.bb`
- [ ] Add bind-mount units for `/etc/hostname` → `/data/platform/hostname` (or defer to Phase 8)
- [ ] Test with config files on boot partition (requires hardware — Phase 2+)
- [ ] Document config file format in `docs/provisioning.md`

## Dependencies

- Requires the `/data` persistent partition (Phase 7/8 — RAUC partition layout)
- Requires NetworkManager (Phase 1 — included in `core-image-minimal` with systemd)
- Can be implemented as a recipe now but only fully testable on hardware (Phase 2+)

## Scheduling

The recipe skeleton can land alongside the `kiosk-os` distro conf in Phase 1.
Full integration and testing is Phase 8 (Persistent data) per the roadmap.
