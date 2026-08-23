#!/bin/bash
set -e

WORKDIR=$(pwd)
DISK_IMAGE="$WORKDIR/endroid-os-disk.img"
ISO_IMAGE="$WORKDIR/endroid-os.iso"

# Create a blank virtual disk (8GB for demo)
echo "Creating virtual disk..."
rm -f "$DISK_IMAGE"
qemu-img create -f qcow2 "$DISK_IMAGE" 8G

# Start QEMU with installer ISO
echo "Starting QEMU installer..."
export DISPLAY=:99

# Check if Xvfb is running, start if not
if ! pgrep -x Xvfb > /dev/null; then
    echo "Starting Xvfb..."
    Xvfb :99 -screen 0 1280x800x24 &
    sleep 2
fi

# Launch QEMU with the installer ISO
qemu-system-x86_64 \
    -m 2048 \
    -hda "$DISK_IMAGE" \
    -cdrom "$ISO_IMAGE" \
    -boot d \
    -enable-kvm 2>/dev/null || qemu-system-x86_64 \
    -m 2048 \
    -hda "$DISK_IMAGE" \
    -cdrom "$ISO_IMAGE" \
    -boot d \
    -cpu qemu64 \
    -vnc :0 &

QEMU_PID=$!
echo "QEMU started with PID: $QEMU_PID"

# Wait for installation to complete (simulated)
sleep 5

# Take screenshot
echo "Taking screenshot of installer..."
sleep 2
import -window root "$WORKDIR/screenshots/installer-running.png" 2>/dev/null || {
    # Fallback: use scrot
    scrot "$WORKDIR/screenshots/installer-running.png" 2>/dev/null || {
        echo "Screenshot tools not available, skipping screenshot capture"
    }
}

# Keep QEMU running for a bit
sleep 3

# Kill QEMU
kill $QEMU_PID 2>/dev/null || true

echo "Installer simulation complete."
echo "Disk image created at: $DISK_IMAGE"
ls -lh "$DISK_IMAGE"
