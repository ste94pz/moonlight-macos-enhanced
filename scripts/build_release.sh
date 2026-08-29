#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT="${REPO_ROOT}/Moonlight.xcodeproj"
readonly SCHEME="Moonlight for macOS"
readonly VERSION_CONFIG="${REPO_ROOT}/Limelight/Version.xcconfig"
readonly BUILD_DIR="${BUILD_DIR:-${REPO_ROOT}/build}"
readonly OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/dist}"
readonly DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${BUILD_DIR}}"
readonly OPENSSL_FRAMEWORK_DIR="${DERIVED_DATA_PATH}/SourcePackages/artifacts/openssl-package/OpenSSL/OpenSSL.xcframework/macos-arm64_x86_64"

usage() {
  cat <<'EOF'
Usage: ./scripts/build_release.sh [--debug] [--arch ARCH] [--dmg] [-- XCODEBUILD_OPTION ...]

Architectures:
  native     Current Mac architecture (default)
  arm64      Apple Silicon
  x86_64     Intel
  universal  Both arm64 and x86_64

Output (default):
  dist/Moonlight-macOS-ARCH.app

Options:
  --debug     Build Debug for the standard macOS destination in Xcode Derived Data
  --dmg       Also create dist/Moonlight-macOS-Enhanced-ARCH.dmg
EOF
}

requested_arch="native"
arch_option_set=0
debug_build=0
create_disk_image=0
xcodebuild_args=()
while (($# > 0)); do
  case "$1" in
    -a|--arch)
      if (($# < 2)); then
        echo "error: $1 requires an architecture" >&2
        usage >&2
        exit 2
      fi
      requested_arch="$2"
      arch_option_set=1
      shift 2
      ;;
    --dmg)
      create_disk_image=1
      shift
      ;;
    --debug)
      debug_build=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      xcodebuild_args+=("$@")
      break
      ;;
    *)
      xcodebuild_args+=("$1")
      shift
      ;;
  esac
done

if ((debug_build == 1 && create_disk_image == 1)); then
  echo "error: --debug cannot be combined with --dmg" >&2
  usage >&2
  exit 2
fi

if ((debug_build == 1 && arch_option_set == 1)); then
  echo "error: --debug cannot be combined with --arch" >&2
  usage >&2
  exit 2
fi

case "${requested_arch}" in
  native)
    build_arch="$(uname -m)"
    ;;
  arm64|x86_64)
    build_arch="${requested_arch}"
    ;;
  universal)
    build_arch="arm64 x86_64"
    ;;
  *)
    echo "error: unsupported architecture '${requested_arch}'" >&2
    usage >&2
    exit 2
    ;;
esac

case "${build_arch}" in
  arm64|x86_64|"arm64 x86_64") ;;
  *)
    echo "error: unsupported host architecture '${build_arch}'" >&2
    exit 2
    ;;
esac

if [[ "${requested_arch}" == native ]]; then
  output_variant="${build_arch}"
else
  output_variant="${requested_arch}"
fi

readonly APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/Moonlight.app"
readonly MAIN_BINARY="${APP_PATH}/Contents/MacOS/Moonlight"
readonly HELPER_BINARY="${APP_PATH}/Contents/Library/LaunchServices/std.skyhua.MoonlightMac.AwdlPrivilegedHelper"
readonly OUTPUT_APP_PATH="${OUTPUT_DIR}/Moonlight-macOS-${output_variant}.app"
readonly DMG_PATH="${OUTPUT_DIR}/Moonlight-macOS-Enhanced-${output_variant}.dmg"

mkdir -p "${OUTPUT_DIR}"

# The generated build number must be visible to xcodebuild, but it should not
# remain as a local source change after the release build finishes or fails.
version_config_backup="$(mktemp "${TMPDIR:-/tmp}/moonlight-version.XXXXXX")"
cp "${VERSION_CONFIG}" "${version_config_backup}"
restore_version_config() {
  cp "${version_config_backup}" "${VERSION_CONFIG}"
  rm -f "${version_config_backup}"
}
trap restore_version_config EXIT

# Generate the build number before xcodebuild reads Version.xcconfig. The scheme
# also runs this script as a pre-action for builds started directly from Xcode.
SRCROOT="${REPO_ROOT}" PROJECT_DIR="${REPO_ROOT}" \
  /bin/bash "${REPO_ROOT}/Limelight/build-number.sh"

echo "Building ${SCHEME}"
echo "$(<"${VERSION_CONFIG}")"
if ((debug_build == 1)); then
  echo "Configuration: Debug"
  echo "Destination: standard macOS destination and Xcode Derived Data"
else
  echo "Configuration: Release"
  echo "Architectures: ${build_arch}"
  echo "Output directory: ${OUTPUT_DIR}"
fi

if ((debug_build == 1)); then
  xcodebuild_command=(
    xcodebuild
    -project "${PROJECT}"
    -scheme "${SCHEME}"
    -configuration Debug
    -destination "platform=macOS"
    build
  )
