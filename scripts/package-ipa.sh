#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime="${repo_root}/Vendor/NodeMobile.xcframework"
build_root="${repo_root}/Build"
product="${build_root}/DerivedData/Build/Products/Release-iphoneos/SillyTavernServer.app"
output="${build_root}/SillyTavernServer-unsigned.ipa"

test -f "${runtime}/Info.plist" || {
  echo "Missing ${runtime}. Prepare the runtime first." >&2
  exit 1
}

mkdir -p "${build_root}"

xcodebuild \
  -project "${repo_root}/SillyTavernServer.xcodeproj" \
  -scheme SillyTavernServer \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "${build_root}/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  clean build

test -d "${product}"

payload_root="$(mktemp -d)"
trap 'rm -rf "${payload_root}"' EXIT
mkdir -p "${payload_root}/Payload"
cp -R "${product}" "${payload_root}/Payload/"

(
  cd "${payload_root}"
  /usr/bin/zip -qry "${output}" Payload
)

echo "Created unsigned IPA: ${output}"
