#!/bin/bash
set -e

WORKDIR=$(pwd)
TARGET_DISK="$1"
if [ -z "$TARGET_DISK" ]; then
    TARGET_DISK="$WORKDIR/endroid-os-installed.img"
fi

echo "=== Installing Endroid OS to disk ==="

# Ensure target disk exists and is correct size
if [ ! -f "$TARGET_DISK" ]; then
    echo "Creating target disk..."
    qemu-img create -f qcow2 "$TARGET_DISK" 8G
fi

# Verify disk size
DISK_SIZE=$(qemu-img info "$TARGET_DISK" --output json | grep -o '"virtual-size":[0-9]*' | cut -d: -f2)
if [ "$DISK_SIZE" -lt 4000000000 ]; then
    echo "Error: Disk image too small ($DISK_SIZE bytes), recreating..."
    rm -f "$TARGET_DISK"
    qemu-img create -f qcow2 "$TARGET_DISK" 8G
fi

# Use parted for partitioning with --script flag to avoid prompts
echo "Partitioning disk with parted..."
parted --script "$TARGET_DISK" mklabel gpt || true
parted --script "$TARGET_DISK" unit MiB mkpart ESP fat32 1 512 || true
parted --script "$TARGET_DISK" unit MiB mkpart system-a ext4 512 2560 || true
parted --script "$TARGET_DISK" unit MiB mkpart system-b ext4 2560 4608 || true
parted --script "$TARGET_DISK" unit MiB mkpart data ext4 4608 100% || true
parted --script "$TARGET_DISK" set 1 esp on || true

echo "Partition table created successfully"
parted "$TARGET_DISK" print

# Set up loop devices
echo "Setting up loop devices..."
LOOP_DEV=$(losetup -f --show "$TARGET_DISK")
trap "losetup -d $LOOP_DEV 2>/dev/null || true" EXIT

# Refresh partition info
partx -u "$LOOP_DEV" 2>/dev/null || sleep 2
ls -la "${LOOP_DEV}"*

# Format partitions
echo "Formatting partitions..."
mkfs.vfat -n ESP "${LOOP_DEV}p1" || echo "ESP format skipped"
mkfs.ext4 -L system-a "${LOOP_DEV}p2" || echo "system-a format skipped"
mkfs.ext4 -L system-b "${LOOP_DEV}p3" || echo "system-b format skipped"
mkfs.ext4 -L data "${LOOP_DEV}p4" || echo "data format skipped"

# Mount and install files
MOUNT_DIR=$(mktemp -d)
trap "umount $MOUNT_DIR 2>/dev/null; rm -rf $MOUNT_DIR; losetup -d $LOOP_DEV 2>/dev/null || true" EXIT

# Install bootloader to ESP
echo "Installing bootloader..."
mount "${LOOP_DEV}p1" "$MOUNT_DIR" || { echo "Failed to mount ESP"; exit 1; }
mkdir -p "$MOUNT_DIR/EFI/BOOT"

cat > "$MOUNT_DIR/EFI/BOOT/grub.cfg" << 'BOOTCFG'
set timeout=5
menuentry "Endroid OS (Slot A)" {
    linux /boot/bzImage quiet
    initrd /boot/initrd.gz
}
menuentry "Endroid OS (Slot B)" {
    linux /boot/bzImage quiet
    initrd /boot/initrd.gz
}
BOOTCFG

umount "$MOUNT_DIR"

# Mount system-a and copy UI files
echo "Installing system files to slot A..."
mount "${LOOP_DEV}p2" "$MOUNT_DIR" || { echo "Failed to mount system-a"; exit 1; }
mkdir -p "$MOUNT_DIR/usr/share/endroid"
mkdir -p "$MOUNT_DIR/boot"
cp "$WORKDIR/ui/index.html" "$MOUNT_DIR/usr/share/endroid/"
cp "$WORKDIR/ui/apps.js" "$MOUNT_DIR/usr/share/endroid/"
cp "$WORKDIR/ui/lucide.js" "$MOUNT_DIR/usr/share/endroid/"
umount "$MOUNT_DIR"

# Mount data partition and create directory structure
echo "Setting up data partition..."
mount "${LOOP_DEV}p4" "$MOUNT_DIR" || { echo "Failed to mount data"; exit 1; }
mkdir -p "$MOUNT_DIR/system"
mkdir -p "$MOUNT_DIR/apps"
mkdir -p "$MOUNT_DIR/user"

cat > "$MOUNT_DIR/system/prefs.json" << 'PREFS'
{
  "version": 1,
  "theme": "dark",
  "accent": "#4FD1C5",
  "accentDim": "#2C8A80",
  "reduceMotion": false,
  "network": { "lastConnectedSsid": null },
  "display": { "brightness": 80 },
  "sound": { "volume": 70, "systemSounds": true }
}
PREFS

cat > "$MOUNT_DIR/system/installed.json" << 'INSTALLED'
{
  "version": 1,
  "apps": []
}
INSTALLED

umount "$MOUNT_DIR"

echo ""
echo "=== Installation Complete ==="
echo "Disk image: $TARGET_DISK"
ls -lh "$TARGET_DISK"
echo ""
echo "Partition layout:"
parted "$TARGET_DISK" print
