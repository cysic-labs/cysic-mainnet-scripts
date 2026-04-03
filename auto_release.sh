#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
RELEASE_NOTES_FILE="${2:-}"
REPO="cysic-labs/cysic-mainnet-scripts"

if [[ -z "$VERSION" ]]; then
  echo "Usage: make auto-release VERSION=vX.Y.Z [RELEASE_NOTES_FILE=/abs/path/notes.md]"
  exit 1
fi

echo "============== begin auto release ${VERSION} =============="

make release

git add -A
if ! git diff --cached --quiet; then
  git commit -m "release ${VERSION}"
else
  echo "No new changes to commit; using current HEAD"
fi

head_commit="$(git rev-parse HEAD)"
local_tag_commit="$(git rev-list -n 1 "${VERSION}" 2>/dev/null || true)"
if [[ -z "$local_tag_commit" ]]; then
  git tag -a "${VERSION}" -m "${VERSION}"
elif [[ "$local_tag_commit" != "$head_commit" ]]; then
  echo "Local tag ${VERSION} already exists on a different commit"
  exit 1
else
  echo "Local tag ${VERSION} already points at HEAD"
fi

branch="$(git branch --show-current)"
git push origin "$branch"

remote_tag_commit="$(git ls-remote --tags origin "refs/tags/${VERSION}" | awk '{print $1}')"
local_tag_commit="$(git rev-list -n 1 "${VERSION}")"
if [[ -n "$remote_tag_commit" && "$remote_tag_commit" != "$local_tag_commit" ]]; then
  echo "Remote tag ${VERSION} already exists on a different commit"
  exit 1
fi
if [[ -z "$remote_tag_commit" ]]; then
  git push origin "${VERSION}"
else
  echo "Remote tag ${VERSION} already present"
fi

notes_file="/tmp/cysic-release-notes-${VERSION}.md"
if [[ -n "$RELEASE_NOTES_FILE" ]]; then
  cat "$RELEASE_NOTES_FILE" > "$notes_file"
else
  {
    echo "## What's Changed"
    echo
    echo "- Release ${VERSION} from commit $(git rev-parse --short HEAD) ($(git log -1 --pretty=%s))."
    while IFS= read -r file; do
      [[ -n "$file" ]] && echo "- Updated \`$file\`."
    done < <(git diff-tree --no-commit-id --name-only -r HEAD)
  } > "$notes_file"
fi

{
  echo
  echo "## SHA256 Checksums"
  echo
  tail -n +2 sha256sum.txt
} >> "$notes_file"

cred="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill)"
user="$(printf '%s\n' "$cred" | sed -n 's/^username=//p' | head -n1)"
pass="$(printf '%s\n' "$cred" | sed -n 's/^password=//p' | head -n1)"
if [[ -z "$user" || -z "$pass" ]]; then
  echo "Missing GitHub credentials from git credential helper"
  exit 1
fi
auth="$(printf '%s:%s' "$user" "$pass" | base64 | tr -d '\n')"

release_json="/tmp/cysic-release-${VERSION}.json"
release_code="$(curl -sS -o "$release_json" -w '%{http_code}' \
  -H "Authorization: Basic ${auth}" \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  "https://api.github.com/repos/${REPO}/releases/tags/${VERSION}")"

python3 - "$notes_file" "$VERSION" > /tmp/cysic-release-payload.json <<'PY'
import json
import sys
from pathlib import Path

notes_path = Path(sys.argv[1])
version = sys.argv[2]
body = notes_path.read_text()
print(json.dumps({
    "tag_name": version,
    "target_commitish": "main",
    "name": version,
    "body": body,
    "draft": False,
    "prerelease": False,
    "make_latest": "true",
}))
PY

if [[ "$release_code" == "200" ]]; then
  release_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$release_json")"
  curl -sSfL \
    -X PATCH \
    -H "Authorization: Basic ${auth}" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -d @/tmp/cysic-release-payload.json \
    "https://api.github.com/repos/${REPO}/releases/${release_id}" \
    > /tmp/cysic-release-update.json
  python3 - <<'PY' | while IFS=$'\t' read -r asset_id asset_name; do
import json
release = json.load(open("/tmp/cysic-release-update.json"))
for asset in release.get("assets", []):
    print(f"{asset['id']}\t{asset['name']}")
PY
    curl -sSfL \
      -X DELETE \
      -H "Authorization: Basic ${auth}" \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      "https://api.github.com/repos/${REPO}/releases/assets/${asset_id}" \
      > /dev/null
  done
  upload_url="$(python3 -c 'import json; print(json.load(open("/tmp/cysic-release-update.json"))["upload_url"].split("{")[0])')"
elif [[ "$release_code" == "404" ]]; then
  curl -sSfL \
    -X POST \
    -H "Authorization: Basic ${auth}" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -d @/tmp/cysic-release-payload.json \
    "https://api.github.com/repos/${REPO}/releases" \
    > "$release_json"
  upload_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["upload_url"].split("{")[0])' "$release_json")"
else
  echo "Unexpected GitHub release lookup status: ${release_code}"
  exit 1
fi

upload_asset() {
  local file="$1"
  local name
  local response_file
  local http_code

  name="$(basename "$file")"
  response_file="/tmp/cysic-upload-${name}.json"

  echo "Uploading asset: ${name}"
  http_code="$(curl --progress-bar --retry 3 --retry-delay 2 \
    --connect-timeout 30 --max-time 3600 \
    -sS -o "$response_file" -w '%{http_code}' \
    -X POST \
    -H "Authorization: Basic ${auth}" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -H 'Content-Type: application/octet-stream' \
    --data-binary @"$file" \
    "${upload_url}?name=${name}")"

  case "$http_code" in
    201)
      echo "Uploaded asset: ${name}"
      ;;
    422)
      echo "Asset already exists on release: ${name}"
      ;;
    *)
      echo "Failed to upload asset ${name}, HTTP ${http_code}"
      cat "$response_file"
      exit 1
      ;;
  esac
}

for file in github_release/*; do
  upload_asset "$file"
done

local_count="$(ls -1 github_release | wc -l | tr -d ' ')"
remote_count="$(curl -sSfL \
  -H "Authorization: Basic ${auth}" \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  "https://api.github.com/repos/${REPO}/releases/tags/${VERSION}" \
  | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("assets", [])))')"
latest_tag="$(curl -sSfL \
  -H "Authorization: Basic ${auth}" \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  "https://api.github.com/repos/${REPO}/releases/latest" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tag_name", ""))')"

if [[ "$local_count" != "$remote_count" ]]; then
  echo "Release asset count mismatch: local=${local_count} remote=${remote_count}"
  exit 1
fi

if [[ "$latest_tag" != "$VERSION" ]]; then
  echo "Latest release mismatch: expected ${VERSION}, got ${latest_tag}"
  exit 1
fi

echo "============== auto release ${VERSION} complete =============="
