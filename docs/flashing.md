# Flashing

How to flash a built image to a device. The procedure depends on the
target's boot storage: a removable SD card can be written directly in
any card reader, while an embedded eMMC must be exposed to the host
over USB first (via `rpiboot`).

## Build output

`make build` automatically copies the flashable image to `artifacts/` at the repo root after a successful build. The `.wic.bz2` file is the compressed disk image, named `<variant>-<image>-<machine>.wic.bz2`. The flash commands below stream directly from the compressed file via `bzcat`, so there is no need to decompress first. Substitute your variant's artifact name for `<image>.wic.bz2`.

## Which method does my hardware use?

| Hardware | Boot storage | Method |
|---|---|---|
| Mycroft Mark II DevKit (Pi 4B + SJ201) | microSD card | [SD card](#flashing-to-an-sd-card) |
| Seeed reTerminal (CM4 with eMMC) | Onboard eMMC, no exposed SD slot | [Embedded eMMC via rpiboot](#flashing-to-embedded-emmc-rpiboot) |
| reTerminal with CM4 Lite swap | microSD via adapter | [SD card](#flashing-to-an-sd-card) |

## Flashing to an SD card

No special tooling. Insert the card into a reader on the host and write
the image.

### macOS

```bash
diskutil list                       # find the SD card, e.g. /dev/disk4
diskutil unmountDisk /dev/diskN
bzcat artifacts/<image>.wic.bz2 \
  | sudo dd of=/dev/rdiskN bs=4m status=progress
diskutil eject /dev/diskN
```

### Linux

```bash
lsblk                               # find the SD card, e.g. /dev/sdX
bzcat artifacts/<image>.wic.bz2 \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Then insert the card into the device and power on. For the Mycroft Mark
II DevKit, the microSD slot is on the Raspberry Pi 4 itself; see the
[teardown guide](https://blog.graywind.org/posts/mark2-teardown/) if the
enclosure blocks access to the slot.

> **Pi 4B boot order (EEPROM).** The Pi 4 chooses its boot device from the
> `BOOT_ORDER` value baked into the bootloader EEPROM, *independent of the
> flashed image*. A DevKit shipped to boot USB-first will show a blank
> screen with no card inserted and ignore a freshly flashed SD if a
> bootable USB stick is also attached. Inspect/change it from any booted
> OS with `rpi-eeprom-config --edit` (`0xf41` = SD\u2192USB, `0xf14` =
> USB\u2192SD). The Mark II DevKit has **no eMMC** \u2014 SD or USB only.

## Flashing to embedded eMMC (rpiboot)

Applies to CM4-based devices with onboard eMMC (e.g. the stock
reTerminal). The CM4 must be put into USB mass storage mode so the host
can write to the eMMC as a block device. This requires `rpiboot` on the
host and physical access to the boot-mode switch.

### Prerequisites

macOS:

```bash
brew install libusb pkg-config bzip2
```

Linux (Debian/Ubuntu):

```bash
sudo apt install libusb-1.0-0-dev pkg-config bzip2
```

`make rpiboot` will check for `libusb` and `pkg-config` and print an error if missing. `bzcat` (from `bzip2`) is needed to stream compressed images during flashing.

### Procedure

The boot-mode switch location is device-specific; the steps below name
the reTerminal's. Any CM4 carrier board has an equivalent `nRPI_BOOT`
switch or jumper (consult its documentation).

1. Power off the device.
2. Locate the boot-mode switch. On the reTerminal it is behind the back cover, near the CM4 module.
3. Flip the boot switch DOWN. This holds `nRPI_BOOT` low, telling the CM4 bootrom to skip eMMC and wait for USB.
4. Connect the device's USB-C port to your host machine.
5. Run rpiboot:

```bash
make rpiboot
```

This clones, builds (if needed), and runs `rpiboot` automatically. The CM4's eMMC will appear as a USB mass storage device when it completes.

6. Identify the eMMC device:

```bash
# macOS
diskutil list        # look for the new disk matching the eMMC size

# Linux
lsblk
```

7. Flash the image:

```bash
# macOS (replace N with the correct disk number)
diskutil unmountDisk /dev/diskN
bzcat artifacts/<image>.wic.bz2 \
  | sudo dd of=/dev/rdiskN bs=4m status=progress
diskutil eject /dev/diskN

# Linux (replace sdX with the correct device)
bzcat artifacts/<image>.wic.bz2 \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

8. Flip the boot switch back UP. This is mandatory. If the switch stays down, the CM4 will not boot from eMMC regardless of USB state.
9. Disconnect USB and power on.

## First boot

Power on and connect via serial console or SSH (if WiFi was pre-configured). The device boots into Weston (fullscreen Wayland compositor) and starts containerized application services. The display may remain blank until a container image is loaded for the first app.

Default serial console settings: 115200 8N1 on the debug UART (GPIO 14/15 via the 40-pin header, or the USB-C port if the debug firmware is installed).

Login as `root` with no password.

## Updating

After initial flash, subsequent updates are applied over-the-air via RAUC A/B slot switching, no reflashing required. See [OTA Updates](updates.md) for how to build and install update bundles.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `rpiboot` doesn't detect the device | Boot switch not flipped, or bad cable | Verify the switch is DOWN. Try a different USB-C cable (must support data, not charge-only). |
| `rpiboot` completes but no disk appears | macOS sometimes delays enumeration | Wait 10-15 seconds. Run `diskutil list` again. Try `sudo rpiboot -d mass-storage-gadget64` for the faster gadget path. |
| Boot hangs at rainbow screen | Kernel not loading | Check that the boot partition has the correct `config.txt` and kernel image. |
| No video output on DSI panel | Display driver not loaded | Check `dmesg` via serial console for `mipi_dsi` errors. Expected for early bring-up. |
| `dd` is very slow on macOS | Using `/dev/diskN` instead of `/dev/rdiskN` | Use the raw device (`rdiskN`) for unbuffered writes. |
| Forgot to flip boot switch back up | CM4 won't boot from eMMC | Flip the switch UP (on the reTerminal: behind the back cover). |
| SD card device boots old image | Wrote to the wrong disk, or card not fully ejected before removal | Re-check the device node with `diskutil list`/`lsblk`; always eject/sync before removing. |

## macOS gotchas

These apply to both SD card and eMMC flashing.

### Unmount before writing

macOS automounts FAT partitions immediately. If you `dd` while a
partition is mounted, the write can silently corrupt the ext4 rootfs
(FAT partition looks fine, rootfs is zeros). Always unmount first:

```bash
# Find the target device
diskutil list
# e.g. /dev/disk4

# Unmount all partitions on the disk
diskutil unmountDisk /dev/disk4

# Flash (use rdiskN for raw unbuffered writes)
bzcat artifacts/<image>.wic.bz2 \
  | sudo dd of=/dev/rdisk4 bs=4m status=progress

# Eject
diskutil eject /dev/disk4
```

### Use the raw device

`/dev/diskN` goes through the macOS buffer cache and is extremely slow.
Always use `/dev/rdiskN` instead. It's an order of magnitude faster.

### `strings` doesn't work on raw block devices

If you need to inspect a partition's contents (e.g. for debugging),
extract it to a file first:

```bash
sudo dd if=/dev/rdisk4s2 of=/tmp/rootfs.img bs=4M status=progress
strings /tmp/rootfs.img | grep something
```

## Verifying a flash

The first 1024 bytes of an ext4 partition are always zeros (boot block),
so a naive check of the partition start will look blank even on a good
flash. Verify the ext4 superblock at offset +1024, looking for magic bytes
`53ef` at +0x438:

```bash
sudo xxd -s 1024 -l 64 /dev/rdisk4s2 | grep 53ef
```

If this returns nothing, the rootfs partition wasn't written correctly.
