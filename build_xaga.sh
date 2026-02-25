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
LINEAGE_KEYS_DIR="${ROOT_DIR}/vendor/lineage-priv/keys"
LINEAGE_KEYS_DIR_LEGACY="${ROOT_DIR}/vendor/lineage-priv"
SIGN=false
GENERATE_KEYS=false
UPLOAD=false
UPLOAD_ONLY=false
GCS_BUCKET="pixelos-downloads-angxddeep"
GCS_PREFIX="sixteen"
UPLOAD_SCOPE="both"
UPLOAD_SCOPE_SET=false
GENERATE_UPDATER_JSON=true
RELEASES_REPO="${ROOT_DIR}/../pixelos-releases"
UPDATER_JSON_REL_PATH="updates.json"
OTA_URL_BASE=""
ROMTYPE_OVERRIDE=""

PRODUCT_OUT=""
TARGET_FILES_DIR=""
SIGNED_OTA=""
FASTBOOT_ARTIFACT=""
DO_SIGN=false
BUILD_SIGN_STATE="unsigned"
BUILD_NUMBER=""
OTA_PUBLIC_URL=""
OTA_REMOTE_BASE=""
FASTBOOT_REQUIRED_IMAGES=(
  super.img
  boot.img
  vendor_boot.img
  dtbo.img
  vbmeta.img
  vbmeta_system.img
  vbmeta_vendor.img
)
OTA_COMPANION_IMAGES=(
  boot.img
  vendor_boot.img
  dtbo.img
  vbmeta.img
)

usage() {
  cat <<'EOF'
Usage: ./build_xaga.sh [options]

Options:
  --mode <super|ota-extract|ota-only>
                               Build mode (default: super)
                               super: build superimage only
                               ota-extract: build OTA and prepare fastboot artifacts
                               ota-only: build OTA package only
  --device <codename>          Device codename (default: xaga)
  --variant <user|userdebug>   Build variant (default: user)
  --jobs <n>                   Parallel jobs for m (default: 2 * nproc)
  --keys-dir <path>            Release keys dir for inline signing
  --sign                       Enable PixelOS inline signing
  --generate-keys              Generate missing keys in --keys-dir
  --upload                     Upload detected build artifacts to GCS
  --upload-only                Upload only (skip build)
  --bucket <name>              GCS bucket name (default: pixelos-downloads-angxddeep)
  --gcs-prefix <path>          Bucket prefix path (default: sixteen)
  --upload-scope <both|ota|fastboot>
                               Which artifacts to upload (default: both)
  --generate-updater-json      Auto-generate updater JSON from OTA artifact (default: enabled)
  --no-generate-updater-json   Disable updater JSON generation
  --release-repo <path>        OTA feed repo path (default: ../pixelos-releases)
  --updater-json <relpath>     Output path relative to release repo (default: updates.json)
  --ota-url-base <url>         Base URL for OTA zip if not uploading (appends OTA filename)
  --romtype <OFFICIAL|UNOFFICIAL>
                               Override romtype in generated updater JSON
  -h, --help                   Show this help

Examples:
  ./build_xaga.sh --mode super
  ./build_xaga.sh --mode ota-extract
  ./build_xaga.sh --mode ota-only
  ./build_xaga.sh --mode ota-extract --sign
  ./build_xaga.sh --mode ota-extract --sign --generate-keys
  ./build_xaga.sh --mode ota-extract --keys-dir vendor/lineage-priv/keys
  ./build_xaga.sh --mode ota-extract --sign --upload --bucket my-bucket
  ./build_xaga.sh --upload-only --bucket my-bucket --upload-scope both
  ./build_xaga.sh --mode ota-extract --ota-url-base https://sourceforge.net/projects/pixelos-releases/files/sixteen/xaga
  ./build_xaga.sh --mode ota-extract --updater-json API/updater/xaga.json
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
      UPLOAD_SCOPE_SET=true
      shift 2
      ;;
    --generate-updater-json)
      GENERATE_UPDATER_JSON=true
      shift
      ;;
    --no-generate-updater-json)
      GENERATE_UPDATER_JSON=false
      shift
      ;;
    --release-repo)
      RELEASES_REPO="$2"
      shift 2
      ;;
    --updater-json)
      UPDATER_JSON_REL_PATH="$2"
      shift 2
      ;;
    --ota-url-base)
      OTA_URL_BASE="$2"
      shift 2
      ;;
    --romtype)
      ROMTYPE_OVERRIDE="$2"
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

