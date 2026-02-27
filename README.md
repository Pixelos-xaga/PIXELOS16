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

```
m fb_package pixelos 
```


Start the compilation:

```
make installclean
```

```
cd frameworks/base && bash ../../apply_animation_fixes.sh && git add -A && git commit -m "Fix Settings UI jitter with AresOS animation patches"
```
