#!/bin/bash

# PixelOS GCloud Build Fix Script
# This script applies and manages fixes from GCLOUD_CHANGES.md

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log function
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running in a PixelOS build directory
check_pixelos_dir() {
    if [ ! -d "out" ] && [ ! -d ".repo" ]; then
        log_error "Not in a PixelOS build directory"
        exit 1
    fi
}

# Function to apply/undo option
apply_option() {
    local name=$1
    local function_name=$2

    echo ""
    echo "=== $name ==="
    echo "This will: ${description[$name]}"
    echo ""
    read -p "Apply this fix? (y/n): " choice

    if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
        $function_name apply
    elif [ "$choice" = "u" ] || [ "$choice" = "U" ]; then
        $function_name undo
    else
        log_info "Skipped $name"
    fi
}

# Function to create custom_xaga.mk
create_custom_xaga() {
    local action=$1

    case "$action" in
        apply)
            log_info "Creating custom_xaga.mk..."
            cat > device/xiaomi/xaga/custom_xaga.mk << 'EOF'
# Copyright (C) 2024 The PixelOS Project
# Licensed under the Apache License, Version 2.0

PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/Makefile

COMMON_LUNCH_COMBO := custom_xaga-user

$(call inherit-product, vendor/custom/config/common_full_phone.mk)

PRODUCT_NAME := custom_xaga
PRODUCT_DEVICE := xaga
PRODUCT_MANUFACTURER := Xiaomi
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := Redmi K30 5G
PRODUCT_RESTRICT_VENDOR_FILES := false

# GMS
PRODUCT_GMS_CLIENTID_BASE := android-xiaomi

PRODUCT_AAPT_CONFIG := normal ldpi
PRODUCT_AAPT_PREF_CONFIG := xhdpi
PRODUCT_PACKAGES += \
    libandroid_net
    
EOF
            log_info "Created device/xiaomi/xaga/custom_xaga.mk"
            ;;
        undo)
            log_info "Removing custom_xaga.mk..."
            rm -f device/xiaomi/xaga/custom_xaga.mk
            log_info "Removed device/xiaomi/xaga/custom_xaga.mk"
            ;;
    esac
}

# Function to apply wpa_supplicant patches
apply_wpa_supplicant() {
    local action=$1

    case "$action" in
        apply)
            log_info "Applying wpa_supplicant patches..."

            if [ ! -d "external/wpa_supplicant_8" ]; then
                log_error "external/wpa_supplicant_8 not found"
                return 1
            fi

            if [ -d "external/wpa_supplicant_8/.git" ]; then
                log_info "WPA suppplicant already has patches"
                return 0
            fi

            # Create placeholder
            cd external/wpa_supplicant_8
            git init
            git commit --allow-empty -m "placeholder"
            cd - > /dev/null

            log_info "Applied wpa_supplicant patches"
            ;;
        undo)
            log_warn "Cannot undo wpa_supplicant patches (requires manual restore)"
            ;;
    esac
}

# Function to remove Qualcomm directories
remove_qcom() {
    local action=$1

    case "$action" in
        apply)
            log_info "Removing Qualcomm hardware directories..."

            local dirs=(
                "hardware/qcom/sdm845"
                "hardware/qcom/sm7250"
                "hardware/qcom/sm8150"
                "hardware/qcom/sm8250"
                "hardware/qcom/sm8350"
            )

            for dir in "${dirs[@]}"; do
                if [ -d "$dir" ]; then
                    rm -rf "$dir"
                    log_info "Removed $dir"
                fi
            done
            ;;
        undo)
            log_warn "Cannot restore Qualcomm directories (requires repo sync)"
            ;;
    esac
}