if [[ "${MODE}" == "ota" ]]; then
  MODE="ota-only"
fi

if [[ "${MODE}" != "super" && "${MODE}" != "ota-extract" && "${MODE}" != "ota-only" ]]; then
  echo "Invalid mode: ${MODE}. Use super, ota-extract, or ota-only." >&2
  exit 1
fi

if [[ "${UPLOAD_SCOPE}" != "both" && "${UPLOAD_SCOPE}" != "ota" && "${UPLOAD_SCOPE}" != "fastboot" ]]; then
  echo "Invalid upload scope: ${UPLOAD_SCOPE}. Use both, ota, or fastboot." >&2
  exit 1
fi

if [[ "${UPLOAD_ONLY}" == true ]]; then
  UPLOAD=true
fi

if [[ "${MODE}" == "ota-only" ]]; then
  if [[ "${UPLOAD_SCOPE}" != "ota" ]]; then
    if [[ "${UPLOAD_SCOPE_SET}" == true ]]; then
      echo "Mode ota-only only supports OTA upload. Overriding --upload-scope=${UPLOAD_SCOPE} to ota."
    fi
    UPLOAD_SCOPE="ota"
  fi
fi

if [[ -d "${LINEAGE_KEYS_DIR}" ]]; then
  DEFAULT_LINEAGE_KEYS_DIR="${LINEAGE_KEYS_DIR}"
else
  DEFAULT_LINEAGE_KEYS_DIR="${LINEAGE_KEYS_DIR_LEGACY}"
fi

if [[ -n "${KEYS_DIR}" && "${KEYS_DIR}" != "${LINEAGE_KEYS_DIR}" && "${KEYS_DIR}" != "${LINEAGE_KEYS_DIR_LEGACY}" ]]; then
  echo "Ignoring --keys-dir=${KEYS_DIR}; using in-tree lineage keys only." >&2
  KEYS_DIR="${DEFAULT_LINEAGE_KEYS_DIR}"
fi

if [[ "${SIGN}" == true ]]; then
  KEYS_DIR="${DEFAULT_LINEAGE_KEYS_DIR}"
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

prepare_inline_signing_keys() {
  local inline_keys_dir="vendor/lineage-priv/keys"
  local inline_keys_dir_abs=""
  local source_keys_dir_abs=""
  local key
  local optional_keys=(
    testkey
    testcert
  )

  if [[ "${DO_SIGN}" != true ]]; then
    return 0
  fi

  mkdir -p "${inline_keys_dir}"
  inline_keys_dir_abs="$(readlink -f "${inline_keys_dir}" 2>/dev/null || true)"
  source_keys_dir_abs="$(readlink -f "${KEYS_DIR}" 2>/dev/null || true)"
  if [[ -n "${inline_keys_dir_abs}" && -n "${source_keys_dir_abs}" && "${inline_keys_dir_abs}" == "${source_keys_dir_abs}" ]]; then
    echo "Inline signing enabled with in-tree lineage keys at ${inline_keys_dir}"
    return 0
  fi

  for key in "${REQUIRED_KEYS[@]}"; do
    ln -sfn "${KEYS_DIR}/${key}.pk8" "${inline_keys_dir}/${key}.pk8"
    ln -sfn "${KEYS_DIR}/${key}.x509.pem" "${inline_keys_dir}/${key}.x509.pem"
  done
  for key in "${optional_keys[@]}"; do
    if [[ -f "${KEYS_DIR}/${key}.pk8" && -f "${KEYS_DIR}/${key}.x509.pem" ]]; then
      ln -sfn "${KEYS_DIR}/${key}.pk8" "${inline_keys_dir}/${key}.pk8"
      ln -sfn "${KEYS_DIR}/${key}.x509.pem" "${inline_keys_dir}/${key}.x509.pem"
    fi
  done

  if [[ ! -f "${inline_keys_dir}/keys.mk" ]]; then
    cat > "${inline_keys_dir}/keys.mk" <<'EOF'
PRODUCT_DEFAULT_DEV_CERTIFICATE := vendor/lineage-priv/keys/releasekey
EOF
  fi

  if [[ ! -f "${inline_keys_dir}/BUILD.bazel" ]]; then
    cat > "${inline_keys_dir}/BUILD.bazel" <<'EOF'
filegroup(
    name = "android_certificate_directory",
    srcs = glob([
        "*.pk8",
        "*.pem",
    ]),
    visibility = ["//visibility:public"],
)
EOF
  fi

  echo "Inline signing enabled with keys from ${KEYS_DIR} -> ${inline_keys_dir}"
}

