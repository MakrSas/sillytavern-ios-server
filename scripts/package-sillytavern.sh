#!/usr/bin/env bash
set -euo pipefail

# CI-only packager. It never runs shell scripts from the downloaded application.
# npm lifecycle scripts are disabled deliberately.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
requested_tag="${1:-latest}"
destination="${2:-${repo_root}/Build/SillyTavernPayload}"
compatibility_patch="${repo_root}/patches/sillytavern-1.18.0-ios-jitless.patch"
frontend_compiler="${repo_root}/scripts/compile-sillytavern-frontend.mjs"
readonly SILLYTAVERN_TAG="1.18.0"
readonly SILLYTAVERN_COMMIT="51ad27fb86d39a3daca3adaa970375c9670c12df"
readonly SILLYTAVERN_ARCHIVE_SHA256="8c479d5980ac69830e47ab643fef21308db5d9ac0cf15d51a0f35a95d2fc62a2"
scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

if [[ "${requested_tag}" == "latest" ]]; then
  requested_tag="$(
    curl --fail --silent --show-error \
      -H "Accept: application/vnd.github+json" \
      -H "User-Agent: SillyTavernServer-iOS-packager" \
      "https://api.github.com/repos/SillyTavern/SillyTavern/releases/latest" |
      python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])'
  )"
fi

if [[ ! "${requested_tag}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Unexpected SillyTavern tag: ${requested_tag}" >&2
  exit 1
fi
if [[ "${requested_tag}" != "${SILLYTAVERN_TAG}" ]]; then
  echo "This compatibility patch is pinned to ${SILLYTAVERN_TAG}, not ${requested_tag}." >&2
  exit 1
fi

archive="${scratch}/sillytavern.tar.gz"
source_url="https://codeload.github.com/SillyTavern/SillyTavern/tar.gz/${SILLYTAVERN_COMMIT}"
curl --fail --location --retry 3 --output "${archive}" "${source_url}"
printf '%s  %s\n' "${SILLYTAVERN_ARCHIVE_SHA256}" "${archive}" | shasum -a 256 --check
tar -xzf "${archive}" -C "${scratch}"

source_directory="${scratch}/SillyTavern-${SILLYTAVERN_COMMIT}"
test -f "${source_directory}/package.json"
test -f "${source_directory}/package-lock.json"
test -f "${source_directory}/server.js"
test -f "${compatibility_patch}"
test -f "${frontend_compiler}"

(
  cd "${source_directory}"
  git apply --no-index --recount --check "${compatibility_patch}"
  git apply --no-index --recount "${compatibility_patch}"
)

node_engine="$(
  python3 - "${source_directory}/package.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle).get("engines", {}).get("node", ""))
PY
)"
if [[ "${node_engine}" != *">= 20"* && "${node_engine}" != *">=20"* ]]; then
  echo "Unexpected Node.js requirement: ${node_engine}" >&2
  exit 1
fi

(
  cd "${source_directory}"
  npm ci --omit=dev --ignore-scripts --no-audit --no-fund
)

test -d "${source_directory}/node_modules/@jimp/js-jpeg"
test -d "${source_directory}/node_modules/@jimp/js-png"
test -f "${source_directory}/node_modules/node-fetch/src/index.js"
node "${frontend_compiler}" "${source_directory}"
test "$(wc -c < "${source_directory}/dist/_webpack/ios-precompiled/output/lib.js")" -gt 100000

python3 - "${source_directory}" "${requested_tag}" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
capabilities = {
    "sillyTavernVersion": sys.argv[2],
    "webAssembly": False,
    "fetchImplementation": "node-fetch",
    "tokenizer": "portable-byte-estimate",
    "imageFormats": ["png", "jpeg", "bmp", "gif", "tiff"],
    "unavailableImageFormats": ["webp", "avif"],
    "frontend": "precompiled-by-ci",
}
(root / "ios-runtime-capabilities.json").write_text(
    json.dumps(capabilities, ensure_ascii=False, indent=2),
    encoding="utf-8",
)
PY

if [[ -e "${destination}" ]]; then
  echo "Refusing to overwrite existing payload: ${destination}" >&2
  exit 1
fi
mkdir -p "$(dirname "${destination}")"
mv "${source_directory}" "${destination}"

python3 - \
  "${destination}" \
  "${requested_tag}" \
  "${SILLYTAVERN_COMMIT}" \
  "${SILLYTAVERN_ARCHIVE_SHA256}" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
entries = {}
for path in sorted(p for p in root.rglob("*") if p.is_file()):
    entries[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()

manifest = {
    "source": "https://github.com/SillyTavern/SillyTavern",
    "tag": sys.argv[2],
    "commit": sys.argv[3],
    "source_archive_sha256": sys.argv[4],
    "node_modules_lifecycle_scripts": "disabled",
    "files": entries,
}
(root / "ios-package-manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2),
    encoding="utf-8",
)
PY

echo "Prepared ${destination} from official tag ${requested_tag}."
