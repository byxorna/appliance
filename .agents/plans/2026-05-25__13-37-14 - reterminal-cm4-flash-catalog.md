# reTerminal CM4 Flash Catalog

Reference doc cataloging the working flash procedure for the Seeed Studio reTerminal (CM4-based, model 102991299) from an Apple Silicon Mac. Captures exact software versions, commits, and observed output from a successful end-to-end flash. Companion to `2026-05-23__18-02-43 - reterminal-feishin-appliance.md`.

## Target Hardware

- Seeed Studio reTerminal, model 102991299
- Compute Module: Raspberry Pi CM4 (with eMMC, not Lite)
- Boot-mode selector: physical slide switch on carrier PCB (not jumper, not solder bridge)
  - Switch DOWN = nRPI_BOOT held low, CM4 bootrom skips eMMC and waits on USB device port
  - Switch UP = normal eMMC boot
- No external boot button or pinhole. Disassembly required for every flash.
- USB-C is the only data+power path that works for rpiboot. USB-A ports on the reTerminal are wired to the CM4 USB host controller and cannot be used as the rpiboot device interface.

## Host Environment

macOS host used for this flash:

- macOS 15.7.5, build 24G624
- arm64 (Apple Silicon)
- Homebrew prefix `/opt/homebrew` (matters: arm64 libusb already available, no source build needed)
- Apple clang 17.0.0 (clang-1700.6.4.2), target `arm64-apple-darwin24.6.0`
- Command Line Tools only (no full Xcode). `make` works via clang; `xcodebuild` is unavailable but not needed.

## Software Versions

### Homebrew packages

| package | version |
|---|---|
| libusb | 1.0.29 |
| pkgconf (provides `pkg-config`) | 2.5.1 |

Installed with:

```
brew install libusb pkg-config
```

On Apple Silicon Homebrew (`/opt/homebrew`), libusb is already arm64. The usbboot README's "compile libusb from source" workaround only applies to Intel Homebrew installs at `/usr/local`.

### usbboot

Repo: `https://github.com/raspberrypi/usbboot`

Clone command:

```
git clone --recurse-submodules --shallow-submodules --depth=1 https://github.com/raspberrypi/usbboot
```

Local clone path used: `~/tmp/reterminal-flash/usbboot`

Commits at time of flash:

- usbboot top-level: `42ca50932f67f4571951a11da3c3161561cb49c2` (2026-05-21, "rpi-eeprom: Update submodule dependency for rpi-eeprom-config A/B updates")
- `rpi-eeprom` submodule: `25f837ab8009a643ed85b9aad94d911baddaf0c4` (2026-05-21, "rpi-eeprom-update: Check RPI_EEPROM_IMMEDIATE_UPDATE after initialised")

Built with plain `make` (no extra env vars). Resulting binary at `~/tmp/reterminal-flash/usbboot/rpiboot`:

- Mach-O 64-bit arm64
- 768440 bytes
- Embedded build strings: `GIT_VER="42ca5093"`, `PKG_VER="local"`, `BUILD_DATE="2026/05/25"`, `DEFAULT_MSG_DIR="/usr/share/rpiboot/mass-storage-gadget64/"`

### Raspberry Pi Imager

- Version 2.0.8
- Path: `/Applications/Raspberry Pi Imager.app`

### OS written to eMMC

- Raspberry Pi OS Lite, 64-bit, Bookworm
- Selected through Raspberry Pi Imager's OS picker
- Advanced options (Cmd+Shift+X) used to preset hostname, enable SSH with public key, configure Wi-Fi and locale before writing

## Procedure (Working Sequence)

1. Disassemble reTerminal. Peel 4 rear rubber feet, remove 4 screws, lift back shell. Remove 2 heatsink screws, lift heatsink. Front panel stays attached; do not pry it.
2. Flip the boot-mode switch on the carrier PCB DOWN. Asserts nRPI_BOOT low.
3. On the Mac, clone and build usbboot:
   ```
   mkdir -p ~/tmp/reterminal-flash && cd ~/tmp/reterminal-flash
   git clone --recurse-submodules --shallow-submodules --depth=1 https://github.com/raspberrypi/usbboot
   cd usbboot
   brew install libusb pkg-config
   make
   ```
4. Connect USB-C from reTerminal to a powered Mac USB port directly. No charge-only cables. No underpowered hubs (they silently fail to enumerate).
5. Run rpiboot:
   ```
   sudo ~/tmp/reterminal-flash/usbboot/rpiboot -d mass-storage-gadget64
   ```
   The `-d mass-storage-gadget64` variant is faster than the legacy MSD directory and is the current recommended path. It ships firmware over the USB device PHY, then the CM4 re-enumerates its eMMC as a USB mass storage device on the host.
6. Confirm eMMC appeared:
   ```
   diskutil list external
   ```
   Expect a new external disk (was `/dev/disk4` on this run). macOS may pop up "The disk you inserted was not readable" — click Ignore. This is normal for the factory ext4 partition.
