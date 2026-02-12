#!/bin/bash

# Configuration
BUCKET="gs://your-pixelos-builds/xaga"
REPO="Pixelos-xaga/pixelos-releases"
BUILD_TYPE="unofficial"  # Change to "official" when ready

echo "======================================"
echo "PixelOS Release Automation"
echo "======================================"
echo ""

# Step 1: Find the latest build folder
echo "Finding latest build..."
LATEST_BUILD=$(gsutil ls ${BUCKET}/ | grep -E '[0-9]{8}_[0-9]{6}' | sort -r | head -n1)

if [ -z "$LATEST_BUILD" ]; then
  echo "❌ No build folders found in ${BUCKET}"
  exit 1
fi

BUILD_FOLDER=$(basename "$LATEST_BUILD")
echo "Latest build folder: $BUILD_FOLDER"
echo ""

# Extract date for version
BUILD_DATE_RAW=${BUILD_FOLDER:0:8}  # 20260212
BUILD_TIME=${BUILD_FOLDER:9:6}      # 213518
VERSION="1.0-${BUILD_DATE_RAW}"
BUILD_DATE="${BUILD_DATE_RAW:0:4}-${BUILD_DATE_RAW:4:2}-${BUILD_DATE_RAW:6:2}"

echo "Version: $VERSION"
echo "Build Date: $BUILD_DATE"
echo ""

# Step 2: List files in the build folder
echo "Files in build:"
gsutil ls ${LATEST_BUILD}
echo ""

# Step 3: Make files public
echo "Making files public..."
gsutil -m acl ch -u AllUsers:R ${LATEST_BUILD}boot.img
gsutil -m acl ch -u AllUsers:R ${LATEST_BUILD}vendor_boot.img
gsutil -m acl ch -u AllUsers:R ${LATEST_BUILD}PixelOS_xaga*.zip
gsutil -m acl ch -u AllUsers:R ${LATEST_BUILD}fastboot.zip 2>/dev/null || echo "  (no fastboot.zip found)"

# Step 4: Get public URLs
BOOT_URL="https://storage.googleapis.com/your-pixelos-builds/xaga/${BUILD_FOLDER}/boot.img"
VENDOR_BOOT_URL="https://storage.googleapis.com/your-pixelos-builds/xaga/${BUILD_FOLDER}/vendor_boot.img"

# Get the actual ROM filename
ROM_FILE=$(gsutil ls ${LATEST_BUILD}PixelOS_xaga*.zip 2>/dev/null | head -n1)
if [ -z "$ROM_FILE" ]; then
  echo "❌ No ROM ZIP found!"
  exit 1
fi
ROM_FILENAME=$(basename "$ROM_FILE")
ROM_URL="https://storage.googleapis.com/your-pixelos-builds/xaga/${BUILD_FOLDER}/${ROM_FILENAME}"

FASTBOOT_URL="https://storage.googleapis.com/your-pixelos-builds/xaga/${BUILD_FOLDER}/fastboot.zip"

echo ""
echo "URLs prepared:"
echo "  Boot: $BOOT_URL"
echo "  Vendor Boot: $VENDOR_BOOT_URL"
echo "  ROM: $ROM_URL"
echo ""

# Step 5: Get changelog
echo "Enter changelog (or press Enter for default):"
read -r CHANGELOG
if [ -z "$CHANGELOG" ]; then
  CHANGELOG="Bug fixes and improvements"
fi

# Step 6: Trigger GitHub workflow
echo ""
echo "Triggering GitHub release..."

gh workflow run create-release-with-ota.yml \
  -R "$REPO" \
  -f version="$VERSION" \
  -f build_date="$BUILD_DATE" \
  -f build_type="$BUILD_TYPE" \
  -f boot_img_url="$BOOT_URL" \
  -f vendor_boot_img_url="$VENDOR_BOOT_URL" \
  -f rom_zip_url="$ROM_URL" \
  -f fastboot_zip_url="$FASTBOOT_URL" \
  -f changelog="$CHANGELOG"

echo ""
echo "✅ Release workflow triggered!"
echo ""
echo "Build Folder: $BUILD_FOLDER"
echo "Check status: https://github.com/$REPO/actions"
echo "OTA endpoint: https://pixelos-xaga.github.io/pixelos-releases/xaga.json"