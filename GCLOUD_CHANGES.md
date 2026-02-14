rm -rf packages/apps/ParanoidSense

## Disable ParanoidSense `libmegface` Conflict (MTK Xiaomi)

### Issue

Build fails with duplicate module error:


**Cause:**

- Xiaomi MTK devices already ship Megvii face unlock HAL (`hardware/xiaomi/megvii`)
- ParanoidSense also includes a prebuilt `libmegface`
- Soong loads both → duplicate module conflict

---

### Resolution

Disable only the ParanoidSense `libmegface` module while keeping the AIDL interfaces intact.

This preserves framework dependencies but removes the duplicate library.

---

### Files Modified


---

### Changes Applied

#### 1) Remove dependency reference

Inside the `required:` block:

```diff
- "libmegface",
+ // "libmegface",
// cc_prebuilt_library_shared {
//     name: "libmegface",
//     src: ["prebuilts/libmegface.so"],
//     vendor: true,
//     strip: {
//         none: true,
//     },
// }
```

---

## Apply AresOS Animation Jitter Fixes

### Issue

Settings UI experiences jitter/stuttering on xaga device due to animation timing bugs and suboptimal activity transitions.

### Resolution

Apply two patches from AresOS that:
1. Replace stock animations with smoother slide+fade transitions (500ms slide, 150ms fade)
2. Fix inverted flag logic and wrong timebase in animation timing system

### Action Required

**Run this script after every `repo sync`:**

```bash
cd frameworks/base
bash ../../apply_animation_fixes.sh
git add -A
git commit -m "Fix Settings UI jitter with AresOS animation patches"
```

### Enable Smooth Animations

Add to device tree `system.prop`:
```
persist.sys.activity_anim_perf_override=true
```

### References

- Commit 1: `016692e508566188718302daf55e162ffa579daa` - New activity animation override
- Commit 2: `c7cbb45447fd44634bb215879d96799404943d25` - Fix inverted flag logic
- Source: https://github.com/AresOS-AOSP/android_frameworks_base