PRODUCT_OUT="out/target/product/${DEVICE}"
TARGET_FILES_DIR="out/target/product/${DEVICE}/obj/PACKAGING/target_files_intermediates"

detect_artifacts() {
  OTA_ARTIFACT=""
  FASTBOOT_ARTIFACT=""
  OTA_SIGN_STATE="unsigned"
  FASTBOOT_SIGN_STATE="${BUILD_SIGN_STATE}"
  BUILD_NUMBER=""
  local file
  local candidates=()
  local newest=""
  local newest_mtime=0
  local mtime=0
  local fastboot_candidates=()
  local fastboot_newest=""
  local fastboot_newest_mtime=0

  if [[ -f "out/signed/signed-ota.zip" ]]; then
    candidates+=("out/signed/signed-ota.zip")
  fi
  while IFS= read -r file; do
    candidates+=("${file}")
  done < <(find "${PRODUCT_OUT}" "out/dist" "out/signed" -maxdepth 2 -type f \( -name "PixelOS_${DEVICE}*.zip" -o -name "PIXELOS_*.zip" -o -name "*${DEVICE}*ota*.zip" \) ! -name "*FASTBOOT*" ! -name "*target_files*" 2>/dev/null)

  for file in "${candidates[@]}"; do
    [[ -f "${file}" ]] || continue
    mtime="$(stat -c %Y "${file}" 2>/dev/null || echo 0)"
    if [[ "${mtime}" -gt "${newest_mtime}" ]]; then
      newest_mtime="${mtime}"
      newest="${file}"
    fi
  done

  if [[ -n "${newest}" ]]; then
    OTA_ARTIFACT="${newest}"
    if [[ "${DO_SIGN}" == true || "${OTA_ARTIFACT}" == *signed* || "${OTA_ARTIFACT}" == *SIGNED* ]]; then
      OTA_SIGN_STATE="signed"
    fi
  fi

  if [[ -f "${PRODUCT_OUT}/fastboot.zip" ]]; then
    fastboot_candidates+=("${PRODUCT_OUT}/fastboot.zip")
  fi
  while IFS= read -r file; do
    fastboot_candidates+=("${file}")
  done < <(find "${PRODUCT_OUT}" "out/dist" -maxdepth 2 -type f \( -name "*fastboot*.zip" -o -name "*FASTBOOT*.zip" \) ! -name "*target_files*" 2>/dev/null)

  for file in "${fastboot_candidates[@]}"; do
    [[ -f "${file}" ]] || continue
    mtime="$(stat -c %Y "${file}" 2>/dev/null || echo 0)"
    if [[ "${mtime}" -gt "${fastboot_newest_mtime}" ]]; then
      fastboot_newest_mtime="${mtime}"
      fastboot_newest="${file}"
    fi
  done
  if [[ -n "${fastboot_newest}" ]]; then
    FASTBOOT_ARTIFACT="${fastboot_newest}"
  fi

  if [[ "${OTA_SIGN_STATE}" == "signed" ]]; then
    FASTBOOT_SIGN_STATE="signed"
  fi

  if [[ -n "${OTA_ARTIFACT}" ]]; then
    local ota_base
    ota_base="$(basename "${OTA_ARTIFACT}")"
    if [[ "${ota_base}" =~ ([0-9]{8}-[0-9]{4}) ]]; then
      BUILD_NUMBER="${BASH_REMATCH[1]}"
    elif [[ "${ota_base}" =~ ([0-9]{8}) ]]; then
      BUILD_NUMBER="${BASH_REMATCH[1]}"
    fi
  elif [[ -n "${FASTBOOT_ARTIFACT}" ]]; then
    local fastboot_base
    fastboot_base="$(basename "${FASTBOOT_ARTIFACT}")"
    if [[ "${fastboot_base}" =~ ([0-9]{8}-[0-9]{4}) ]]; then
      BUILD_NUMBER="${BASH_REMATCH[1]}"
    elif [[ "${fastboot_base}" =~ ([0-9]{8}) ]]; then
      BUILD_NUMBER="${BASH_REMATCH[1]}"
    fi
  fi
  [[ -n "${BUILD_NUMBER}" ]] || BUILD_NUMBER="$(date +%Y%m%d-%H%M)"
}

