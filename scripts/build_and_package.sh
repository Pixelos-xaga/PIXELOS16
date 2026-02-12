#!/bin/bash

# Exit on error
set -e

# --- Configuration ---
DEVICE="xaga"
BUILD_TYPE="user"
FIRMWARE_REPO="https://github.com/XagaForge/android_vendor_firmware"
FIRMWARE_BRANCH="main" # Assuming main branch, can be adjusted
# List of firmware images required by win_installation.bat
FIRMWARE_IMAGES=(
    "apusys.img" "audio_dsp.img" "ccu.img" "dpm.img" "gpueb.img" "gz.img" "lk.img"
    "mcf_ota.img" "mcupm.img" "md1img.img" "mvpu_algo.img" "pi_img.img" "scp.img"
    "spmfw.img" "sspm.img" "tee.img" "vcp.img" "preloader_xaga.bin"
)
# List of build artifacts to copy from $OUT
BUILD_ARTIFACTS=(
    "boot.img" "vendor_boot.img" "dtbo.img" "super.img" "vbmeta.img" "vbmeta_system.img" "vbmeta_vendor.img"
)

# --- 1. Environment Setup ---
echo ">>> Setting up build environment..."
source build/envsetup.sh
breakfast $DEVICE $BUILD_TYPE

# Get OUT directory
OUT_DIR="$OUT"
if [ -z "$OUT_DIR" ]; then
    echo "ERROR: \$OUT is not set. Ensure breakfast command succeeded."
    exit 1
fi
echo ">>> Build output directory: $OUT_DIR"

# --- 2. Build ---
echo ">>> Starting build..."
m pixelos
echo ">>> generating super.img..."
m superimage

# --- 3. Prepare Packaging Directory ---
TIMESTAMP=$(date +%Y%m%d-%H%M)
PACKAGE_NAME="FASTBOOT_Pixel_${DEVICE}_${TIMESTAMP}"
PACKAGE_DIR="${OUT_DIR}/${PACKAGE_NAME}"
IMAGES_DIR="${PACKAGE_DIR}/images"

echo ">>> Preparing fastboot package at: $PACKAGE_DIR"
rm -rf "$PACKAGE_DIR"
mkdir -p "$IMAGES_DIR"

# --- 4. Copy Fastboot Tools and Scripts ---
echo ">>> Copying fastboot scripts..."
cp -r scripts/fastboot/* "$PACKAGE_DIR/"

# --- 5. Fetch and Copy Firmware Images ---
echo ">>> Fetching firmware images..."
TEMP_FIRMWARE_DIR="${OUT_DIR}/temp_firmware"
rm -rf "$TEMP_FIRMWARE_DIR"
git clone "$FIRMWARE_REPO" "$TEMP_FIRMWARE_DIR"

echo ">>> Copying firmware images to package..."
for img in "${FIRMWARE_IMAGES[@]}"; do
    if [ -f "${TEMP_FIRMWARE_DIR}/${img}" ]; then
        cp "${TEMP_FIRMWARE_DIR}/${img}" "$IMAGES_DIR/"
    else
        echo "WARNING: Firmware image not found: $img"
    fi
done

# Clean up temp firmware dir
rm -rf "$TEMP_FIRMWARE_DIR"

# --- 6. Copy Build Artifacts ---
echo ">>> Copying build artifacts to package..."
for img in "${BUILD_ARTIFACTS[@]}"; do
    if [ -f "${OUT_DIR}/${img}" ]; then
        cp "${OUT_DIR}/${img}" "$IMAGES_DIR/"
    else
        echo "ERROR: Build artifact not found: $img"
        exit 1
    fi
done

# --- 7. Create Fastboot ZIP ---
echo ">>> Creating Fastboot ZIP..."
cd "$OUT_DIR"
zip -r "${PACKAGE_NAME}.zip" "${PACKAGE_NAME}"
echo ">>> Fastboot package created: ${OUT_DIR}/${PACKAGE_NAME}.zip"

# --- 8. Copy OTA ZIP ---
echo ">>> Handling OTA ZIP..."
# Find the latest OTA zip
OTA_ZIP=$(ls Pixelos_${DEVICE}*.zip | grep -v "FASTBOOT" | head -n 1) # Simple check, might need refinement if multiple exist
if [ -n "$OTA_ZIP" ]; then
    echo ">>> Found OTA ZIP: $OTA_ZIP"
    # It's already in OUT_DIR, so we just acknowledge it.
else
    echo "WARNING: OTA ZIP not found in $OUT_DIR"
fi

echo ">>> Done!"
