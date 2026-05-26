# Flashing

How to extract build artifacts from the container and flash them to the reTerminal.

## Extracting the image

`make build` automatically copies the flashable image to `artifacts/` at the repo root after a successful build. The `.wic.bz2` file is the compressed disk image.

Decompress it:

```bash
bunzip2 artifacts/core-image-minimal-seeed-reterminal.rootfs.wic.bz2
```

## Flashing to SD card

Write the `.wic` image to a microSD card. Replace `/dev/diskN` with the correct device.

### macOS

```bash
# Identify the SD card
diskutil list

# Unmount (do NOT eject)
diskutil unmountDisk /dev/diskN

# Flash (use rdiskN for raw device — much faster)
sudo dd if=artifacts/core-image-minimal-seeed-reterminal.rootfs.wic of=/dev/rdiskN bs=4m status=progress

# Eject
diskutil eject /dev/diskN
```

### Linux

```bash
# Identify the SD card
lsblk

# Flash
sudo dd if=artifacts/core-image-minimal-seeed-reterminal.rootfs.wic of=/dev/sdX bs=4M status=progress conv=fsync

# Sync and remove
sync
```

## Flashing to eMMC

The reTerminal's CM4 has 32GB onboard eMMC. To flash directly to eMMC, the CM4 must be put into USB mass storage mode using `rpiboot`.

### Prerequisites

Install `rpiboot` on the host:

```bash
# macOS
brew install rpiboot

# Linux (Debian/Ubuntu)
sudo apt install rpiboot
```

### Procedure

1. **Power off** the reTerminal.
2. **Open the back cover** and locate the Boot mode switch (near the CM4 module).
3. **Flip the boot switch** to the "disable eMMC boot" position (this forces USB boot).
4. **Connect** the reTerminal's USB-C port to your host machine.
5. **Run rpiboot:**

```bash
sudo rpiboot
```

The CM4's eMMC will appear as a USB mass storage device (e.g., `/dev/diskN` on macOS, `/dev/sdX` on Linux).

6. **Flash** using the same `dd` commands above, targeting the eMMC device.
7. **Flip the boot switch back** to the normal position.
8. **Disconnect USB** and power on.

## First boot

Insert the SD card (or, if you flashed eMMC, just power on) and connect a serial console or HDMI monitor.

Default serial console settings: **115200 8N1** on the debug UART (GPIO 14/15 via the 40-pin header, or the USB-C port if the debug firmware is installed).

The system boots to a login prompt. Default credentials depend on the image — `core-image-minimal` typically uses `root` with no password.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| No video output | Display rotation not configured | Expected for `core-image-minimal` (no GUI). Use serial console. |
| Boot hangs at rainbow screen | Kernel not loading | Check that the boot partition has the correct `config.txt` and kernel image. |
| `rpiboot` doesn't detect the device | Boot switch not flipped | Verify the switch position. Try a different USB cable (must support data). |
| `dd` is very slow on macOS | Using `/dev/diskN` instead of `/dev/rdiskN` | Use the raw device (`rdiskN`) for unbuffered writes. |
