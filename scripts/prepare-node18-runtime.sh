#!/usr/bin/env bash
set -euo pipefail

readonly VERSION="18.20.4"
readonly SHA256="8c5ca3a0d1e38de7f182a5642593e82593b820efd375a14b3ecafc4bcfee620e"
readonly URL="https://github.com/nodejs-mobile/nodejs-mobile/releases/download/v${VERSION}/nodejs-mobile-v${VERSION}-ios.zip"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${repo_root}/Vendor/NodeMobile.xcframework"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "${temporary_directory}"' EXIT

archive="${temporary_directory}/node-mobile.zip"
curl --fail --location --retry 3 --output "${archive}" "${URL}"

actual_sha="$(shasum -a 256 "${archive}" | awk '{print $1}')"
if [[ "${actual_sha}" != "${SHA256}" ]]; then
  echo "SHA-256 mismatch for ${URL}" >&2
  echo "expected: ${SHA256}" >&2
  echo "actual:   ${actual_sha}" >&2
  exit 1
fi

unzip -q "${archive}" -d "${temporary_directory}/unpacked"
test -f "${temporary_directory}/unpacked/NodeMobile.xcframework/Info.plist"

if [[ -e "${destination}" ]]; then
  echo "Refusing to overwrite existing runtime: ${destination}" >&2
  exit 1
fi

mv "${temporary_directory}/unpacked/NodeMobile.xcframework" "${destination}"
echo "Prepared ${destination} (NodeMobile ${VERSION})."
