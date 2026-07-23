#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime="${repo_root}/Vendor/NodeMobile.xcframework"
build_root="${repo_root}/Build"
product="${build_root}/DerivedData/Build/Products/Release-iphoneos/SillyTavernServer.app"
output="${build_root}/SillyTavernServer-unsigned.ipa"
app_binary="${product}/SillyTavernServer"
embedded_framework="${product}/Frameworks/NodeMobile.framework/NodeMobile"
linked_libraries="${build_root}/linked-libraries.txt"
ipa_contents="${build_root}/ipa-contents.txt"

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
test -f "${app_binary}"
test -f "${embedded_framework}" || {
  echo "NodeMobile.framework is not embedded in the app bundle." >&2
  exit 1
}

xcrun otool -L "${app_binary}" | tee "${linked_libraries}"
grep -Fq "@rpath/NodeMobile.framework/NodeMobile" "${linked_libraries}" || {
  echo "The app executable is not linked to NodeMobile.framework." >&2
  exit 1
}

framework_size="$(stat -f '%z' "${embedded_framework}")"
if [[ "${framework_size}" -lt 10000000 ]]; then
  echo "Embedded NodeMobile binary is unexpectedly small: ${framework_size} bytes." >&2
  exit 1
fi
echo "Embedded NodeMobile binary: ${framework_size} bytes."

payload_root="$(mktemp -d)"
trap 'rm -rf "${payload_root}"' EXIT
mkdir -p "${payload_root}/Payload"
cp -R "${product}" "${payload_root}/Payload/"

(
  cd "${payload_root}"
  /usr/bin/zip -qry "${output}" Payload
)

unzip -l "${output}" | tee "${ipa_contents}"
grep -Fq "Payload/SillyTavernServer.app/Frameworks/NodeMobile.framework/NodeMobile" "${ipa_contents}" || {
  echo "Packaged IPA lost NodeMobile.framework." >&2
  exit 1
}

echo "Created unsigned IPA: ${output}"
