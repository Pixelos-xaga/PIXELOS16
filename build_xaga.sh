#!/usr/bin/env bash
# Keep strict error handling, but avoid nounset because AOSP envsetup/breakfast
# scripts can reference unset vars (for example TOP) during initialization.
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT_DIR}"

DEVICE="xaga"
VARIANT="user"
MODE="super"
CPU_COUNT="$(nproc)"
JOBS="$((CPU_COUNT * 2))"
KEYS_DIR=""
SIGN=false
GENERATE_KEYS=false
UPLOAD=false
UPLOAD_ONLY=false
GCS_BUCKET="pixelos-downloads-angxddeep"
GCS_PREFIX="sixteen"
UPLOAD_SCOPE="both"

PRODUCT_OUT=""
TARGET_FILES_DIR=""
SIGNED_OTA=""
DO_SIGN=false
BUILD_SIGN_STATE="unsigned"

usage() {
  cat <<'EOF'
Usage: ./build_xaga.sh [options]

Options:
  --mode <super|ota-extract>   Build mode (default: super)
  --device <codename>          Device codename (default: xaga)
  --variant <user|userdebug>   Build variant (default: user)
  --jobs <n>                   Parallel jobs for m (default: 2 * nproc)
  --keys-dir <path>            Release keys dir for signing target-files
  --sign                       Sign OTA/images output (ota-extract mode)
  --generate-keys              Generate missing keys in --keys-dir
  --upload                     Upload detected build artifacts to GCS
  --upload-only                Upload only (skip build)
  --bucket <name>              GCS bucket name (default: pixelos-downloads-angxddeep)
  --gcs-prefix <path>          Bucket prefix path (default: sixteen)
  --upload-scope <both|ota|fastboot>
                               Which artifacts to upload (default: both)
  -h, --help                   Show this help

Examples:
  ./build_xaga.sh --mode super
  ./build_xaga.sh --mode ota-extract
  ./build_xaga.sh --mode ota-extract --sign
  ./build_xaga.sh --mode ota-extract --sign --generate-keys
  ./build_xaga.sh --mode ota-extract --keys-dir ~/android-keys
  ./build_xaga.sh --mode ota-extract --sign --upload --bucket my-bucket
  ./build_xaga.sh --upload-only --bucket my-bucket --upload-scope both
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --variant)
      VARIANT="$2"
      shift 2
      ;;
    --jobs)
      JOBS="$2"
      shift 2
      ;;
    --keys-dir)
      KEYS_DIR="$2"
      shift 2
      ;;
    --sign)
      SIGN=true
      shift
      ;;
    --generate-keys)
      GENERATE_KEYS=true
      shift
      ;;
    --upload)
      UPLOAD=true
      shift
      ;;
    --upload-only)
      UPLOAD_ONLY=true
      shift
      ;;
    --bucket)
      GCS_BUCKET="$2"
      shift 2
      ;;
    --gcs-prefix)
      GCS_PREFIX="$2"
      shift 2
      ;;
    --upload-scope)
      UPLOAD_SCOPE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "${MODE}" != "super" && "${MODE}" != "ota-extract" ]]; then
  echo "Invalid mode: ${MODE}. Use super or ota-extract." >&2
  exit 1
fi

if [[ "${UPLOAD_SCOPE}" != "both" && "${UPLOAD_SCOPE}" != "ota" && "${UPLOAD_SCOPE}" != "fastboot" ]]; then
  echo "Invalid upload scope: ${UPLOAD_SCOPE}. Use both, ota, or fastboot." >&2
  exit 1
fi

if [[ "${UPLOAD_ONLY}" == true ]]; then
  UPLOAD=true
fi

if [[ "${SIGN}" == true && "${MODE}" != "ota-extract" ]]; then
  echo "--sign is only supported with --mode ota-extract." >&2
  exit 1
fi

if [[ "${SIGN}" == true && -z "${KEYS_DIR}" ]]; then
  KEYS_DIR="${HOME}/android-keys"
fi

if [[ "${SIGN}" == true || -n "${KEYS_DIR}" ]]; then
  DO_SIGN=true
fi

if [[ "${DO_SIGN}" == true && "${UPLOAD_ONLY}" != true ]]; then
  if [[ "${GENERATE_KEYS}" == true ]]; then
    "${ROOT_DIR}/setup_signing_keys.sh" --keys-dir "${KEYS_DIR}"
  fi

  REQUIRED_KEYS=(
    releasekey
    platform
    shared
    media
    networkstack
  )
  for key in "${REQUIRED_KEYS[@]}"; do
    if [[ ! -f "${KEYS_DIR}/${key}.pk8" || ! -f "${KEYS_DIR}/${key}.x509.pem" ]]; then
      echo "Missing key pair: ${KEYS_DIR}/${key}.pk8 and ${KEYS_DIR}/${key}.x509.pem" >&2
      echo "Use --generate-keys to create missing keys automatically." >&2
      exit 1
    fi
  done
