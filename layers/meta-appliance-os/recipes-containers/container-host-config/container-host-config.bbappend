# Override container storage to use the persistent /data partition.
# The rootfs is read-only, so container images must live on writable storage
# that survives A/B rootfs updates.

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