normalize_ota_artifact_name() {
  local artifact="$1"
  local artifact_dir=""
  local artifact_name=""
  local artifact_build=""

  if [[ -z "${artifact}" || ! -f "${artifact}" ]]; then
    return 1
  fi

  artifact_dir="$(dirname "${artifact}")"
  artifact_name="$(basename "${artifact}")"

  if [[ "${artifact_name}" =~ ([0-9]{8}-[0-9]{4}) ]]; then
    artifact_build="${BASH_REMATCH[1]}"
  elif [[ "${artifact_name}" =~ ([0-9]{8}) ]]; then
    artifact_build="${BASH_REMATCH[1]}"
  elif [[ -n "${BUILD_NUMBER}" ]]; then
    artifact_build="${BUILD_NUMBER}"
  else
    artifact_build="$(date +%Y%m%d-%H%M)"
  fi

  OTA_ARTIFACT="${artifact}"
  BUILD_NUMBER="${artifact_build}"
  echo "Prepared OTA release artifact: ${artifact_name}"
  return 0
}

upload_artifact() {
  local artifact="$1"
  local artifact_kind="$2"
  local artifact_name=""
  local remote_base
  local remote_path

  if [[ -z "${artifact}" ]]; then
    return 1
  fi
  if [[ ! -f "${artifact}" ]]; then
    echo "Upload skipped (${artifact_kind}): missing file ${artifact}" >&2
    return 1
  fi

  remote_base="${GCS_PREFIX}/${DEVICE}/${BUILD_NUMBER}/${artifact_kind}"
  remote_base="${remote_base#/}"
  remote_base="${remote_base%/}"
  artifact_name="$(basename "${artifact}")"
  remote_path="gs://${GCS_BUCKET}/${remote_base}/${artifact_name}"

  echo "Uploading ${artifact_kind} -> ${remote_path}"
  gsutil cp "${artifact}" "${remote_path}"
  gsutil setmeta -h "Content-Disposition:attachment; filename=${artifact_name}" "${remote_path}" >/dev/null 2>&1 || \
    echo "Warning: failed to set Content-Disposition metadata for ${remote_path}"
  echo "Uploaded: ${remote_path}"
  local public_url="https://storage.googleapis.com/${GCS_BUCKET}/${remote_base}/${artifact_name}"
  echo "Public URL (if bucket/object is public): ${public_url}"
  if [[ "${artifact_kind}" == "ota" ]]; then
    OTA_PUBLIC_URL="${public_url}"
    OTA_REMOTE_BASE="${remote_base}"
  fi
}

