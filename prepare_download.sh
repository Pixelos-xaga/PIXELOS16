#!/bin/bash
# prepare_download.sh - Run this on your GCP VM to prepare files for download

set -e

# --- Configuration ---
# Set base directory
BASE_DIR="$HOME/PIXELOS16"

OUT_DIR="${OUT}"
if [ -z "$OUT_DIR" ]; then
    OUT_DIR="${BASE_DIR}/out/target/product/xaga"
    echo ">>> \$OUT not set, using default: $OUT_DIR"
fi

TIMESTAMP=$(date +%Y%m%d_%H%M)
DOWNLOAD_DIR="${OUT_DIR}/downloads_${TIMESTAMP}"

echo "============================================"
echo "  Prepare ROM Files for Download"
echo "============================================"
echo ""
echo "What would you like to prepare?"
echo "  1) Image files only (fastboot images)"
echo "  2) Recovery build (OTA ZIP + boot images)"
echo ""
read -p "Enter your choice (1-2): " CHOICE
echo ""

case $CHOICE in
    1)
        echo ">>> Preparing IMAGE FILES package..."
        PACKAGE_NAME="images_${TIMESTAMP}"
        PACKAGE_DIR="${DOWNLOAD_DIR}/${PACKAGE_NAME}"
        mkdir -p "$PACKAGE_DIR"
        
        # Copy image files
        ARTIFACTS=(
            "boot.img"
            "vendor_boot.img"
            "super.img"
            "vbmeta.img"
            "vbmeta_system.img"
            "vbmeta_vendor.img"
        )
        
        for img in "${ARTIFACTS[@]}"; do
            if [ -f "${OUT_DIR}/${img}" ]; then
                cp "${OUT_DIR}/${img}" "${PACKAGE_DIR}/"
                echo ">>> Copied $img ($(du -h ${OUT_DIR}/${img} | cut -f1))"
            else
                echo "ERROR: Missing $img"
                exit 1
            fi
        done
        
        # Create ZIP archive
        cd "$DOWNLOAD_DIR"
        zip -r "${PACKAGE_NAME}.zip" "${PACKAGE_NAME}"
        FINAL_FILE="${DOWNLOAD_DIR}/${PACKAGE_NAME}.zip"
        rm -rf "${PACKAGE_NAME}"
        ;;

    2)
        echo ">>> Preparing RECOVERY BUILD package..."
        PACKAGE_NAME="recovery_${TIMESTAMP}"
        PACKAGE_DIR="${DOWNLOAD_DIR}/${PACKAGE_NAME}"
        mkdir -p "$PACKAGE_DIR"
        
        # Check for multiple OTA ZIPs
        ZIP_COUNT=$(find "$OUT_DIR" -maxdepth 1 -name "Pixelos_xaga*.zip" ! -name "*FASTBOOT*" -type f | wc -l)
        if [ "$ZIP_COUNT" -gt 1 ]; then
            echo ">>> WARNING: Found $ZIP_COUNT recovery ZIPs in $OUT_DIR"
            echo ">>> Available ZIPs:"
            find "$OUT_DIR" -maxdepth 1 -name "Pixelos_xaga*.zip" ! -name "*FASTBOOT*" -type f -printf '    %TY-%Tm-%Td %TH:%TM - %f\n' | sort -r
            echo ">>> Selecting the LATEST one..."
            echo ""
        fi
        
        # Find and copy LATEST OTA ZIP (by modification time)
        OTA_ZIP=$(find "$OUT_DIR" -maxdepth 1 -name "Pixelos_xaga*.zip" ! -name "*FASTBOOT*" -type f -printf '%T@ %p\n' | sort -rn | head -n 1 | cut -d' ' -f2-)
        if [ -n "$OTA_ZIP" ]; then
            cp "$OTA_ZIP" "${PACKAGE_DIR}/"
            echo ">>> Copied $(basename $OTA_ZIP) ($(du -h $OTA_ZIP | cut -f1))"
            echo ">>> Modified: $(date -r $OTA_ZIP '+%Y-%m-%d %H:%M:%S')"
        else
            echo "ERROR: OTA ZIP not found in $OUT_DIR"
            exit 1
        fi
        
        # Copy boot images
        if [ -f "${OUT_DIR}/boot.img" ]; then
            cp "${OUT_DIR}/boot.img" "${PACKAGE_DIR}/"
            echo ">>> Copied boot.img ($(du -h ${OUT_DIR}/boot.img | cut -f1))"
        else
            echo "ERROR: Missing boot.img"
            exit 1
        fi
        
        if [ -f "${OUT_DIR}/vendor_boot.img" ]; then
            cp "${OUT_DIR}/vendor_boot.img" "${PACKAGE_DIR}/"
            echo ">>> Copied vendor_boot.img ($(du -h ${OUT_DIR}/vendor_boot.img | cut -f1))"
        else
            echo "ERROR: Missing vendor_boot.img"
            exit 1
        fi
        
        # Create ZIP archive
        cd "$DOWNLOAD_DIR"
        zip -r "${PACKAGE_NAME}.zip" "${PACKAGE_NAME}"
        FINAL_FILE="${DOWNLOAD_DIR}/${PACKAGE_NAME}.zip"
        rm -rf "${PACKAGE_NAME}"
        ;;

    *)
        echo "ERROR: Invalid choice. Please select 1 or 2."
        exit 1
        ;;
esac

echo ""
echo "============================================"
echo ">>> Package ready!"
echo "============================================"
echo "Location: $FINAL_FILE"
echo "Size: $(du -h $FINAL_FILE | cut -f1)"
echo ""
echo "Download command for Windows:"
echo "gcloud compute scp pixelos:$FINAL_FILE . --project=agile-outlook-481719-c1 --zone=YOUR_ZONE"
echo ""
echo "Or just run the download_rom_auto.bat script on Windows!"
echo "============================================"

# Save path for automation
echo "$FINAL_FILE" > /tmp/pixelos_last_build.txt
