#!/bin/bash
# Build the Linux kernel for Endroid OS
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$SCRIPT_DIR/../kernel"
OUTPUT_DIR="$SCRIPT_DIR/../output"

mkdir -p "$OUTPUT_DIR"

echo "=== Building Linux Kernel ==="

# Clone linux-stable if not present
if [ ! -d "$KERNEL_DIR/linux-stable" ]; then
    echo "Cloning linux-stable..."
    git clone --depth 1 --branch v6.6.y https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git "$KERNEL_DIR/linux-stable"
fi

cd "$KERNEL_DIR/linux-stable"

# Apply our defconfig
echo "Applying endroid_defconfig..."
cp "$KERNEL_DIR/endroid_defconfig" .config

# Run olddefconfig to resolve any missing options
make olddefconfig

# Build the kernel
echo "Building kernel (this may take a while)..."
make -j$(nproc) bzImage
make -j$(nproc) modules

# Create minimal initramfs
echo "Creating initramfs..."
mkdir -p "$KERNEL_DIR/initramfs"
cat > "$KERNEL_DIR/initramfs/init" << 'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
exec switch_root /dev/root /init
EOF
chmod +x "$KERNEL_DIR/initramfs/init"

cd "$KERNEL_DIR/initramfs"
find . | cpio -H newc -o | gzip > "$OUTPUT_DIR/initramfs.cpio.gz"

# Copy kernel
cp "$KERNEL_DIR/linux-stable/arch/x86/boot/bzImage" "$OUTPUT_DIR/"

echo "=== Kernel build complete ==="
echo "Output: $OUTPUT_DIR/bzImage, $OUTPUT_DIR/initramfs.cpio.gz"
