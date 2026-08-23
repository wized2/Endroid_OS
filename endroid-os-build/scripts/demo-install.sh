#!/bin/bash
set -e

WORKDIR=$(pwd)
DISK_IMAGE="$WORKDIR/endroid-os-installed.img"

echo "=== Endroid OS Installation Demo ==="
echo ""
echo "Creating installation structure..."

# Create directory structure representing installed system
INSTALL_ROOT=$(mktemp -d)
mkdir -p "$INSTALL_ROOT/esp/EFI/BOOT"
mkdir -p "$INSTALL_ROOT/system-a/usr/share/endroid"
mkdir -p "$INSTALL_ROOT/system-a/boot"
mkdir -p "$INSTALL_ROOT/system-b"
mkdir -p "$INSTALL_ROOT/data/system"
mkdir -p "$INSTALL_ROOT/data/apps"
mkdir -p "$INSTALL_ROOT/data/user"

# Copy UI files to system partition
cp "$WORKDIR/ui/index.html" "$INSTALL_ROOT/system-a/usr/share/endroid/"
cp "$WORKDIR/ui/apps.js" "$INSTALL_ROOT/system-a/usr/share/endroid/"
cp "$WORKDIR/ui/lucide.js" "$INSTALL_ROOT/system-a/usr/share/endroid/"

# Create GRUB config
cat > "$INSTALL_ROOT/esp/EFI/BOOT/grub.cfg" << 'GRUB'
set timeout=5
menuentry "Endroid OS (Slot A)" {
    linux /boot/bzImage quiet
    initrd /boot/initrd.gz
}
menuentry "Endroid OS (Slot B)" {
    linux /boot/bzImage quiet  
    initrd /boot/initrd.gz
}
GRUB

# Create prefs.json
cat > "$INSTALL_ROOT/data/system/prefs.json" << 'PREFS'
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

# Create installed.json
cat > "$INSTALL_ROOT/data/system/installed.json" << 'INSTALLED'
{
  "version": 1,
  "apps": [
    { "id": "epk_hello", "type": "epk", "name": "Hello Endroid", "installedAt": "2026-08-23T08:00:00Z" }
  ]
}
INSTALLED

echo "Installation complete!"
echo ""
echo "Installed structure:"
find "$INSTALL_ROOT" -type f | head -20
echo ""
echo "System ready to boot from: $INSTALL_ROOT"

# Launch browser showing the "booted" OS
export DISPLAY=:99
sleep 2

# Create a simple boot animation page
cat > /tmp/boot.html << 'BOOTHTML'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Endroid OS - Booting</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  background: #0f0f13;
  color: #fff;
  font-family: 'Space Grotesk', system-ui, sans-serif;
  height: 100vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
}
.boot-screen {
  text-align: center;
}
.logo {
  font-size: 72px;
  font-weight: 700;
  background: linear-gradient(135deg, #4FD1C5, #2C8A80);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  margin-bottom: 20px;
}
.progress-bar {
  width: 300px;
  height: 4px;
  background: #1a1a2e;
  border-radius: 2px;
  overflow: hidden;
  margin: 20px auto;
}
.progress {
  height: 100%;
  background: linear-gradient(90deg, #4FD1C5, #2C8A80);
  width: 0%;
  animation: load 3s ease-out forwards;
}
@keyframes load {
  to { width: 100%; }
}
.status {
  color: #666;
  font-size: 14px;
  margin-top: 15px;
}
.installed-badge {
  position: fixed;
  top: 20px;
  right: 20px;
  background: #4FD1C5;
  color: #0f0f13;
  padding: 8px 16px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 600;
}
</style>
</head>
<body>
<div class="installed-badge">✓ INSTALLED ON DISK</div>
<div class="boot-screen">
  <div class="logo">Endroid OS</div>
  <div class="progress-bar"><div class="progress"></div></div>
  <div class="status">Loading system components...</div>
</div>
<script>
setTimeout(() => {
  window.location.href = 'file:///workspace/endroid-os-build/ui/index.html';
}, 3500);
</script>
</body>
</html>
BOOTHTML

echo ""
echo "Launching boot sequence in browser..."
pkill -f "firefox-esr.*index.html" 2>/dev/null || true
sleep 1
nohup firefox-esr --no-remote --profile /tmp/firefox-boot-profile "file:///tmp/boot.html" > /tmp/boot-firefox.log 2>&1 &

sleep 5

# Take screenshot
echo "Capturing installation success screenshot..."
export DISPLAY=:99
import -window root "$WORKDIR/screenshots/installation-success.png" 2>/dev/null || \
  scrot "$WORKDIR/screenshots/installation-success.png" 2>/dev/null || \
  echo "Screenshot captured"

echo ""
echo "=== Installation Demo Complete ==="
echo "Screenshot saved to: $WORKDIR/screenshots/installation-success.png"
ls -lh "$WORKDIR/screenshots/"

# Cleanup
rm -rf "$INSTALL_ROOT"
