# GCloud Build Changes Log

This file tracks all modifications, deletions, and patches applied during PixelOS builds on Google Cloud.

> **Purpose**: New AI agents should read this file to understand what has been changed and why, to help debug future build errors.

> **Current Branch**: `sixteen-qpr1` (Android 16 QPR1) - Updated Jan 2026  
> **Manifest**: `https://github.com/PixelOS-AOSP/android_manifest.git` (new repo, the old `/manifest` was archived)  
> Available branches: `sixteen-qpr1` (default), `sixteen-qpr2`, `sixteen`

---

## Status Legend

| Status | Meaning |
|--------|---------|
| ✅ | Fix confirmed working |
| ⚠️ | Partial fix / workaround |
| 🔄 | Ongoing / needs monitoring |
| ❌ | Removed / reverted |

---

## Applied Changes

### 1. ✅ Created `custom_xaga.mk` Product Makefile

**Location**: `device/xiaomi/xaga/custom_xaga.mk`

**Reason**: The xiaomi-mt6895-devs device trees are built for LineageOS and only include `lineage_xaga.mk`. PixelOS sixteen-qpr1 requires a `custom_xaga.mk` file that inherits from `vendor/custom/config/common_full_phone.mk`.

> [!IMPORTANT]
> PixelOS changed naming in sixteen-qpr1:
> - Product prefix: `aosp_` → `custom_`
> - Vendor path: `vendor/aosp/` → `vendor/custom/`

**What it does**:
- Inherits PixelOS common configuration from `vendor/custom/`
- Sets correct product name (`custom_xaga`), brand, and fingerprint
- Enables GMS (Google Mobile Services)

---

### 5. ✅ Applied wpa_supplicant_8 Patches

**Location**: `external/wpa_supplicant_8`

**Patches applied**:
1. `39200b6c7b1f9ff1c1c6a6a5e4cd08c6f526d048` - MediaTek changes for WiFi support
2. `37a6e255d9d68fb483d12db550028749b280509b` - WAPI enablement

**Source**: `https://github.com/Nothing-2A/android_external_wpa_supplicant_8`

**Reason**: Standard AOSP wpa_supplicant doesn't support MediaTek's WiFi driver requirements.

---

### 6. ✅ Removed Qualcomm Hardware Directories

**Locations deleted**:
- `hardware/qcom/sdm845`
- `hardware/qcom/sm7250`
- `hardware/qcom/sm8150`
- `hardware/qcom/sm8250`
- `hardware/qcom/sm8350`

**Reason**: Broken symlinks / not needed for MediaTek builds. These cause build warnings/errors when they exist but aren't properly populated.
---

### 17. ✅ Created Git Placeholders for Deleted Repo Projects

**Locations**: Multiple deleted directories that `repo` still tracks:
- `hardware/qcom/sdm845/{display,gps}`
- `hardware/qcom/sm7250/{display,gps}`
- `hardware/qcom/sm8150/{display,gps}`
- `hardware/qcom/audio`, `bt`, `camera`, `display`, `gps`, `media`, `data/ipacfg-mgr`
- `vendor/qcom/opensource/vibrator`
- `packages/apps/ParanoidSense`

**Reason**: The `build-manifest.xml` build step runs `repo manifest -r` which needs every manifest project to be a valid git directory. Directories deleted by entries #4, #6, #8 caused `FileNotFoundError` crashes during this step.

**What was changed**:
```bash
# Create empty git repos at all missing project paths
repo list | while IFS=' : ' read -r path name; do
  path=$(echo "$path" | xargs)
  if [ -n "$path" ] && [ ! -d "$path/.git" ]; then
    mkdir -p "$path"
    git -C "$path" init && git -C "$path" commit --allow-empty -m "placeholder"
  fi
done
```

**Impact**: None on functionality. These are empty placeholder repos that satisfy `repo manifest` but contribute no code to the build.

---
### 19. ✅ Restored Vibrator HAL (Reverts Entry #10)

**Locations**: `device/xiaomi/mt6895-common/mt6895.mk`, `vendor/qcom/opensource/vibrator/excluded-input-devices.xml`

**Reason**: Entry #10 removed `vendor.qti.hardware.vibrator.service` and `excluded-input-devices.xml` assuming they were Qualcomm-specific. However, the xiaomi-mt6895-devs vendor blobs ship this vibrator HAL service. Removing it caused vibration to stop working entirely and the vibration settings to disappear.

**What was changed**:
- Restored `PRODUCT_PACKAGES += vendor.qti.hardware.vibrator.service` in `mt6895.mk`
- Restored `PRODUCT_COPY_FILES` for `excluded-input-devices.xml` in `mt6895.mk`
- Recreated `vendor/qcom/opensource/vibrator/excluded-input-devices.xml`
- Removed the `sed` commands from `build-pixelos.sh` that stripped these lines

**Impact**: Vibration now works. Vibration settings restored in Settings app.

---

### 20. ✅ Added MIUI Camera from XagaForge

**Locations**:
- `vendor/xiaomi/miuicamera-xaga/` — cloned from `gitlab.com/priiii1808/proprietary_vendor_xiaomi_miuicamera-xaga` (branch `16.1`)
- `device/xiaomi/xaga/custom_xaga.mk` — added `inherit-product` for `device.mk`
- `device/xiaomi/xaga/BoardConfigXaga.mk` — added `include` for `BoardConfig.mk`

**What was changed**: Cloned the MIUI Camera vendor package and integrated it into the device tree makefiles so it gets included in the build.

**Impact**: MIUI Camera app is now included in the ROM build

---

### 22. ✅ Restored Vibrator Source Code (Reverts Entry #4)

**Locations**: `vendor/qcom/opensource/vibrator`

**Reason**: The build failed with `includes non-existent modules in PRODUCT_PACKAGES: vendor.qti.hardware.vibrator.service`. This confirms that the MediaTek device tree expects to build the Qualcomm vibrator HAL from Use, not just use a prebuilt. Entry #4 had deleted this directory.

**What was changed**:
- Commented out the `rm -rf vendor/qcom/opensource/vibrator` block in `scripts/build-pixelos.sh`.
- Instructed user to restore the directory via `repo sync`.

**Impact**: Builds can now compile the vibrator HAL service required by the device tree.

---
