# Flashing

How to flash the built image to the reTerminal.

## Build output

`make build` automatically copies the flashable image to `artifacts/` at the repo root after a successful build. The `.wic.bz2` file is the compressed disk image. The flash commands below stream directly from the compressed file via `bzcat`, so there is no need to decompress first.

## SD card vs eMMC

The reTerminal ships with a CM4 module that has 32GB onboard eMMC. There is **no exposed microSD card slot** — the CM4 sits on a carrier board inside the enclosure.

| Method | When to use | Requires hardware access? |
|---|---|---|
| **eMMC via rpiboot** | Normal workflow. Writes directly to the onboard storage. | Yes — must open the back cover to flip the boot-mode switch. |
| **SD card (CM4 Lite only)** | Only if you have swapped the CM4 for a Lite variant (no eMMC) and added an SD card adapter. Not the stock configuration. | N/A |

For the stock reTerminal, **always use eMMC flashing**.

## Flashing to eMMC

The CM4 must be put into USB mass storage mode so the host can write to the eMMC as a block device. This requires `rpiboot` on the host and physical access to the boot-mode switch inside the enclosure.

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

1. **Power off** the reTerminal.
2. **Open the back cover** and locate the boot-mode switch (near the CM4 module).
3. **Flip the boot switch DOWN** — this holds `nRPI_BOOT` low, telling the CM4 bootrom to skip eMMC and wait for USB.
4. **Connect** the reTerminal's USB-C port to your host machine.
5. **Run rpiboot:**

```bash
make rpiboot
```

This clones, builds (if needed), and runs `rpiboot` automatically. The CM4's eMMC will appear as a USB mass storage device when it completes.

6. **Identify the eMMC device:**

```bash
# macOS
diskutil list        # look for the new ~29GB disk

# Linux
lsblk
```

7. **Flash the image:**

```bash
# macOS (replace N with the correct disk number)
diskutil unmountDisk /dev/diskN
bzcat artifacts/reterminal-hifi-core-image-minimal-seeed-reterminal.wic.bz2 \
  | sudo dd of=/dev/rdiskN bs=4m status=progress
diskutil eject /dev/diskN

# Linux (replace sdX with the correct device)
bzcat artifacts/reterminal-hifi-core-image-minimal-seeed-reterminal.wic.bz2 \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

8. **Flip the boot switch back UP.** This is mandatory — if the switch stays down, the CM4 will not boot from eMMC regardless of USB state.
9. **Disconnect USB** and power on.

## Flashing to SD card

Only applicable if you have a CM4 Lite variant with an SD card adapter. Write the `.wic` image to a microSD card:

### macOS

```bash
diskutil list
diskutil unmountDisk /dev/diskN
bzcat artifacts/reterminal-hifi-core-image-minimal-seeed-reterminal.wic.bz2 \
  | sudo dd of=/dev/rdiskN bs=4m status=progress
diskutil eject /dev/diskN
```

### Linux

```bash
lsblk
bzcat artifacts/reterminal-hifi-core-image-minimal-seeed-reterminal.wic.bz2 \
  | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

## First boot

Power on and connect a serial console. There is no graphical login yet — `core-image-minimal` provides a text console only.

Default serial console settings: **115200 8N1** on the debug UART (GPIO 14/15 via the 40-pin header, or the USB-C port if the debug firmware is installed).

Login as `root` with no password.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `rpiboot` doesn't detect the device | Boot switch not flipped, or bad cable | Verify the switch is DOWN. Try a different USB-C cable (must support data, not charge-only). |
| `rpiboot` completes but no disk appears | macOS sometimes delays enumeration | Wait 10–15 seconds. Run `diskutil list` again. Try `sudo rpiboot -d mass-storage-gadget64` for the faster gadget path. |
| Boot hangs at rainbow screen | Kernel not loading | Check that the boot partition has the correct `config.txt` and kernel image. |
| No video output on DSI panel | Display driver not loaded | Check `dmesg` via serial console for `mipi_dsi` errors. Expected for early bring-up. |
| `dd` is very slow on macOS | Using `/dev/diskN` instead of `/dev/rdiskN` | Use the raw device (`rdiskN`) for unbuffered writes. |
| Forgot to flip boot switch back up | CM4 won't boot from eMMC | Open the back cover and flip the switch UP. |

## macOS gotchas

### Unmount before writing

macOS automounts FAT partitions immediately. If you `dd` while a
partition is mounted, the write can silently corrupt the ext4 rootfs
(FAT partition looks fine, rootfs is zeros). Always unmount first:

```bash
# Find the eMMC device
diskutil list
# Look for the ~29GB disk, e.g. /dev/disk4

# Unmount all partitions on the disk
diskutil unmountDisk /dev/disk4

# Flash (use rdiskN for raw unbuffered writes)
bzcat artifacts/reterminal-hifi-core-image-minimal-seeed-reterminal.wic.bz2 \
  | sudo dd of=/dev/rdisk4 bs=4m status=progress

# Eject
diskutil eject /dev/disk4
```

### Use the raw device

`/dev/diskN` goes through the macOS buffer cache and is extremely slow.
Always use `/dev/rdiskN` instead — it's an order of magnitude faster.

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
flash. Verify the ext4 superblock at offset +1024 — look for magic bytes
`53ef` at +0x438:

```bash
sudo xxd -s 1024 -l 64 /dev/rdisk4s2 | grep 53ef
```

If this returns nothing, the rootfs partition wasn't written correctly.
