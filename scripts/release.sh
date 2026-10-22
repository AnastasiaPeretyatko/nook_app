#!/usr/bin/env bash
# Builds the release APK and publishes it as a GitHub Release together with the
# version.json the app checks at launch.
#
#   scripts/release.sh "What's new"
#   DRY_RUN=1 scripts/release.sh "text"   # build + version.json, publish nothing
#
# The version comes from pubspec.yaml (`version: 1.0.4+5` → name 1.0.4, code 5).
# Nothing is published unless every step before it succeeded (set -e).
set -euo pipefail
cd "$(dirname "$0")/.."

CHANGELOG="${1:-}"
[ -n "$CHANGELOG" ] || { echo "usage: scripts/release.sh \"changelog\"" >&2; exit 1; }
DRY_RUN="${DRY_RUN:-}"

# Same constant the app uses, so the repo is written down once.
REPO=$(sed -n "s/^const updateRepo = '\(.*\)';/\1/p" lib/update/app_update.dart)
[ -n "$REPO" ] || { echo "updateRepo not found in lib/update/app_update.dart" >&2; exit 1; }

VERSION=$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | tr -d '[:space:]')
NAME=${VERSION%+*}
CODE=${VERSION#*+}
[[ "$NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$CODE" =~ ^[0-9]+$ ]] \
  || { echo "pubspec version must look like 1.0.4+5, got '$VERSION'" >&2; exit 1; }

if [ -z "$DRY_RUN" ]; then
  # An update only installs over an app signed with the same key, so a release
  # signed with the debug key would strand everyone who installs it.
  [ -f android/key.properties ] || [ -n "${ALLOW_DEBUG_KEY:-}" ] \
    || { echo "android/key.properties is missing: the APK would get the debug key" >&2; exit 1; }
  [ "$REPO" != "OWNER/REPO" ] || { echo "set updateRepo in lib/update/app_update.dart first" >&2; exit 1; }
  gh auth status >/dev/null || { echo "run: gh auth login" >&2; exit 1; }
  if gh release view "v$NAME" --repo "$REPO" >/dev/null 2>&1; then
    echo "release v$NAME already exists — raise the version in pubspec.yaml" >&2
    exit 1
  fi
fi

flutter build apk --release

APK=build/app/outputs/flutter-apk/app-release.apk
[ -f "$APK" ] || { echo "$APK was not produced" >&2; exit 1; }

OUT=build/release
mkdir -p "$OUT"
SHA=$(sha256sum "$APK" | cut -d' ' -f1)
python3 - "$CODE" "$NAME" "https://github.com/$REPO/releases/download/v$NAME/app-release.apk" \
  "$CHANGELOG" "$SHA" > "$OUT/version.json" <<'PY'
import json, sys
code, name, url, changelog, sha = sys.argv[1:]
print(json.dumps({"versionCode": int(code), "versionName": name, "url": url,
                  "changelog": changelog, "sha256": sha}, ensure_ascii=False, indent=2))
PY
cat "$OUT/version.json"

if [ -n "$DRY_RUN" ]; then
  echo "DRY_RUN: not publishing v$NAME"
  exit 0
fi

gh release create "v$NAME" "$APK" "$OUT/version.json" \
  --repo "$REPO" --title "v$NAME" --notes "$CHANGELOG"
echo "Published: https://github.com/$REPO/releases/tag/v$NAME"
