#!/bin/bash
# Build the root filesystem using Buildroot
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDROOT_DIR="$SCRIPT_DIR/../buildroot"
OUTPUT_DIR="$SCRIPT_DIR/../output"
DAEMON_DIR="$SCRIPT_DIR/../daemon"

mkdir -p "$OUTPUT_DIR"

echo "=== Building Root Filesystem ==="

# Clone buildroot if not present
if [ ! -d "$BUILDROOT_DIR/buildroot" ]; then
    echo "Cloning buildroot..."
    git clone --depth 1 --branch 2024.02 https://gitlab.buildroot.org/buildroot/buildroot.git "$BUILDROOT_DIR/buildroot"
fi

cd "$BUILDROOT_DIR/buildroot"

# Copy external tree
echo "Setting up external tree..."
mkdir -p br2-external/package/endroidd
cp -r "$BUILDROOT_DIR/br2-external/configs/" br2-external/configs/
cp -r "$BUILDROOT_DIR/br2-external/package/endroidd/" br2-external/package/endroidd/

# Create external config file
cat > br2-external/external.mk << 'EOF'
include $(sort $(wildcard $(BR2_EXTERNAL_ENDROID_PATH)/package/*/*.mk))
EOF

# Build with our config
echo "Running make menuconfig to verify..."
make BR2_EXTERNAL=../br2-external endroid_defconfig

# Build everything
echo "Building rootfs (this will take a while)..."
make BR2_EXTERNAL=../br2-external -j$(nproc)

# Copy output
cp output/images/rootfs.squashfs "$OUTPUT_DIR/"

echo "=== Rootfs build complete ==="
echo "Output: $OUTPUT_DIR/rootfs.squashfs"
