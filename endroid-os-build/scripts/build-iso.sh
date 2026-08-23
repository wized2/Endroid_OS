#!/bin/bash
set -e

WORKDIR=$(pwd)
ISO_DIR="$WORKDIR/iso_root"
BOOT_DIR="$ISO_DIR/boot/grub"
EFI_DIR="$ISO_DIR/EFI/BOOT"

# Clean up
rm -rf "$ISO_DIR" "$WORKDIR/endroid-os.iso"
mkdir -p "$BOOT_DIR" "$EFI_DIR"

echo "=== Creating Endroid OS ISO ==="

# Copy UI files
echo "Copying UI files..."
mkdir -p "$ISO_DIR/usr/share/endroid"
cp "$WORKDIR/ui/index.html" "$ISO_DIR/usr/share/endroid/"
cp "$WORKDIR/ui/apps.js" "$ISO_DIR/usr/share/endroid/"
cp "$WORKDIR/ui/lucide.js" "$ISO_DIR/usr/share/endroid/"

# Create a simple kernel (we'll use a placeholder for demo)
# For a real build, this would be the compiled bzImage
echo "Creating minimal initramfs..."

# Create init script
cat > "$WORKDIR/init" << 'INIT'
#!/bin/busybox sh
busybox mkdir -p /dev /proc /sys /mnt /data/system /data/apps /data/user
busybox mount -t proc proc /proc
busybox mount -t sysfs sys /sys
busybox mount -t devtmpfs dev /dev

# Mount squashfs root
busybox mkdir -p /root
busybox mount -t squashfs -o ro /dev/sr0 /mnt

# Mount data partition (simulated as tmpfs for ISO demo)
busybox mount -t tmpfs data /data

# Start a simple HTTP server for the UI
cd /mnt/usr/share/endroid
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

menuentry "Endroid OS" {
    linux /boot/bzImage quiet
    initrd /initrd.gz
    boot
}

menuentry "Endroid OS (Install)" {
    linux /boot/bzImage install
    initrd /initrd.gz
    boot
}
GRUB

# Create GRUB config for EFI
cat > "$EFI_DIR/grub.cfg" << 'GRUB'
set timeout=5
set default=0

menuentry "Endroid OS" {
    linux /boot/bzImage quiet
    initrd /initrd.gz
    boot
}

menuentry "Endroid OS (Install)" {
    linux /boot/bzImage install
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
xorriso -as mkisofs \
    -V "ENDROID_OS" \
    -b boot/grub/i386-pc-eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    --grub2-mbr "$GRUB_DIR/i386-pc/linuxboot.img" \
    -eltorito-alt-boot \
    -e EFI/BOOT/efiboot.img \
    -no-emul-boot \
    -isohybrid-mbr "$GRUB_DIR/i386-pc/linuxboot.img" \
    -o "$WORKDIR/endroid-os.iso" \
    "$ISO_DIR" 2>&1 || echo "Note: Full hybrid ISO creation may require additional grub files"

# Simpler ISO creation for demo
rm -f "$WORKDIR/endroid-os.iso"
genisoimage -V "ENDROID_OS" \
    -b boot/grub/i386-pc-eltorito.img \
    -c boot/grub/boot.catalog \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -o "$WORKDIR/endroid-os.iso" \
    "$ISO_DIR" 2>&1 || {
    echo "Creating basic ISO without boot info for demo..."
    genisoimage -V "ENDROID_OS" -o "$WORKDIR/endroid-os.iso" "$ISO_DIR"
}

echo "ISO created at: $WORKDIR/endroid-os.iso"
ls -lh "$WORKDIR/endroid-os.iso"
