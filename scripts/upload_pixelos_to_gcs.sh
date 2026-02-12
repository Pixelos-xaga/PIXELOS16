#!/bin/bash

# PixelOS ROM Upload Script for Google Cloud Storage
# This script uploads boot.img, vendor_boot.img, and PixelOS zip to GCS bucket

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIXELOS_ROOT="$(dirname "$SCRIPT_DIR")"  # Parent directory of scripts folder
BUCKET_NAME="${GCS_BUCKET_NAME:-your-pixelos-builds}"  # Hardcoded default bucket
OUT_DIR="${OUT:-$PIXELOS_ROOT/out/target/product}"  # Default Android build output directory
DEVICE="${DEVICE_CODENAME}"  # Device codename - will auto-detect if not set

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if bucket name is provided
if [ -z "$BUCKET_NAME" ]; then
    print_error "Bucket name not provided!"
    echo "Usage: GCS_BUCKET_NAME=your-bucket-name DEVICE_CODENAME=device ./upload_pixelos_to_gcs.sh"
    echo "   OR: ./upload_pixelos_to_gcs.sh your-bucket-name device-codename [out-directory]"
    exit 1
fi

# Allow command line arguments as alternative
if [ $# -ge 1 ]; then
    BUCKET_NAME=$1
fi

if [ $# -ge 2 ]; then
    DEVICE=$2
fi

if [ $# -ge 3 ]; then
    OUT_DIR=$3
fi

# Auto-detect device if not provided
if [ -z "$DEVICE" ]; then
    print_info "Device codename not provided, attempting auto-detection..."
    
    # Method 1: Check TARGET_PRODUCT environment variable
    if [ -n "$TARGET_PRODUCT" ]; then
        DEVICE=$(echo "$TARGET_PRODUCT" | sed 's/^aosp_//;s/^pixelos_//;s/^custom_//;s/-.*$//')
        print_info "Detected device from TARGET_PRODUCT: ${DEVICE}"
    fi
    
    # Method 2: Look for directories in out/target/product (excluding common non-device dirs)
    if [ -z "$DEVICE" ] && [ -d "$OUT_DIR" ]; then
        DEVICE=$(ls -1 "$OUT_DIR" 2>/dev/null | grep -v "^generic" | grep -v "^emulator" | grep -v "^mainline" | head -1)
        if [ -n "$DEVICE" ]; then
            print_info "Detected device from output directory: ${DEVICE}"
        fi
    fi
    
    # Method 3: Check for boot.img and extract device from path
    if [ -z "$DEVICE" ]; then
        BOOT_PATH=$(find "$OUT_DIR" -name "boot.img" -type f 2>/dev/null | head -1)
        if [ -n "$BOOT_PATH" ]; then
            DEVICE=$(basename $(dirname "$BOOT_PATH"))
            print_info "Detected device from boot.img path: ${DEVICE}"
        fi
    fi
    
    if [ -z "$DEVICE" ]; then
        print_error "Could not auto-detect device codename!"
        echo "Please provide device codename:"
        echo "  DEVICE_CODENAME=xaga ./upload_pixelos_to_gcs.sh"
        echo "  OR: ./upload_pixelos_to_gcs.sh your-pixelos-builds xaga"
        exit 1
    fi
fi

# Construct the full output path
FULL_OUT_DIR="${OUT_DIR}/${DEVICE}"

print_info "Starting PixelOS ROM upload to GCS"
print_info "Bucket: gs://${BUCKET_NAME}"
print_info "Device: ${DEVICE}"
print_info "Output directory: ${FULL_OUT_DIR}"

# Check if gcloud is installed and authenticated
if ! command -v gsutil &> /dev/null; then
    print_error "gsutil not found. Please install Google Cloud SDK."
    print_info "Run: curl https://sdk.cloud.google.com | bash"
    exit 1
fi

# Verify authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    print_warning "Not authenticated with gcloud. Running authentication..."
    gcloud auth login
fi

# Check if output directory exists
if [ ! -d "$FULL_OUT_DIR" ]; then
    print_error "Output directory not found: ${FULL_OUT_DIR}"
    exit 1
fi

# Find the ROM files
print_info "Searching for ROM files..."

# Find boot.img
BOOT_IMG=$(find "$FULL_OUT_DIR" -name "boot.img" -type f | head -1)
if [ -z "$BOOT_IMG" ]; then
    print_warning "boot.img not found in ${FULL_OUT_DIR}"
else
    print_info "Found boot.img: ${BOOT_IMG}"
fi

# Find vendor_boot.img
VENDOR_BOOT_IMG=$(find "$FULL_OUT_DIR" -name "vendor_boot.img" -type f | head -1)
if [ -z "$VENDOR_BOOT_IMG" ]; then
    print_warning "vendor_boot.img not found in ${FULL_OUT_DIR}"
else
    print_info "Found vendor_boot.img: ${VENDOR_BOOT_IMG}"
fi

# Find PixelOS zip (usually named PixelOS-*.zip or similar)
PIXELOS_ZIP=$(find "$FULL_OUT_DIR" -name "PixelOS*.zip" -o -name "pixelos*.zip" -o -name "aosp*.zip" | head -1)
if [ -z "$PIXELOS_ZIP" ]; then
    # Try finding any zip file in the directory
    PIXELOS_ZIP=$(find "$FULL_OUT_DIR" -name "*.zip" -type f | head -1)
    if [ -z "$PIXELOS_ZIP" ]; then
        print_warning "PixelOS ROM zip not found in ${FULL_OUT_DIR}"
    else
        print_info "Found ROM zip: ${PIXELOS_ZIP}"
    fi
else
    print_info "Found PixelOS zip: ${PIXELOS_ZIP}"
fi

# Check if at least one file was found
if [ -z "$BOOT_IMG" ] && [ -z "$VENDOR_BOOT_IMG" ] && [ -z "$PIXELOS_ZIP" ]; then
    print_error "No ROM files found to upload!"
    exit 1
fi

# Create a timestamp for the upload folder
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
UPLOAD_PATH="${DEVICE}/${TIMESTAMP}"

print_info "Upload path: gs://${BUCKET_NAME}/${UPLOAD_PATH}/"

# Upload function
upload_file() {
    local file=$1
    local filename=$(basename "$file")
    
    if [ -n "$file" ] && [ -f "$file" ]; then
        print_info "Uploading ${filename}..."
        if gsutil -m cp "$file" "gs://${BUCKET_NAME}/${UPLOAD_PATH}/${filename}"; then
            print_info "✓ ${filename} uploaded successfully"
            
            # Make file publicly accessible (optional - comment out if you want private files)
            # gsutil acl ch -u AllUsers:R "gs://${BUCKET_NAME}/${UPLOAD_PATH}/${filename}"
            
            # Generate download URL
            echo "Download URL: https://storage.googleapis.com/${BUCKET_NAME}/${UPLOAD_PATH}/${filename}"
        else
            print_error "Failed to upload ${filename}"
            return 1
        fi
    fi
}

# Upload all found files
upload_file "$BOOT_IMG"
upload_file "$VENDOR_BOOT_IMG"
upload_file "$PIXELOS_ZIP"

print_info "Upload complete!"
print_info "All files available at: gs://${BUCKET_NAME}/${UPLOAD_PATH}/"

# Generate a simple index file
INDEX_FILE="/tmp/pixelos_build_info.txt"
cat > "$INDEX_FILE" << EOF
PixelOS Build Information
========================
Device: ${DEVICE}
Build Date: $(date)
Upload Path: gs://${BUCKET_NAME}/${UPLOAD_PATH}/

Files:
EOF

[ -n "$BOOT_IMG" ] && echo "- boot.img" >> "$INDEX_FILE"
[ -n "$VENDOR_BOOT_IMG" ] && echo "- vendor_boot.img" >> "$INDEX_FILE"
[ -n "$PIXELOS_ZIP" ] && echo "- $(basename "$PIXELOS_ZIP")" >> "$INDEX_FILE"

gsutil cp "$INDEX_FILE" "gs://${BUCKET_NAME}/${UPLOAD_PATH}/BUILD_INFO.txt"
rm "$INDEX_FILE"

print_info "Build info uploaded to: gs://${BUCKET_NAME}/${UPLOAD_PATH}/BUILD_INFO.txt"