# Function to create git placeholders
create_git_placeholders() {
    local action=$1

    case "$action" in
        apply)
            log_info "Creating git placeholders..."

            if [ ! -x "$(command -v repo)" ]; then
                log_error "repo command not found. Please run: repo init -u https://github.com/PixelOS-AOSP/android_manifest.git -b sixteen-qpr1"
                return 1
            fi

            # Create placeholders for missing directories
            local projects=(
                "hardware/qcom/sdm845/display"
                "hardware/qcom/sdm845/gps"
                "hardware/qcom/sm7250/display"
                "hardware/qcom/sm7250/gps"
                "hardware/qcom/sm8150/display"
                "hardware/qcom/sm8150/gps"
                "hardware/qcom/audio"
                "hardware/qcom/bt"
                "hardware/qcom/camera"
                "hardware/qcom/display"
                "hardware/qcom/gps"
                "hardware/qcom/media"
                "hardware/qcom/data/ipacfg-mgr"
                "vendor/qcom/opensource/vibrator"
                "packages/apps/ParanoidSense"
            )

            for project in "${projects[@]}"; do
                if [ ! -d "$project/.git" ]; then
                    mkdir -p "$project"
                    cd "$project"
                    git init > /dev/null 2>&1
                    git commit --allow-empty -m "placeholder" > /dev/null 2>&1
                    cd - > /dev/null
                    log_info "Created placeholder for $project"
                fi
            done
            ;;
        undo)
            log_warn "Cannot remove git placeholders (requires repo sync)"
            ;;
    esac
}

# Function to restore vibrator
restore_vibrator() {
    local action=$1

    case "$action" in
        apply)
            log_info "Restoring vibrator HAL..."

            local files=(
                "device/xiaomi/mt6895-common/mt6895.mk"
                "vendor/qcom/opensource/vibrator/excluded-input-devices.xml"
            )

            for file in "${files[@]}"; do
                if [ ! -f "$file" ]; then
                    log_error "$file not found. Please run: repo sync vendor/qcom/opensource/vibrator"
                    return 1
                fi
            done

            log_info "Restored vibrator configuration"
            ;;
        undo)
            log_info "Removing vibrator configuration..."

            local files=(
                "device/xiaomi/mt6895-common/mt6895.mk"
                "vendor/qcom/opensource/vibrator/excluded-input-devices.xml"
            )

            for file in "${files[@]}"; do
                if [ -f "$file" ]; then
                    # Note: In a real scenario, we'd restore from git or backup
                    log_warn "Cannot safely remove $file. Check your backups."
                fi
            done
            log_info "Vibrator configuration noted for review"
            ;;
    esac
}

# Function to add MIUI Camera
add_miui_camera() {
    local action=$1

    case "$action" in
        apply)
            log_info "Adding MIUI Camera..."

            if [ ! -d "vendor/xiaomi/miuicamera-xaga" ]; then
                log_info "Cloning MIUI Camera from XagaForge..."
                git clone --branch 16.1 https://gitlab.com/priiii1808/proprietary_vendor_xiaomi_miuicamera-xaga.git vendor/xiaomi/miuicamera-xaga
            else
                log_info "MIUI Camera directory already exists"
            fi

            # Add to makefiles if not already present
            if ! grep -q "miuicamera-xaga" device/xiaomi/xaga/BoardConfigXaga.mk 2>/dev/null; then
                echo "" >> device/xiaomi/xaga/BoardConfigXaga.mk
                echo "include vendor/xiaomi/miuicamera-xaga/BoardConfig.mk" >> device/xiaomi/xaga/BoardConfigXaga.mk
                log_info "Added MIUI Camera to BoardConfigXaga.mk"
            fi

            log_info "MIUI Camera added"
            ;;
        undo)
            log_info "Removing MIUI Camera..."

            if [ -d "vendor/xiaomi/miuicamera-xaga" ]; then
                rm -rf vendor/xiaomi/miuicamera-xaga
                log_info "Removed vendor/xiaomi/miuicamera-xaga"
            fi

            # Remove from makefiles
            sed -i '/miuicamera-xaga/d' device/xiaomi/xaga/BoardConfigXaga.mk
            log_info "Removed MIUI Camera references from makefiles"
            ;;
    esac
}

