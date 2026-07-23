#!/usr/bin/env bash
set -euo pipefail

# CI-only packager. It never runs shell scripts from the downloaded application.
# npm lifecycle scripts are disabled deliberately.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
requested_tag="${1:-latest}"
destination="${2:-${repo_root}/Build/SillyTavernPayload}"
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

archive="${scratch}/sillytavern.tar.gz"
source_url="https://github.com/SillyTavern/SillyTavern/archive/refs/tags/${requested_tag}.tar.gz"
curl --fail --location --retry 3 --output "${archive}" "${source_url}"
tar -xzf "${archive}" -C "${scratch}"

source_directory="${scratch}/SillyTavern-${requested_tag}"
test -f "${source_directory}/package.json"
test -f "${source_directory}/package-lock.json"
test -f "${source_directory}/server.js"

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

if [[ -e "${destination}" ]]; then
  echo "Refusing to overwrite existing payload: ${destination}" >&2
  exit 1
fi
mkdir -p "$(dirname "${destination}")"
mv "${source_directory}" "${destination}"

python3 - "${destination}" "${requested_tag}" <<'PY'
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
    "node_modules_lifecycle_scripts": "disabled",
    "files": entries,
}
(root / "ios-package-manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2),
    encoding="utf-8",
)
PY

echo "Prepared ${destination} from official tag ${requested_tag}."
