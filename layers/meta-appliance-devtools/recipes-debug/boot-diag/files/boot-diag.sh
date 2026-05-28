#!/bin/sh
# Dump early-boot diagnostics. Tries to write to the FAT boot partition
# (found by label or device), and always writes to /var/log/ as fallback.

LOG_CONTENT=""
collect() {
    LOG_CONTENT="$LOG_CONTENT
=== $1 ===
$(eval "$2" 2>&1)
"
}

collect "boot-diag timestamp" "date"
collect "hostname" "hostname"
collect "ip addr" "ip addr"
collect "systemctl status sshd.socket" "systemctl status sshd.socket"
collect "systemctl status sshdgenkeys.service" "systemctl status sshdgenkeys.service"
collect "journalctl -u sshd.socket" "journalctl -u sshd.socket --no-pager -n 30"
collect "journalctl -u sshdgenkeys.service" "journalctl -u sshdgenkeys.service --no-pager -n 30"
collect "journalctl -u sshd@*" "journalctl -u 'sshd@*' --no-pager -n 30"
collect "ss -tlnp" "ss -tlnp"
collect "ls /etc/ssh/" "ls -la /etc/ssh/"
collect "sshd_config" "grep -v '^#' /etc/ssh/sshd_config | grep -v '^$'"
collect "failed units" "systemctl --failed"
collect "dmesg tail" "dmesg | tail -50"
collect "block devices" "cat /proc/partitions"
collect "mounts" "cat /proc/mounts"
collect "blkid" "blkid"

# Always write to rootfs (readable via strings on ext4 partition)
echo "$LOG_CONTENT" > /var/log/boot-diag.log

# Try to write to boot partition -- try multiple strategies
BOOT_MOUNTED=""
for dev in /dev/mmcblk0p1 /dev/mmcblk1p1 /dev/mmcblk2p1; do
    [ -b "$dev" ] || continue
    MOUNT_POINT="/run/boot-diag-mnt"
    mkdir -p "$MOUNT_POINT"
    if mount -t vfat "$dev" "$MOUNT_POINT" 2>/dev/null; then
        echo "$LOG_CONTENT" > "$MOUNT_POINT/boot-diag.log"
        sync
        umount "$MOUNT_POINT"
        BOOT_MOUNTED="$dev"
        break
    fi
done

# Also try by label
if [ -z "$BOOT_MOUNTED" ] && [ -e /dev/disk/by-label/boot ]; then
    MOUNT_POINT="/run/boot-diag-mnt"
    mkdir -p "$MOUNT_POINT"
    if mount -t vfat /dev/disk/by-label/boot "$MOUNT_POINT" 2>/dev/null; then
        echo "$LOG_CONTENT" > "$MOUNT_POINT/boot-diag.log"
        sync
        umount "$MOUNT_POINT"
    fi
fi

rmdir /run/boot-diag-mnt 2>/dev/null
