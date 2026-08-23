#!/bin/bash
# Run Endroid OS in QEMU for testing
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/../output"
UI_DIR="$SCRIPT_DIR/../ui"

echo "=== Running Endroid OS in QEMU ==="

# Check if output files exist
if [ ! -f "$OUTPUT_DIR/bzImage" ]; then
    echo "Error: bzImage not found. Run build-kernel.sh first."
    exit 1
fi

if [ ! -f "$OUTPUT_DIR/initramfs.cpio.gz" ]; then
    echo "Error: initramfs.cpio.gz not found. Run build-kernel.sh first."
    exit 1
fi

# Create a disk image for /data partition if it doesn't exist
DATA_DISK="$OUTPUT_DIR/data.img"
if [ ! -f "$DATA_DISK" ]; then
    echo "Creating data disk image..."
    qemu-img create -f qcow2 "$DATA_DISK" 1G
    # Format as ext4
    sudo mkfs.ext4 -F "$DATA_DISK"
fi

# Boot parameters
KERNEL_CMDLINE="console=ttyS0 root=/dev/ram0 rw init=/init"

echo "Booting QEMU..."
qemu-system-x86_64 \
    -kernel "$OUTPUT_DIR/bzImage" \
    -initrd "$OUTPUT_DIR/initramfs.cpio.gz" \
    -append "$KERNEL_CMDLINE" \
    -m 2048 \
    -cpu host \
    -enable-kvm \
    -serial stdio \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-gpu-pci \
    -device virtio-blk-pci,drive=data \
    -drive file="$DATA_DISK",format=qcow2,if=virtio \
    -display gtk,gl=on