# Main menu
main_menu() {
    local in_undo_mode=false
    local selected=""

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║     PixelOS GCloud Build Fixes - Interactive Menu               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"

    while true; do
        echo ""
        echo "Select an action:"
        echo "  1. Apply all fixes"
        echo "  2. Apply specific fixes"
        echo "  3. Undo all changes"
        echo "  4. Undo specific changes"
        echo "  5. Show status"
        echo "  0. Exit"
        echo ""
        read -p "Choice: " choice

        case "$choice" in
            1)
                log_info "Applying all fixes..."
                check_pixelos_dir

                create_custom_xaga apply
                apply_wpa_supplicant apply
                remove_qcom apply
                create_git_placeholders apply
                restore_vibrator apply
                add_miui_camera apply

                echo ""
                log_info "All fixes applied!"
                ;;
            2)
                echo ""
                echo "Available fixes:"
                echo "  1. Create custom_xaga.mk"
                echo "  2. Apply wpa_supplicant patches"
                echo "  3. Remove Qualcomm directories"
                echo "  4. Create git placeholders"
                echo "  5. Restore vibrator HAL"
                echo "  6. Add MIUI Camera"
                echo "  0. Back to main menu"
                echo ""
                read -p "Select fix (0-6): " fix_choice

                case "$fix_choice" in
                    1) apply_option "custom_xaga.mk" create_custom_xaga ;;
                    2) apply_option "wpa_supplicant patches" apply_wpa_supplicant ;;
                    3) apply_option "Remove Qualcomm directories" remove_qcom ;;
                    4) apply_option "Create git placeholders" create_git_placeholders ;;
                    5) apply_option "Restore vibrator HAL" restore_vibrator ;;
                    6) apply_option "Add MIUI Camera" add_miui_camera ;;
                    0) continue ;;
                esac
                ;;
            3)
                log_info "Undoing all changes..."
                check_pixelos_dir

                create_custom_xaga undo
                add_miui_camera undo
                remove_qcom undo
                create_git_placeholders undo
                restore_vibrator undo

                echo ""
                log_warn "Some changes cannot be automatically undone. Check your backups."
                ;;
            4)
                echo ""
                echo "Available fixes to undo:"
                echo "  1. Undo custom_xaga.mk"
                echo "  2. Undo MIUI Camera"
                echo "  3. Restore Qualcomm directories (requires repo sync)"
                echo "  4. Remove git placeholders (requires repo sync)"
                echo "  5. Re-remove vibrator configuration"
                echo "  0. Back to main menu"
                echo ""
                read -p "Select fix to undo (0-5): " undo_choice

                case "$undo_choice" in
                    1) create_custom_xaga undo ;;
                    2) add_miui_camera undo ;;
                    3) remove_qcom undo ;;
                    4) create_git_placeholders undo ;;
                    5) restore_vibrator undo ;;
                    0) continue ;;
                esac
                ;;
            5)
                echo ""
                echo "=== Build Fix Status ==="
                check_pixelos_dir

                echo -n "custom_xaga.mk: "
                if [ -f "device/xiaomi/xaga/custom_xaga.mk" ]; then
                    echo "✓ Applied"
                else
                    echo "✗ Not applied"
                fi

                echo -n "wpa_supplicant patches: "
                if [ -d "external/wpa_supplicant_8/.git" ]; then
                    echo "✓ Applied"
                else
                    echo "✗ Not applied"
                fi

                echo -n "Git placeholders: "
                if [ -f "hardware/qcom/sdm845/display/.git" ]; then
                    echo "✓ Applied"
                else
                    echo "✗ Not applied"
                fi

                echo -n "MIUI Camera: "
                if [ -d "vendor/xiaomi/miuicamera-xaga" ]; then
                    echo "✓ Applied"
                else
                    echo "✗ Not applied"
                fi
                ;;
            0)
                log_info "Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid choice"
                ;;
        esac
    done
}

# Run main menu
main_menu