7. Open Raspberry Pi Imager. Cmd+Shift+X for advanced options. Set hostname, SSH key, Wi-Fi, locale. Choose OS: Raspberry Pi OS Lite 64-bit (Bookworm). Choose storage: the eMMC disk. Write. Wait for verification to complete.
8. After write+verify, eMMC unmounts. Verify:
   ```
   diskutil list external
   ```
   No external disks should remain.
9. Unplug USB-C.
10. Flip the boot-mode switch back UP. Mandatory. Switch still down means nRPI_BOOT stays low and CM4 will not boot from eMMC on power-up regardless of USB state.
11. Reassemble heatsink (2 screws) and back shell (4 screws + 4 rubber feet).
12. Apply 5V/3A USB-C power. First boot expands the root filesystem and applies imager advanced-options config. Wait 60-90 seconds.
13. SSH from the Mac:
    ```
    ssh <user>@<hostname>.local
    ```
    Blank screen on the reTerminal LCD is expected on stock Pi OS (no Seeed LCD/touch overlays installed yet). Successful SSH login confirms the flash pipeline end-to-end.

## Expected vs Observed Output

### rpiboot expected output

The repo prints build banner, advises the EMMC_DISABLE/nRPIBOOT jumper, then loads bootfiles, bootcode, second-stage boot server, memsys blobs, config.txt, and boot.img. Final line is `Second stage boot server done`.

### rpiboot observed output (verbatim)

```
RPIBOOT: build-date 2026/05/25 pkg-version local 42ca5093
Please fit the EMMC_DISABLE / nRPIBOOT jumper before connecting the power and USB cables to the target device.
If the device fails to connect then please see https://rpltd.co/rpiboot for debugging tips.
Loading: mass-storage-gadget64/bootfiles.bin
Using mass-storage-gadget64/bootfiles.bin
Waiting for BCM2835/6/7/2711/2712...
Sending bootcode.bin
Successful read 4 bytes
Waiting for BCM2835/6/7/2711/2712...
Second stage boot server
File read: mcb.bin
File read: memsys00.bin
File read: memsys01.bin
File read: memsys02.bin
File read: memsys03.bin
File read: memsys04.bin
File read: memsys05.bin
File read: memsys06.bin
File read: memsys07.bin
File read: memsys08.bin
File read: bootmain
Loading: mass-storage-gadget64/config.txt
File read: config.txt
Loading: mass-storage-gadget64/boot.img
File read: boot.img
Second stage boot server done
```

Matches expected output. The "jumper" wording in the banner refers generically to the nRPI_BOOT pull; on the reTerminal the equivalent is the carrier-PCB slide switch in the DOWN position.

### diskutil list external observed output

After rpiboot finished, before the Imager write:

```
/dev/disk4 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:     FDisk_partition_scheme                        *31.3 GB    disk4
   1:             Windows_FAT_32 boot                    268.4 MB   disk4s1
   2:                      Linux                         31.0 GB    disk4s2
```

268.4 MB FAT32 boot partition + 31.0 GB Linux ext4 partition is the factory Pi OS image shipped on this reTerminal. The Imager overwrites both during write.

After write+verify+unmount:

```
(empty; command returns no external physical disks)
```

This is the expected post-write state and confirms macOS has released the device. Safe to unplug USB-C.

## Constraints, Gotchas, References

- Apple Silicon Homebrew already ships arm64 libusb. Skip the usbboot README's libusb-from-source step unless on Intel Homebrew at `/usr/local`.
- USB-A ports on the reTerminal are CM4 host ports. They cannot serve as the rpiboot device interface. Use the USB-C port only.
- Underpowered USB-C sources (some hubs, some monitor downstream ports) silently fail to enumerate the rpiboot device. Use a direct Mac USB-C port or a powered hub.
- Boot switch direction is well-documented:
  - CM4 datasheet: nRPI_BOOT low at power-on routes to USB boot
  - Seeed wiki reTerminal flashing steps: switch is described as "flip down" for rpiboot mode
  - Raspberry Pi cm-emmc-flashing documentation
  - Alex Whittemore's CM4 carrier reference posts
- Blank screen on stock Pi OS post-flash is expected. The reTerminal's LCD and capacitive touch require `seeed-linux-dtoverlays` (installed in the appliance phase, not here).
- First-boot delay is normal: filesystem expansion + cloud-init-style firstboot from Imager advanced options runs before SSH comes up.
- If `ssh <host>.local` fails, mDNS may be the culprit. Fall back to scanning the LAN for the new IP (`arp -a` or router DHCP table).

## Companion docs

- `2026-05-23__18-02-43 - reterminal-feishin-appliance.md` — full appliance build plan that consumes this flashed base image (kiosk, Feishin, Seeed overlays, audio, LEDs).
- `2026-05-23__16-45-00 - appliance-image-research.md` — earlier research on which Pi OS variant to base the appliance on.
