#!/usr/bin/env bash
set -euo pipefail

readonly NODE_MOBILE_REPOSITORY="https://github.com/nodejs-mobile/nodejs-mobile.git"
# Head of the public Node 22.9.0 port branch. It is intentionally pinned:
# moving the ref would execute unreviewed build changes in CI.
readonly NODE_MOBILE_COMMIT="106c51f95d55d1010de56a2ffd09bfb4ba819a47"
readonly APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly NODE_MOBILE_PATCH="${APP_ROOT}/patches/node22-ios-host-tools.patch"
readonly NODE_MOBILE_FRAMEWORK_PATCH="${APP_ROOT}/patches/node22-ios-framework-libraries.patch"

target="${1:-}"
case "${target}" in
  arm64|arm64-simulator) ;;
  *)
    echo "Usage: $0 arm64|arm64-simulator" >&2
    exit 64
    ;;
esac

scratch_root="${RUNNER_TEMP:-}"
if [[ -z "${scratch_root}" ]]; then
  scratch_root="$(mktemp -d)"
fi
scratch_root="$(cd "${scratch_root}" && pwd -P)"
source_root="${scratch_root}/nodejs-mobile-${target}"

if [[ -e "${source_root}" ]]; then
  echo "Refusing to reuse existing source directory: ${source_root}" >&2
  exit 1
fi

cleanup_source() {
  if [[ ! -e "${source_root}" ]]; then
    return
  fi

  case "${source_root}" in
    "${scratch_root%/}"/nodejs-mobile-arm64|\
    "${scratch_root%/}"/nodejs-mobile-arm64-simulator)
      rm -rf -- "${source_root}"
      ;;
    *)
      echo "Refusing to clean unexpected source directory: ${source_root}" >&2
      ;;
  esac
}
trap cleanup_source EXIT

mkdir -p "${source_root}"
git -C "${source_root}" init
git -C "${source_root}" remote add origin "${NODE_MOBILE_REPOSITORY}"
git -C "${source_root}" fetch --depth=1 origin "${NODE_MOBILE_COMMIT}"
git -C "${source_root}" checkout --detach FETCH_HEAD

actual_commit="$(git -C "${source_root}" rev-parse HEAD)"
if [[ "${actual_commit}" != "${NODE_MOBILE_COMMIT}" ]]; then
  echo "Unexpected source commit: ${actual_commit}" >&2
  exit 1
fi

git -C "${source_root}" apply --check "${NODE_MOBILE_PATCH}"
git -C "${source_root}" apply "${NODE_MOBILE_PATCH}"
git -C "${source_root}" apply --check "${NODE_MOBILE_FRAMEWORK_PATCH}"
git -C "${source_root}" apply "${NODE_MOBILE_FRAMEWORK_PATCH}"
git -C "${source_root}" diff --check

python3 -m venv "${source_root}/.venv"
source "${source_root}/.venv/bin/activate"
python -m pip install --disable-pip-version-check --no-input "setuptools==80.9.0"

(
  cd "${source_root}"
  ./tools/ios_framework_prepare.sh "${target}"
)

framework_root="${source_root}/out_ios_${target}"
framework="$(
  find "${framework_root}" \
    -type d \
    -path '*/Release-*/NodeMobile.framework' \
    -print \
    -quit
)"
if [[ -z "${framework}" || ! -f "${framework}/NodeMobile" ]]; then
  echo "NodeMobile.framework was not produced for ${target}." >&2
  find "${framework_root}" -type d -name NodeMobile.framework -print >&2
  exit 1
fi

output_root="${scratch_root}/node22-${target}"
mkdir -p "${output_root}"
cp -R "${framework}" "${output_root}/"
printf '%s\n' "${NODE_MOBILE_COMMIT}" > "${output_root}/SOURCE_COMMIT"
echo "Built ${output_root}/NodeMobile.framework"
