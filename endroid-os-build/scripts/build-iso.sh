#!/bin/bash
# Build the Endroid OS installer ISO
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/../output"
INSTALLER_DIR="$SCRIPT_DIR/../installer"
UI_DIR="$SCRIPT_DIR/../ui"

mkdir -p "$OUTPUT_DIR"

echo "=== Building Endroid OS Installer ISO ==="

# This script sets up a Calamares-based installer
# For now, we create a minimal live ISO that can install to disk

ISO_ROOT="$OUTPUT_DIR/iso-root"
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT"/{boot,EFI/boot,isolinux}

# Copy kernel and initramfs
cp "$OUTPUT_DIR/bzImage" "$ISO_ROOT/boot/vmlinuz"
cp "$OUTPUT_DIR/initramfs.cpio.gz" "$ISO_ROOT/boot/initrd.gz"

# Copy UI files for live environment
mkdir -p "$ISO_ROOT/usr/share/endroid"
cp "$UI_DIR/index.html" "$ISO_ROOT/usr/share/endroid/"
cp "$UI_DIR/apps.js" "$ISO_ROOT/usr/share/endroid/"

# Create isolinux config
cat > "$ISO_ROOT/isolinux/isolinux.cfg" << 'EOF'
DEFAULT endroid
LABEL endroid
    MENU LABEL Endroid OS Installer
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.gz boot=live quiet
EOF

# Create GRUB config for UEFI
cat > "$ISO_ROOT/EFI/boot/grub.cfg" << 'EOF'
menuentry "Endroid OS Installer" {
    linux /boot/vmlinuz boot=live quiet
    initrd /boot/initrd.gz
}
EOF

# Generate isolinux binary (requires syslinux)
if command -v isolinux.bin &> /dev/null; then
    cp $(which isolinux.bin) "$ISO_ROOT/isolinux/"
fi

# Create the ISO
echo "Creating ISO image..."
xorriso -as mkisofs \
    -V "ENDROID_INSTALLER" \
    -sysid "" \
    -A "Endroid OS Installer" \
    -input-charset utf-8 \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e EFI/boot/grub.cfg \
    -no-emul-boot \
    -o "$OUTPUT_DIR/endroid-installer.iso" \
    "$ISO_ROOT"

echo "=== Installer ISO build complete ==="
echo "Output: $OUTPUT_DIR/endroid-installer.iso"
