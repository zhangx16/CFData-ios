#!/usr/bin/env bash
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$TASK_ROOT"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "iOS builds require macOS and Xcode. Run the Build unsigned iOS IPA workflow."
  exit 1
fi
command -v go >/dev/null
command -v xcodegen >/dev/null
command -v gomobile >/dev/null
xcodebuild -version
python3 ios/scripts/prepare_core.py

MOBILE_VERSION=v0.0.0-20261011034528-197770444867
IOS_APP_VERSION="${IOS_APP_VERSION:-1.1.0}"
(
  cd build/mobile
  go mod tidy
  go get "golang.org/x/mobile/cmd/gobind@${MOBILE_VERSION}"
  go test -race ./internal/core
  gomobile bind -target=ios/arm64 -iosversion=16.0 \
    -ldflags "-s -w -X cfdataios/internal/core.appVersion=$IOS_APP_VERSION" \
    -o "$TASK_ROOT/build/CFDataMobile.xcframework" ./mobile
)

ICON_DIR="$TASK_ROOT/ios/Assets/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICON_DIR"
# JPEG round-trip removes alpha; reuse the project's existing icon.
sips -s format jpeg combined_refactor/favicon.png --out build/icon.jpg >/dev/null
sips -s format png -z 1024 1024 build/icon.jpg --out "$ICON_DIR/AppIcon.png" >/dev/null
python3 - "$ICON_DIR" <<'PY'
import json
import pathlib
import sys
p = pathlib.Path(sys.argv[1])
(p / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}))
PY

xcodegen generate --spec ios/project.yml
xcodebuild -project ios/CFData.xcodeproj -scheme CFData \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  MARKETING_VERSION="$IOS_APP_VERSION" \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" build

APP_PATH="$TASK_ROOT/build/DerivedData/Build/Products/Release-iphoneos/CFData.app"
test -f "$APP_PATH/CFData"
lipo -info "$APP_PATH/CFData"
python3 ios/scripts/package_ipa.py "$APP_PATH" "$TASK_ROOT/release_assets/CFData-ios-unsigned.ipa"
(
  cd release_assets
  shasum -a 256 CFData-ios-unsigned.ipa > CFData-ios-unsigned.ipa.sha256
)
echo "Built release_assets/CFData-ios-unsigned.ipa; sign before installing on an iPhone."
