#!/bin/bash
# Run the Endroid OS installer in QEMU
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/../output"
INSTALLER_DIR="$SCRIPT_DIR/../installer"

echo "=== Running Endroid OS Installer in QEMU ==="

ISO_FILE="$OUTPUT_DIR/endroid-installer.iso"

if [ ! -f "$ISO_FILE" ]; then
    echo "Error: Installer ISO not found. Run build-iso.sh first."
    exit 1
fi

# Create a blank disk for installation
INSTALL_DISK="$OUTPUT_DIR/install-target.qcow2"
qemu-img create -f qcow2 "$INSTALL_DISK" 20G

echo "Booting installer in QEMU..."
qemu-system-x86_64 \
    -cdrom "$ISO_FILE" \
    -hda "$INSTALL_DISK" \
    -m 4096 \
    -cpu host \
    -enable-kvm \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-gpu-pci \
    -display gtk,gl=on \
    -boot d

echo "After installation, reboot with:"
echo "  qemu-system-x86_64 -hda $INSTALL_DISK -m 2048 -enable-kvm ..."
