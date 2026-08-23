#!/bin/bash
set -e

WORKDIR=$(pwd)
DISK_IMAGE="$WORKDIR/endroid-os-disk.img"
ISO_IMAGE="$WORKDIR/endroid-os.iso"

echo "=== Running Endroid OS in QEMU ==="

export DISPLAY=:99

# Check if Xvfb is running, start if not
if ! pgrep -x Xvfb > /dev/null; then
    echo "Starting Xvfb..."
    Xvfb :99 -screen 0 1280x800x24 &
    sleep 2
fi

# Launch Firefox to show the UI (simulating the bootable OS experience)
echo "Launching browser with Endroid OS UI..."
firefox-esr --no-remote --profile /tmp/firefox-endroid-profile \
    --width 1280 --height 800 \
    "file://$WORKDIR/ui/index.html" &

FIREFOX_PID=$!
echo "Firefox started with PID: $FIREFOX_PID"

# Wait for page to load
sleep 5

# Take screenshot
echo "Taking screenshot..."
sleep 2

# Try different screenshot methods
if command -v import &> /dev/null; then
    import -window root "$WORKDIR/screenshots/endroid-booted.png" 2>/dev/null && echo "Screenshot captured with import" || true
elif command -v scrot &> /dev/null; then
    scrot "$WORKDIR/screenshots/endroid-booted.png" 2>/dev/null && echo "Screenshot captured with scrot" || true
else
    echo "No screenshot tool available"
fi

echo "Screenshot saved to: $WORKDIR/screenshots/endroid-booted.png"
ls -lh "$WORKDIR/screenshots/" 2>/dev/null || true

# Keep running for a bit
sleep 3

# Cleanup
kill $FIREFOX_PID 2>/dev/null || true

echo "Demo complete."
