#!/bin/bash
# PixelOS Fastboot Package Builder
# Usage: ./build_fb_package.sh
# Run this AFTER running: m pixelos (or m otapackage)

set -e

DEVICE="xaga"
DEVICE_PATH="device/xiaomi/xaga"
OUT_DIR="out/target/product/${DEVICE}"
TEMPLATE_ZIP="${DEVICE_PATH}/prebuilts/fastboot.zip"
BUILD_NAME="PixelOS"
DATE=$(date +%Y%m%d)

echo "============================================"
echo "  PixelOS Fastboot Package Builder"
echo "============================================"

# Check if OTA build exists
if [ ! -d "${OUT_DIR}" ]; then
    echo "ERROR: Build output not found!"
    echo "Please run 'm pixelos' first."
    exit 1
fi

# Check for super.img
if [ ! -f "${OUT_DIR}/super.img" ]; then
    echo "ERROR: super.img not found!"
    echo "Please ensure the build completed successfully."
    exit 1
fi

# Check for template zip
if [ ! -f "${TEMPLATE_ZIP}" ]; then
    echo "ERROR: fastboot template not found at ${TEMPLATE_ZIP}"
    exit 1
fi

echo ""
echo "[1/4] Creating working directory..."
WORK_DIR=$(mktemp -d)
FB_DIR="${WORK_DIR}/fastboot_package"
IMAGES_DIR="${FB_DIR}/images"
mkdir -p "${IMAGES_DIR}"

echo "[2/4] Extracting fastboot template..."
unzip -q "${TEMPLATE_ZIP}" -d "${FB_DIR}"

echo "[3/4] Copying built images..."
# Copy all relevant images to the images folder
cp -v "${OUT_DIR}/super.img" "${IMAGES_DIR}/" 2>/dev/null || true
cp -v "${OUT_DIR}/boot.img" "${IMAGES_DIR}/" 2>/dev/null || true
cp -v "${OUT_DIR}/vendor_boot.img" "${IMAGES_DIR}/" 2>/dev/null || true
cp -v "${OUT_DIR}/vbmeta.img" "${IMAGES_DIR}/" 2>/dev/null || true
cp -v "${OUT_DIR}/vbmeta_system.img" "${IMAGES_DIR}/" 2>/dev/null || true

# Copy dtbo if exists
cp -v "${OUT_DIR}/dtbo.img" "${IMAGES_DIR}/" 2>/dev/null || true

# Copy any other img files
for img in "${OUT_DIR}"/*.img; do
    if [ -f "$img" ]; then
        filename=$(basename "$img")
        if [ ! -f "${IMAGES_DIR}/${filename}" ]; then
            cp -v "$img" "${IMAGES_DIR}/"
        fi
    fi
done

echo "[4/4] Creating fastboot zip..."
OUTPUT_ZIP="${OUT_DIR}/${BUILD_NAME}-${DEVICE}-${DATE}-fastboot.zip"
cd "${FB_DIR}"
zip -rq "${OUTPUT_ZIP}" .
cd -

echo ""
echo "============================================"
echo "  SUCCESS!"
echo "============================================"
echo "Fastboot package created:"
echo "  ${OUTPUT_ZIP}"
echo ""
echo "Files in package:"
unzip -l "${OUTPUT_ZIP}" | head -20

# Cleanup
rm -rf "${WORK_DIR}"

echo ""
echo "Done!"
