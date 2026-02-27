# PIXELOS16

# PixelOS

This is a github project which will be cloned into linux vm and used to build PixelOS 16 for xaga device. while this git repo also exist on windows machine. where the ai agent is running.

## Getting Started

To get started with the PixelOS source code, you'll need to be
familiar with [Git and Repo](https://source.android.com/setup/build/downloading).

To initialize your local repository, run:

```bash
repo init -u https://github.com/PixelOS-AOSP/android_manifest.git -b sixteen-qpr2 --git-lfs
```

Then, sync the repository:

```bash
repo sync
```

## Building the System

Initialize the ROM build environment by sourcing the envsetup.sh script:

```bash
source build/envsetup.sh
```

After cloning the device-specific sources, use breakfast to configure the build for your device:

```bash
breakfast xaga user
```

Start the compilation:

```
make installclean
```

```bash
source build/envsetup.sh
export IS_OFFICIAL=true
bash build_xaga.sh --mode ota-extract --sign --keys-dir ~/android-keys --upload --upload-scope fastboot 

--variant userdebug
 
```

```
cd frameworks/base && bash ../../apply_animation_fixes.sh && git add -A && git commit -m "Fix Settings UI jitter with AresOS animation patches"
```
## Build Notes

### Vibrator HAL
The Vibrator HAL (`vendor/qcom/opensource/vibrator`) and its configuration in `device/xiaomi/mt6895-common/mt6895.mk` and `excluded-input-devices.xml` are **REQUIRED** for vibration to work. 

**Do not remove them** even if they appear to be Qualcomm-specific blobs. The MediaTek device tree depends on them for proper vibration functionality.

## OTA Releases Repo

The OTA releases repository is now cloned at:

`pixelos-releases`

Use that repo to host your updater feed file (`updates.json`) and release ZIP links.

### Sample `updates.json`

```json
{
  "response": [
    {
      "datetime": 1739923200,
      "filename": "PixelOS_xaga-16.0-20260219-UNOFFICIAL.zip",
      "id": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "romtype": "UNOFFICIAL",
      "size": 2684354560,
      "url": "https://your-domain.example/xaga/PixelOS_xaga-16.0-20260219-UNOFFICIAL.zip",
      "version": "16.0"
    }
  ]
}
```

Set the Updater app server URL to the raw/static URL of this JSON file.

### Auto-generate updater feed after build

`build_xaga.sh` can now auto-generate updater JSON from the built OTA ZIP
(datetime, filename, sha256, size, URL, version).

Example for official-style per-device feed:

```bash
export IS_OFFICIAL=true
bash build_xaga.sh \
  --mode ota-extract \
  --sign \
  --upload \
  --updater-json API/updater/xaga.json \
  --release-repo ../pixelos-releases
```

Without `--upload`, provide a URL base:

```bash
bash build_xaga.sh \
  --mode ota-extract \
  --ota-url-base https://sourceforge.net/projects/pixelos-releases/files/sixteen/xaga \
  --updater-json API/updater/xaga.json \
  --release-repo ../pixelos-releases
```