detect_rom_version_from_ota_name() {
  local ota_name="$1"
  if [[ "${ota_name}" =~ -([0-9]+\.[0-9]+)- ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "${ota_name}" =~ -([0-9]+)- ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  echo "16"
}

resolve_ota_download_url() {
  local ota_name="$1"
  if [[ -n "${OTA_PUBLIC_URL}" ]]; then
    echo "${OTA_PUBLIC_URL}"
    return 0
  fi
  if [[ -n "${OTA_URL_BASE}" ]]; then
    echo "${OTA_URL_BASE%/}/${ota_name}"
    return 0
  fi
  return 1
}

generate_updater_json() {
  local ota_path="$1"
  local ota_name=""
  local ota_size=""
  local ota_sha256=""
  local ota_datetime=""
  local ota_url=""
  local ota_version=""
  local romtype=""
  local output_path=""
  local output_dir=""

  if [[ -z "${ota_path}" || ! -f "${ota_path}" ]]; then
    echo "Updater JSON generation skipped: OTA artifact not found."
    return 0
  fi
  ota_name="$(basename "${ota_path}")"
  ota_size="$(stat -c %s "${ota_path}")"
  ota_datetime="$(stat -c %Y "${ota_path}")"
  ota_sha256="$(sha256sum "${ota_path}" | awk '{print $1}')"
  ota_version="$(detect_rom_version_from_ota_name "${ota_name}")"

  if ! ota_url="$(resolve_ota_download_url "${ota_name}")"; then
    echo "Updater JSON generation skipped: provide --ota-url-base or use --upload for automatic URL." >&2
    return 0
  fi

  if [[ -n "${ROMTYPE_OVERRIDE}" ]]; then
    romtype="${ROMTYPE_OVERRIDE}"
  elif [[ "${IS_OFFICIAL:-}" == "true" ]]; then
    romtype="OFFICIAL"
  else
    romtype="UNOFFICIAL"
  fi

  if [[ -d "${RELEASES_REPO}" ]]; then
    output_path="${RELEASES_REPO}/${UPDATER_JSON_REL_PATH}"
    output_dir="$(dirname "${output_path}")"
    echo "Updater JSON output repo: ${RELEASES_REPO}"
  else
    output_path="${PRODUCT_OUT}/${UPDATER_JSON_REL_PATH}"
    output_dir="$(dirname "${output_path}")"
    echo "Updater JSON release repo not found at ${RELEASES_REPO}."
    echo "Falling back to local output: ${output_path}"
  fi
  mkdir -p "${output_dir}"

  cat > "${output_path}" <<EOF
{
  "response": [
    {
      "datetime": "${ota_datetime}",
      "filename": "${ota_name}",
      "id": "${ota_sha256}",
      "romtype": "${romtype}",
      "size": ${ota_size},
      "url": "${ota_url}",
      "version": ${ota_version}
    }
  ]
}
EOF

  echo "Generated updater JSON: ${output_path}"
  GENERATED_UPDATER_JSON_PATH="${output_path}"
}

upload_updater_json_to_ota_folder() {
  local json_path="$1"
  local json_name=""
  local json_remote_path=""

  if [[ -z "${json_path}" || ! -f "${json_path}" ]]; then
    echo "Updater JSON upload skipped: file not found."
    return 0
  fi
  if [[ -z "${OTA_REMOTE_BASE}" ]]; then
    echo "Updater JSON upload skipped: OTA remote path is unknown."
    return 0
  fi

  json_name="$(basename "${json_path}")"
  json_remote_path="gs://${GCS_BUCKET}/${OTA_REMOTE_BASE}/${json_name}"
  echo "Uploading updater JSON -> ${json_remote_path}"
  gsutil cp "${json_path}" "${json_remote_path}"
  gsutil setmeta -h "Content-Disposition:attachment; filename=${json_name}" "${json_remote_path}" >/dev/null 2>&1 || \
    echo "Warning: failed to set Content-Disposition metadata for ${json_remote_path}"
  echo "Uploaded updater JSON: ${json_remote_path}"
  echo "Updater JSON URL (if public): https://storage.googleapis.com/${GCS_BUCKET}/${OTA_REMOTE_BASE}/${json_name}"
}

resolve_ota_companion_image_path() {
  local img="$1"
  local file
  local newest=""
  local newest_mtime=0
  local mtime=0

  if [[ -f "${PRODUCT_OUT}/${img}" ]]; then
    echo "${PRODUCT_OUT}/${img}"
    return 0
  fi

  while IFS= read -r file; do
    [[ -f "${file}" ]] || continue
    mtime="$(stat -c %Y "${file}" 2>/dev/null || echo 0)"
    if [[ "${mtime}" -gt "${newest_mtime}" ]]; then
      newest_mtime="${mtime}"
      newest="${file}"
    fi
  done < <(find "${PRODUCT_OUT}" "out/dist" "out/signed" -maxdepth 2 -type f \( -name "${img}" -o -name "*_ota_${img}" \) ! -name "*FASTBOOT*" ! -name "*fastboot*" 2>/dev/null)

  [[ -n "${newest}" ]] || return 1
  echo "${newest}"
  return 0
}

prepare_ota_companion_images() {
  local missing=()
  local img
  local latest_target_files=""
  local extract_pattern=()

  for img in "${OTA_COMPANION_IMAGES[@]}"; do
    if [[ ! -f "${PRODUCT_OUT}/${img}" ]]; then
      missing+=("${img}")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  latest_target_files="$(find_latest_target_files_zip || true)"
  if [[ -n "${latest_target_files}" ]]; then
    echo "Preparing OTA companion images from ${latest_target_files}"
    for img in "${missing[@]}"; do
      extract_pattern+=("IMAGES/${img}")
    done
    unzip -oj "${latest_target_files}" "${extract_pattern[@]}" -d "${PRODUCT_OUT}" >/dev/null 2>&1 || true
  fi

  missing=()
  for img in "${OTA_COMPANION_IMAGES[@]}"; do
    if [[ ! -f "${PRODUCT_OUT}/${img}" ]]; then
      missing+=("${img}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "OTA companion upload skipped for missing images: ${missing[*]}"
    return 1
  fi

  return 0
}

upload_ota_companion_images() {
  local img
  local source_path=""
  local staged_path=""
  local remote_path=""
  local uploaded_any=false
  local release_dir="${ROOT_DIR}/out/release/${DEVICE}"

  if [[ -z "${OTA_REMOTE_BASE}" ]]; then
    echo "OTA companion upload skipped: OTA remote path is unknown."
    return 1
  fi

  prepare_ota_companion_images || true
  mkdir -p "${release_dir}"

  for img in "${OTA_COMPANION_IMAGES[@]}"; do
    if ! source_path="$(resolve_ota_companion_image_path "${img}")"; then
      echo "OTA companion upload skipped (${img}): source image not found."
      continue
    fi
    staged_path="${release_dir}/${img}"
    cp -f "${source_path}" "${staged_path}"

    remote_path="gs://${GCS_BUCKET}/${OTA_REMOTE_BASE}/${img}"
    echo "Uploading OTA companion (${img}) -> ${remote_path}"
    gsutil cp "${staged_path}" "${remote_path}"
    gsutil setmeta -h "Content-Disposition:attachment; filename=${img}" "${remote_path}" >/dev/null 2>&1 || \
      echo "Warning: failed to set Content-Disposition metadata for ${remote_path}"
    echo "Uploaded OTA companion: ${remote_path}"
    echo "Companion URL (if public): https://storage.googleapis.com/${GCS_BUCKET}/${OTA_REMOTE_BASE}/${img}"
    uploaded_any=true
  done

  if [[ "${uploaded_any}" != true ]]; then
    return 1
  fi
  return 0
}

package_fastboot_zip() {
  local zip_name="fastboot.zip"
  local zip_path="${PRODUCT_OUT}/${zip_name}"
  local img
  local missing=()
  local img_count="${#FASTBOOT_REQUIRED_IMAGES[@]}"
  local zip_size=""

  echo "[fastboot] Preparing ${zip_name} in ${PRODUCT_OUT}"
  echo "[fastboot] Checking required images (${img_count} files)"

  for img in "${FASTBOOT_REQUIRED_IMAGES[@]}"; do
    if [[ ! -f "${PRODUCT_OUT}/${img}" ]]; then
      missing+=("${img}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[fastboot] Cannot package ${zip_name}; missing images: ${missing[*]}" >&2
    return 1
  fi
  echo "[fastboot] Image check passed"

  if ! command -v zip >/dev/null 2>&1; then
    echo "[fastboot] zip not found. Install zip package to create ${zip_name}." >&2
    return 1
  fi

  rm -f "${zip_path}"
  echo "[fastboot] Creating ${zip_name} (compression: -9)"
  if ! (
    cd "${PRODUCT_OUT}"
    zip -q -9 "${zip_name}" "${FASTBOOT_REQUIRED_IMAGES[@]}"
  ); then
    echo "[fastboot] Failed to create ${zip_path}" >&2
    return 1
  fi
  zip_size="$(du -h "${zip_path}" 2>/dev/null | awk '{print $1}')"
  FASTBOOT_ARTIFACT="${zip_path}"
  echo "[fastboot] Created artifact: ${FASTBOOT_ARTIFACT}${zip_size:+ (${zip_size})}"
  return 0
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

extract_superimage_from_target_files() {
  local target_files_zip="$1"
  local output_super="${PRODUCT_OUT}/super.img"

  if [[ -z "${target_files_zip}" || ! -f "${target_files_zip}" ]]; then
    if [[ -f "${output_super}" ]]; then
      echo "Target-files zip not found; keeping existing ${output_super}."
      return 0
    fi
    echo "Cannot extract super.img: target-files zip not found and ${output_super} is missing." >&2
    return 1
  fi
  if ! unzip -l "${target_files_zip}" "IMAGES/super.img" >/dev/null 2>&1; then
    if [[ -f "${output_super}" ]]; then
      echo "IMAGES/super.img missing in ${target_files_zip}; keeping existing ${output_super}."
      return 0
    fi
    echo "Cannot extract super.img: IMAGES/super.img missing in ${target_files_zip} and ${output_super} is missing." >&2
    return 1
  fi

  echo "Extracting OTA super image from ${target_files_zip} -> ${output_super}"
  unzip -p "${target_files_zip}" "IMAGES/super.img" > "${output_super}"
  return 0
}

ensure_fastboot_images_present() {
  local missing=()
  local img

  for img in "${FASTBOOT_REQUIRED_IMAGES[@]}"; do
    if [[ ! -f "${PRODUCT_OUT}/${img}" ]]; then
      missing+=("${img}")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  echo "Missing fastboot images after extraction: ${missing[*]}"
  echo "Building missing image targets for fastboot package"
  m -j"${JOBS}" superimage bootimage vendorbootimage dtboimage vbmetaimage vbmeta_systemimage vbmeta_vendorimage

  missing=()
  for img in "${FASTBOOT_REQUIRED_IMAGES[@]}"; do
    if [[ ! -f "${PRODUCT_OUT}/${img}" ]]; then
      missing+=("${img}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Still missing required fastboot images: ${missing[*]}" >&2
    return 1
  fi

  return 0
}

if [[ "${UPLOAD_ONLY}" != true ]]; then
  if [[ ! -f build/envsetup.sh ]]; then
    echo "build/envsetup.sh not found. Run this from your Android source root." >&2
    exit 1
  fi

  echo "[1/4] Sourcing build environment"
  source build/envsetup.sh

  prepare_inline_signing_keys

  echo "[2/4] Running breakfast ${DEVICE} ${VARIANT}"
  breakfast "${DEVICE}" "${VARIANT}"

  if [[ "${MODE}" == "super" ]]; then
    echo "[3/4] Building superimage via m -j${JOBS} pixelos superimage"
    m -j"${JOBS}" pixelos superimage
    echo "[4/4] Build done. Check ${PRODUCT_OUT}"
  elif [[ "${MODE}" == "ota-extract" ]]; then
    echo "[3/4] Building OTA + fastboot image targets in one pass"
    m -j"${JOBS}" pixelos superimage target-files-package otapackage otatools

    mkdir -p "${PRODUCT_OUT}"
    [[ "${DO_SIGN}" == true ]] && BUILD_SIGN_STATE="signed"
    LATEST_TARGET_FILES="$(find_latest_target_files_zip || true)"

    missing_fastboot_images=()
    for img in "${FASTBOOT_REQUIRED_IMAGES[@]}"; do
      if [[ ! -f "${PRODUCT_OUT}/${img}" ]]; then
        missing_fastboot_images+=("${img}")
      fi
    done

    if [[ ${#missing_fastboot_images[@]} -gt 0 ]]; then
      if [[ -z "${LATEST_TARGET_FILES}" ]]; then
        echo "Could not find target-files zip for fallback extraction. Missing images: ${missing_fastboot_images[*]}" >&2
        echo "Searched: ${TARGET_FILES_DIR}, ${PRODUCT_OUT}/obj/PACKAGING/target_files_intermediates, out/dist" >&2
        exit 1
      fi

      EXTRACT_FROM_ZIP="${LATEST_TARGET_FILES}"
      EXTRACT_DIR="${PRODUCT_OUT}/images_from_target_files"
      rm -rf "${EXTRACT_DIR}"
      mkdir -p "${EXTRACT_DIR}"

      echo "Missing fastboot images from direct build (${missing_fastboot_images[*]})."
      echo "Fallback: extracting IMAGES/*.img from ${EXTRACT_FROM_ZIP}"
      unzip -oj "${EXTRACT_FROM_ZIP}" "IMAGES/*.img" -d "${EXTRACT_DIR}" >/dev/null

      echo "Copying extracted images into ${PRODUCT_OUT}"
      cp -af "${EXTRACT_DIR}"/*.img "${PRODUCT_OUT}/"
    else
      echo "Fastboot images already present in ${PRODUCT_OUT}; skipping target-files image extraction."
    fi

    ensure_fastboot_images_present

    extract_superimage_from_target_files "${LATEST_TARGET_FILES}"
  else
    echo "[3/4] Building OTA package targets only"
    m -j"${JOBS}" pixelos target-files-package otapackage otatools
    mkdir -p "${PRODUCT_OUT}"
    [[ "${DO_SIGN}" == true ]] && BUILD_SIGN_STATE="signed"
    echo "[4/4] OTA build done. Check ${PRODUCT_OUT}"
  fi
fi

if [[ "${UPLOAD}" == true ]]; then
  if ! command -v gsutil >/dev/null 2>&1; then
    echo "gsutil not found. Install Google Cloud SDK / gsutil first." >&2
    exit 1
  fi

  detect_artifacts
  if [[ -n "${OTA_ARTIFACT:-}" ]]; then
    normalize_ota_artifact_name "${OTA_ARTIFACT}"
  fi

  UPLOADED_ANY=false
  OTA_UPLOADED=false

  if [[ "${UPLOAD_SCOPE}" == "both" || "${UPLOAD_SCOPE}" == "ota" ]]; then
    if [[ -n "${OTA_ARTIFACT:-}" ]]; then
      if upload_artifact "${OTA_ARTIFACT}" "ota"; then
        UPLOADED_ANY=true
        OTA_UPLOADED=true
        upload_ota_companion_images || true
      fi
    else
      echo "No OTA artifact detected; skipped OTA upload."
    fi
  fi

  if [[ "${GENERATE_UPDATER_JSON}" == true && "${OTA_UPLOADED}" == true ]]; then
    generate_updater_json "${OTA_ARTIFACT:-}"
    upload_updater_json_to_ota_folder "${GENERATED_UPDATER_JSON_PATH:-}"
  fi

  if [[ "${UPLOAD_SCOPE}" == "both" || "${UPLOAD_SCOPE}" == "fastboot" ]]; then
    CAN_PACKAGE_FASTBOOT=true
    for img in "${FASTBOOT_REQUIRED_IMAGES[@]}"; do
      if [[ ! -f "${PRODUCT_OUT}/${img}" ]]; then
        CAN_PACKAGE_FASTBOOT=false
        break
      fi
    done

    FASTBOOT_UPLOAD_ARTIFACT="${FASTBOOT_ARTIFACT:-}"
    if [[ "${CAN_PACKAGE_FASTBOOT}" == true ]] && package_fastboot_zip; then
      FASTBOOT_UPLOAD_ARTIFACT="${FASTBOOT_ARTIFACT}"
    elif [[ -n "${FASTBOOT_UPLOAD_ARTIFACT}" && -f "${FASTBOOT_UPLOAD_ARTIFACT}" ]]; then
      echo "Using existing fastboot artifact: ${FASTBOOT_UPLOAD_ARTIFACT}"
    else
      FASTBOOT_UPLOAD_ARTIFACT=""
    fi

    if [[ -n "${FASTBOOT_UPLOAD_ARTIFACT}" ]] && upload_artifact "${FASTBOOT_UPLOAD_ARTIFACT}" "fastboot"; then
      UPLOADED_ANY=true
    else
      echo "No fastboot zip detected; skipped fastboot upload."
    fi
  fi

  if [[ "${UPLOADED_ANY}" != true ]]; then
    echo "No artifacts were uploaded. Check build outputs and --upload-scope." >&2
    exit 1
  fi
fi

if [[ "${UPLOAD}" != true && "${GENERATE_UPDATER_JSON}" == true ]]; then
  detect_artifacts
  if [[ -n "${OTA_ARTIFACT:-}" ]]; then
    normalize_ota_artifact_name "${OTA_ARTIFACT}"
  fi
  generate_updater_json "${OTA_ARTIFACT:-}"
fi

echo "Done."
