# Flash Workflow Improvements

## Goal
Streamline the flash + debug cycle with Makefile targets, so the workflow
is `make flash` instead of manual `bzcat | dd` and `rpiboot` invocations.

## Planned Targets

### `make flash`
- Takes `DISK=` parameter (e.g. `make flash DISK=/dev/sdX`)
- Decompresses and writes the latest `$(BUILD)-$(IMAGE)-$(MACHINE).wic.bz2`
  from `artifacts/` to the target device
- Safety: require explicit `DISK=`, refuse to run without it
- Print a confirmation prompt with device info before writing

### `make rpiboot`
- Containerized `rpiboot` so the host doesn't need it installed
- Build a minimal container image (or use an existing one) with `rpiboot`
  binary
- Needs USB device passthrough (`--device` flag for podman/docker)
- macOS caveat: USB passthrough to podman machine may need extra config
  (Lima / QEMU USB forwarding) -- investigate feasibility

### `make boot-diag`
- Convenience target: mount FAT partition from rpiboot mass-storage device,
  cat `boot-diag.log`, unmount
- Depends on `make rpiboot` having exposed the eMMC

## Open Questions
- Is containerized rpiboot practical on macOS with podman? USB device
  passthrough through the podman VM may be unreliable. Might need a
  native `brew install rpiboot` fallback.
- Should `make flash` invoke `rpiboot` first, or keep them separate?
- Consider adding `make serial` if a USB-UART adapter is ever connected.
