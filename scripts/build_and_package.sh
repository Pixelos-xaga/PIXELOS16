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
    "spmfw.img" "sspm.img" "tee.img" "vcp.img" "dtbo.img" "preloader_raw.img"
)
# List of build artifacts to copy from $OUT
BUILD_ARTIFACTS=(
    "boot.img" "vendor_boot.img" "super.img" "vbmeta.img" "vbmeta_system.img" "vbmeta_vendor.img"
)

# --- Interactive Menu ---
echo "============================================"
echo "  PixelOS Build & Package Script"
echo "============================================"
echo ""
echo "What would you like to build?"
echo "  1) Recovery ROM only (OTA ZIP)"
echo "  2) Recovery ROM + Fastboot package (OTA + Fastboot)"
echo "  3) Fastboot package only (no build)"
echo ""
read -p "Enter your choice (1-3): " BUILD_CHOICE
echo ""

case $BUILD_CHOICE in
    1)
        echo ">>> Selected: Recovery ROM only"
        DO_BUILD=true
        DO_FASTBOOT=false
        ;;
    2)
        echo ">>> Selected: Recovery ROM + Fastboot package"
        DO_BUILD=true
        DO_FASTBOOT=true
        ;;
    3)
        echo ">>> Selected: Fastboot package only"
        DO_BUILD=false
        DO_FASTBOOT=true
        ;;
    *)
        echo "ERROR: Invalid choice. Please select 1, 2, or 3."
        exit 1
        ;;
esac

echo ""

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

# --- 2. Build (Conditional) ---
if [ "$DO_BUILD" = true ]; then
    echo ">>> Starting build..."
    m pixelos superimage
else
    echo ">>> Skipping build (using existing artifacts)..."
    # Verify that required artifacts exist
    echo ">>> Checking for existing build artifacts..."
    MISSING_ARTIFACTS=false
    for img in "${BUILD_ARTIFACTS[@]}"; do
        if [ ! -f "${OUT_DIR}/${img}" ]; then
            echo "ERROR: Required artifact not found: ${OUT_DIR}/${img}"
            MISSING_ARTIFACTS=true
        fi
    done
    
    if [ "$MISSING_ARTIFACTS" = true ]; then
        echo "ERROR: Missing build artifacts. Please build first or select option 1 or 2."
        exit 1
    fi
    echo ">>> All required artifacts found."
fi

# --- 3. Fastboot Package Creation (Conditional) ---
if [ "$DO_FASTBOOT" = true ]; then
    # --- 3a. Prepare Packaging Directory ---
    TIMESTAMP=$(date +%Y%m%d-%H%M)
    PACKAGE_NAME="FASTBOOT_Pixel_${DEVICE}_${TIMESTAMP}"
    PACKAGE_DIR="${OUT_DIR}/${PACKAGE_NAME}"
    IMAGES_DIR="${PACKAGE_DIR}/images"

    echo ">>> Preparing fastboot package at: $PACKAGE_DIR"
    rm -rf "$PACKAGE_DIR"
    mkdir -p "$IMAGES_DIR"

    # --- 3b. Copy Fastboot Tools and Scripts ---
    echo ">>> Copying fastboot scripts to $PACKAGE_DIR..."
    if [ -d "scripts/fastboot" ]; then
        cp -r scripts/fastboot/. "$PACKAGE_DIR/"
    else
        echo "ERROR: scripts/fastboot directory not found!"
        exit 1
    fi

    # Verify tools directory
    if [ -d "$PACKAGE_DIR/tools" ]; then
        echo ">>> Tools directory verified in package."
        ls -F "$PACKAGE_DIR/tools"
    else
        echo "ERROR: tools directory missing in package!"
        echo "DEBUG: Listing source scripts/fastboot:"
        ls -F "scripts/fastboot"
        exit 1
    fi

    # --- 3c. Fetch and Copy Firmware Images ---
    echo ">>> Fetching firmware images..."
    TEMP_FIRMWARE_DIR="${OUT_DIR}/temp_firmware"
    rm -rf "$TEMP_FIRMWARE_DIR"
    git clone "$FIRMWARE_REPO" "$TEMP_FIRMWARE_DIR"

    echo ">>> Copying firmware images to package..."
    for img in "${FIRMWARE_IMAGES[@]}"; do
        # Search for the image file recursively within the temp firmware directory
        IMG_PATH=$(find "$TEMP_FIRMWARE_DIR" -type f -name "$img" | head -n 1)
        
        if [ -n "$IMG_PATH" ]; then
            echo ">>> Found $img at $IMG_PATH"
            # Rename preloader_raw.img to preloader_xaga.bin if needed
            if [ "$img" == "preloader_raw.img" ]; then
                cp "$IMG_PATH" "$IMAGES_DIR/preloader_xaga.bin"
            else
                cp "$IMG_PATH" "$IMAGES_DIR/"
            fi
        else
            echo "WARNING: Firmware image not found: $img"
            # List files in temp firmware for debugging (limited to first 2 levels)
            # echo "DEBUG: Listing temp firmware content:"
            # find "$TEMP_FIRMWARE_DIR" -maxdepth 2
        fi
    done

    # Clean up temp firmware dir
    rm -rf "$TEMP_FIRMWARE_DIR"

    # --- 3d. Copy Build Artifacts ---
    echo ">>> Copying build artifacts to package..."
    for img in "${BUILD_ARTIFACTS[@]}"; do
        if [ -f "${OUT_DIR}/${img}" ]; then
            cp "${OUT_DIR}/${img}" "$IMAGES_DIR/"
        else
            echo "ERROR: Build artifact not found: $img"
            echo "DEBUG: Listing output directory content matching available images:"
            ls -1 "$OUT_DIR" | grep -E "img|zip" || echo "No images found in $OUT_DIR"
            exit 1
        fi
    done

    # --- 3e. Create Fastboot ZIP ---
    echo ">>> Creating Fastboot ZIP..."
    cd "$OUT_DIR"
    zip -r "${PACKAGE_NAME}.zip" "${PACKAGE_NAME}"
    echo ">>> Fastboot package created: ${OUT_DIR}/${PACKAGE_NAME}.zip"
else
    echo ">>> Skipping fastboot package creation."
fi

# --- 4. Handle OTA ZIP (for Recovery builds) ---
if [ "$DO_BUILD" = true ]; then
    echo ">>> Handling OTA ZIP..."
    # Find the latest OTA zip
    OTA_ZIP=$(find "$OUT_DIR" -maxdepth 1 -name "Pixelos_${DEVICE}*.zip" ! -name "*FASTBOOT*" -type f | head -n 1)
    if [ -n "$OTA_ZIP" ]; then
        echo ">>> Found OTA ZIP: $OTA_ZIP"
        # It's already in OUT_DIR, so we just acknowledge it.
    else
        echo "WARNING: OTA ZIP not found in $OUT_DIR"
    fi
fi

echo ""
echo "============================================"
echo ">>> Done!"
echo "============================================"

# Summary
if [ "$DO_BUILD" = true ]; then
    echo ">>> Recovery ROM built"
    if [ -n "$OTA_ZIP" ]; then
        echo "    - OTA ZIP: $OTA_ZIP"
    fi
fi

if [ "$DO_FASTBOOT" = true ]; then
    echo ">>> Fastboot package created"
    echo "    - Location: ${OUT_DIR}/${PACKAGE_NAME}.zip"
fi