fi

PRODUCT_OUT="out/target/product/${DEVICE}"
TARGET_FILES_DIR="out/target/product/${DEVICE}/obj/PACKAGING/target_files_intermediates"

make_fastboot_package_from_current_images() {
  local sign_state="$1"
  local package_dir="out/upload_packages"
  local package_name="PixelOS_${DEVICE}-$(date +%Y%m%d-%H%M)-FASTBOOT-${sign_state}.zip"
  local package_path="${package_dir}/${package_name}"
  local required_imgs=(
    boot.img
    vendor_boot.img
    super.img
    vbmeta.img
    vbmeta_system.img
    vbmeta_vendor.img
  )
  local img

  mkdir -p "${package_dir}"
  for img in "${required_imgs[@]}"; do
    if [[ ! -f "${PRODUCT_OUT}/${img}" ]]; then
      return 1
    fi
  done

  (
    cd "${PRODUCT_OUT}"
    zip -q -j "${ROOT_DIR}/${package_path}" "${required_imgs[@]}"
  )

  echo "${package_path}"
  return 0
}

detect_artifacts() {
  OTA_ARTIFACT=""
  FASTBOOT_ARTIFACT=""
  OTA_SIGN_STATE="unsigned"
  FASTBOOT_SIGN_STATE="${BUILD_SIGN_STATE}"
  local latest_ota=""

  if [[ -f "out/signed/signed-ota.zip" ]]; then
    OTA_ARTIFACT="out/signed/signed-ota.zip"
    OTA_SIGN_STATE="signed"
  else
    latest_ota="$(ls -1t "${PRODUCT_OUT}"/PixelOS_"${DEVICE}"*.zip 2>/dev/null | grep -v 'FASTBOOT' | head -n 1 || true)"
    if [[ -n "${latest_ota}" ]]; then
      OTA_ARTIFACT="${latest_ota}"
      if [[ "${OTA_ARTIFACT}" == *signed* || "${OTA_ARTIFACT}" == *SIGNED* ]]; then
        OTA_SIGN_STATE="signed"
      fi
    fi
  fi

  if [[ "${OTA_SIGN_STATE}" == "signed" ]]; then
    FASTBOOT_SIGN_STATE="signed"
  fi

  # Always create a fresh fastboot package from current images to match the
  # current build outputs and avoid reusing stale FASTBOOT zips.
  FASTBOOT_ARTIFACT="$(make_fastboot_package_from_current_images "${FASTBOOT_SIGN_STATE}" || true)"
}

upload_artifact() {
  local artifact="$1"
  local artifact_kind="$2"
  local sign_state="$3"
  local remote_base
  local remote_path

  if [[ -z "${artifact}" ]]; then
    return 1
  fi
  if [[ ! -f "${artifact}" ]]; then
    echo "Upload skipped (${artifact_kind}): missing file ${artifact}" >&2
    return 1
  fi

  remote_base="${GCS_PREFIX}/${DEVICE}/${artifact_kind}/${sign_state}"
  remote_base="${remote_base#/}"
  remote_base="${remote_base%/}"
  remote_path="gs://${GCS_BUCKET}/${remote_base}/$(basename "${artifact}")"

  echo "Uploading ${artifact_kind} (${sign_state}) -> ${remote_path}"
  gsutil cp "${artifact}" "${remote_path}"
  echo "Uploaded: ${remote_path}"
  echo "Public URL (if bucket/object is public): https://storage.googleapis.com/${GCS_BUCKET}/${remote_base}/$(basename "${artifact}")"
}

find_latest_target_files_zip() {
  local search_dirs=(
    "${TARGET_FILES_DIR}"
    "${PRODUCT_OUT}/obj/PACKAGING/target_files_intermediates"
    "out/dist"
  )
  local dir
  local file
  local candidates=()
  local newest=""
  local newest_mtime=0
  local mtime=0

  for dir in "${search_dirs[@]}"; do
    [[ -d "${dir}" ]] || continue
    while IFS= read -r file; do
      candidates+=("${file}")
    done < <(find "${dir}" -maxdepth 2 -type f -name "*target_files*.zip" 2>/dev/null)
  done

  for file in "${candidates[@]}"; do
    mtime="$(stat -c %Y "${file}" 2>/dev/null || echo 0)"
    if [[ "${mtime}" -gt "${newest_mtime}" ]]; then
      newest_mtime="${mtime}"
      newest="${file}"
    fi
  done

  [[ -n "${newest}" ]] || return 1
  echo "${newest}"
  return 0
}

