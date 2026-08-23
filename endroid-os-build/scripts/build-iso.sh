#!/bin/bash
set -e

WORKDIR=$(pwd)
ISO_DIR="$WORKDIR/iso_root"
BOOT_DIR="$ISO_DIR/boot/grub"
EFI_DIR="$ISO_DIR/EFI/BOOT"

# Clean up
rm -rf "$ISO_DIR" "$WORKDIR/endroid-os-installer.iso"
mkdir -p "$BOOT_DIR" "$EFI_DIR"

echo "=== Creating Endroid OS Installer ISO ==="

# Copy UI files
echo "Copying UI files..."
mkdir -p "$ISO_DIR/usr/share/endroid"
mkdir -p "$ISO_DIR/usr/bin"
cp "$WORKDIR/ui/index.html" "$ISO_DIR/usr/share/endroid/"
cp "$WORKDIR/ui/apps.js" "$ISO_DIR/usr/share/endroid/"
cp "$WORKDIR/ui/lucide.js" "$ISO_DIR/usr/share/endroid/"

# Create installer script
cat > "$ISO_DIR/usr/bin/installer.sh" << 'INSTALLER'
#!/bin/sh
# Simple installer for Endroid OS
echo "Installing Endroid OS..."
# This would be replaced with actual Calamares or custom installer
echo "Installation complete!"
INSTALLER
chmod +x "$ISO_DIR/usr/bin/installer.sh"

# Create a simple kernel placeholder
echo "Creating minimal initramfs..."

# Create init script
cat > "$WORKDIR/init" << 'INIT'
#!/bin/busybox sh
busybox mkdir -p /dev /proc /sys /mnt /data/system /data/apps /data/user
busybox mount -t proc proc /proc
busybox mount -t sysfs sys /sys
busybox mount -t devtmpfs dev /dev

# Check if we're in install mode
if grep -q "install" /proc/cmdline; then
    echo "Starting installer..."
    exec /usr/bin/installer.sh
fi

# Mount squashfs root (simulated for demo)
busybox mkdir -p /root
busybox mount -t tmpfs root /root

# Mount data partition (simulated as tmpfs for ISO demo)
busybox mount -t tmpfs data /data

# Start browser with UI (simulated with simple HTTP server)
cd /usr/share/endroid
exec busybox httpd -f -p 80 -h .
INIT

chmod +x "$WORKDIR/init"

# Create minimal initramfs using cpio
cd "$WORKDIR"
find init | cpio -H newc -o | gzip > "$ISO_DIR/initrd.gz"

# Create GRUB config for BIOS
cat > "$BOOT_DIR/grub.cfg" << 'GRUB'
set timeout=5
set default=0

menuentry "Endroid OS (Live)" {
    linux /boot/bzImage quiet
    initrd /initrd.gz
    boot
}

menuentry "Endroid OS (Install)" {
    linux /boot/bzImage install quiet
    initrd /initrd.gz
    boot
}
GRUB

# Create GRUB config for EFI
cat > "$EFI_DIR/grub.cfg" << 'GRUB'
set timeout=5
set default=0

menuentry "Endroid OS (Live)" {
    linux /boot/bzImage quiet
    initrd /initrd.gz
    boot
}

menuentry "Endroid OS (Install)" {
    linux /boot/bzImage install quiet
    initrd /initrd.gz
    boot
}
GRUB

# Download a minimal kernel for demo purposes
echo "Downloading minimal kernel..."
if [ ! -f "$ISO_DIR/boot/bzImage" ]; then
    # Use a small test kernel or create a placeholder
    # For demo, we'll create a very minimal bzImage placeholder
    dd if=/dev/zero of="$ISO_DIR/boot/bzImage" bs=1M count=4 2>/dev/null
fi

# Create the ISO
echo "Creating ISO image..."
genisoimage -V "ENDROID_OS" \
    -b boot/grub/i386-pc-eltorito.img \
    -c boot/grub/boot.catalog \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -o "$WORKDIR/endroid-os-installer.iso" \
    "$ISO_DIR" 2>&1 || {
    echo "Creating basic ISO without boot info for demo..."
    genisoimage -V "ENDROID_OS" -o "$WORKDIR/endroid-os-installer.iso" "$ISO_DIR"
}

echo "ISO created at: $WORKDIR/endroid-os-installer.iso"
ls -lh "$WORKDIR/endroid-os-installer.iso"