else
  xcodebuild_command=(
    xcodebuild
    -project "${PROJECT}"
    -scheme "${SCHEME}"
    -configuration Release
    -destination "platform=macOS,arch=$( [[ "${requested_arch}" == universal ]] && echo "$(uname -m)" || echo "${build_arch}" )"
    -derivedDataPath "${DERIVED_DATA_PATH}"
    build
    ARCHS="${build_arch}"
    ONLY_ACTIVE_ARCH="$( [[ "${requested_arch}" == universal ]] && echo NO || echo YES )"
    CLANG_ENABLE_EXPLICIT_MODULES=NO
    "FRAMEWORK_SEARCH_PATHS=\$(inherited) ${OPENSSL_FRAMEWORK_DIR}"
  )
fi

code_signing_overridden=0
for ((i = 0; i < ${#xcodebuild_args[@]}; i++)); do
  case "${xcodebuild_args[$i]}" in
    CODE_SIGNING_ALLOWED=*|CODE_SIGNING_REQUIRED=*)
      code_signing_overridden=1
      break
      ;;
  esac
done

if ((code_signing_overridden == 0)); then
  signing_team_id="${SIGNING_TEAM_ID:-$(
    awk '/DEVELOPMENT_TEAM = / { gsub(/;/, "", $3); print $3; exit }' \
      "${PROJECT}/project.pbxproj"
  )}"
  signing_identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  if [[ -z "${signing_team_id}" || "${signing_identities}" != *"(${signing_team_id})"* ]]; then
    echo "Signing: disabled (no private key found for team ${signing_team_id:-unknown})"
    xcodebuild_command+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
  else
    echo "Signing: enabled for team ${signing_team_id}"
  fi
fi

if ((${#xcodebuild_args[@]} > 0)); then
  xcodebuild_command+=("${xcodebuild_args[@]}")
fi

"${xcodebuild_command[@]}"

if ((debug_build == 1)); then
  debug_build_settings_command=(
    xcodebuild
    -project "${PROJECT}"
    -scheme "${SCHEME}"
    -configuration Debug
    -destination "platform=macOS"
    -showBuildSettings
  )
  if ((${#xcodebuild_args[@]} > 0)); then
    debug_build_settings_command+=("${xcodebuild_args[@]}")
  fi
  debug_build_settings="$("${debug_build_settings_command[@]}")"
  debug_target_build_dir="$(awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { print $2; exit }' <<<"${debug_build_settings}")"
  debug_full_product_name="$(awk -F ' = ' '/^[[:space:]]*FULL_PRODUCT_NAME = / { print $2; exit }' <<<"${debug_build_settings}")"

  echo "Debug app created:"
  echo "  ${debug_target_build_dir}/${debug_full_product_name}"
  exit 0
fi

if [[ ! -x "${MAIN_BINARY}" ]]; then
  echo "error: expected app binary not found at ${MAIN_BINARY}" >&2
  exit 1
fi

if [[ ! -x "${HELPER_BINARY}" ]]; then
  echo "error: expected AWDL helper not found at ${HELPER_BINARY}" >&2
  exit 1
fi

main_archs="$(lipo -archs "${MAIN_BINARY}")"
helper_archs="$(lipo -archs "${HELPER_BINARY}")"
for expected_arch in ${build_arch}; do
  if [[ " ${main_archs} " != *" ${expected_arch} "* ]]; then
    echo "error: main binary is missing ${expected_arch} (found: ${main_archs})" >&2
    exit 1
  fi
  if [[ " ${helper_archs} " != *" ${expected_arch} "* ]]; then
    echo "error: AWDL helper is missing ${expected_arch} (found: ${helper_archs})" >&2
    exit 1
  fi
done

echo "Main binary architectures: ${main_archs}"
echo "AWDL helper architectures: ${helper_archs}"

rm -rf "${OUTPUT_APP_PATH}"
ditto "${APP_PATH}" "${OUTPUT_APP_PATH}"

if ((create_disk_image == 1)); then
  output_app_name="$(basename "${OUTPUT_APP_PATH}")"
  if command -v create-dmg >/dev/null 2>&1; then
    create-dmg \
      --overwrite \
      --volname "Moonlight macOS Enhanced (${output_variant})" \
      --volicon "${OUTPUT_APP_PATH}/Contents/Resources/AppIcon.icns" \
      --window-pos 200 120 \
      --window-size 600 400 \
      --icon-size 100 \
      --icon "${output_app_name}" 150 185 \
      --hide-extension "${output_app_name}" \
      --app-drop-link 450 185 \
      "${DMG_PATH}" \
      "${OUTPUT_APP_PATH}" || \
    hdiutil create -volname "Moonlight-${output_variant}" -srcfolder "${OUTPUT_APP_PATH}" -ov -format UDZO "${DMG_PATH}"
  else
    hdiutil create -volname "Moonlight-${output_variant}" -srcfolder "${OUTPUT_APP_PATH}" -ov -format UDZO "${DMG_PATH}"
  fi
fi

echo "Release app created:"
echo "  ${OUTPUT_APP_PATH}"
if ((create_disk_image == 1)); then
  echo "Disk image created:"
  echo "  ${DMG_PATH}"
fi