if [[ "${UPLOAD_ONLY}" != true ]]; then
  if [[ ! -f build/envsetup.sh ]]; then
    echo "build/envsetup.sh not found. Run this from your Android source root." >&2
    exit 1
  fi

  echo "[1/4] Sourcing build environment"
  source build/envsetup.sh

  echo "[2/4] Running breakfast ${DEVICE} ${VARIANT}"
  breakfast "${DEVICE}" "${VARIANT}"

  if [[ "${MODE}" == "super" ]]; then
    echo "[3/4] Building superimage via m -j${JOBS} pixelos superimage"
    m -j"${JOBS}" pixelos superimage
    echo "[4/4] Build done. Check ${PRODUCT_OUT}"
  else
    echo "[3/4] Building target-files and otatools"
    m -j"${JOBS}" target-files-package otatools

    mkdir -p "${PRODUCT_OUT}"

    LATEST_TARGET_FILES="$(find_latest_target_files_zip || true)"
    if [[ -z "${LATEST_TARGET_FILES}" ]]; then
      echo "Could not find target-files zip. Searched: ${TARGET_FILES_DIR}, ${PRODUCT_OUT}/obj/PACKAGING/target_files_intermediates, out/dist" >&2
      exit 1
    fi

    EXTRACT_FROM_ZIP="${LATEST_TARGET_FILES}"

    if [[ "${DO_SIGN}" == true ]]; then
      mkdir -p out/signed
      SIGNED_TARGET_FILES="out/signed/signed-target_files.zip"
      SIGNED_OTA="out/signed/signed-ota.zip"

      echo "[4/4] Signing target-files with keys in ${KEYS_DIR}"
      out/host/linux-x86/bin/sign_target_files_apks -o \
        -d "${KEYS_DIR}" \
        "${LATEST_TARGET_FILES}" \
        "${SIGNED_TARGET_FILES}"

      out/host/linux-x86/bin/ota_from_target_files \
        -k "${KEYS_DIR}/releasekey" \
        "${SIGNED_TARGET_FILES}" \
        "${SIGNED_OTA}"

      EXTRACT_FROM_ZIP="${SIGNED_TARGET_FILES}"
      BUILD_SIGN_STATE="signed"
    fi

    EXTRACT_DIR="${PRODUCT_OUT}/images_from_target_files"
    rm -rf "${EXTRACT_DIR}"
    mkdir -p "${EXTRACT_DIR}"

    echo "Extracting IMAGES/*.img from: ${EXTRACT_FROM_ZIP}"
    unzip -oj "${EXTRACT_FROM_ZIP}" "IMAGES/*.img" -d "${EXTRACT_DIR}" >/dev/null

    echo "Copying extracted images into ${PRODUCT_OUT}"
    cp -af "${EXTRACT_DIR}"/*.img "${PRODUCT_OUT}/"

    [[ "${DO_SIGN}" == true ]] && BUILD_SIGN_STATE="signed"
  fi
fi

if [[ "${UPLOAD}" == true ]]; then
  if ! command -v gsutil >/dev/null 2>&1; then
    echo "gsutil not found. Install Google Cloud SDK / gsutil first." >&2
    exit 1
  fi

  detect_artifacts

  UPLOADED_ANY=false

  if [[ "${UPLOAD_SCOPE}" == "both" || "${UPLOAD_SCOPE}" == "ota" ]]; then
    if [[ -n "${OTA_ARTIFACT:-}" ]]; then
      upload_artifact "${OTA_ARTIFACT}" "ota" "${OTA_SIGN_STATE}" && UPLOADED_ANY=true
    else
      echo "No OTA artifact detected; skipped OTA upload."
    fi
  fi

  if [[ "${UPLOAD_SCOPE}" == "both" || "${UPLOAD_SCOPE}" == "fastboot" ]]; then
    if [[ -n "${FASTBOOT_ARTIFACT:-}" ]]; then
      upload_artifact "${FASTBOOT_ARTIFACT}" "fastboot" "${FASTBOOT_SIGN_STATE}" && UPLOADED_ANY=true
    else
      echo "No fastboot artifact detected; skipped fastboot upload."
    fi
  fi

  if [[ "${UPLOADED_ANY}" != true ]]; then
    echo "No artifacts were uploaded. Check build outputs and --upload-scope." >&2
    exit 1
  fi
fi

echo "Done."
