#!/usr/bin/env bash
# Build the minimal macOS sample against the just-built EngagementCloudSDK.framework.
#
# Assumes the framework has been built already:
#   ./gradlew :engagement-cloud-sdk:linkDebugFrameworkMacosArm64
#
# Produces macosApp/build/MacosApp.app. Run it with:
#   open macosApp/build/MacosApp.app
# or from Terminal (to see NSLog output on stderr):
#   macosApp/build/MacosApp.app/Contents/MacOS/MacosApp
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
FRAMEWORK_DIR="${FRAMEWORK_DIR:-$REPO_ROOT/engagement-cloud-sdk/build/bin/macosArm64/debugFramework}"
FRAMEWORK="$FRAMEWORK_DIR/EngagementCloudSDK.framework"

if [[ ! -d "$FRAMEWORK" ]]; then
  echo "error: framework not found at $FRAMEWORK" >&2
  echo "hint:  build it first with:" >&2
  echo "         ./gradlew :engagement-cloud-sdk:linkDebugFrameworkMacosArm64" >&2
  exit 1
fi

APP_BUNDLE="$HERE/build/MacosApp.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
FRAMEWORKS_DIR="$CONTENTS/Frameworks"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR"

cp "$HERE/Info.plist" "$CONTENTS/Info.plist"

# Copy (not symlink) so the .app is self-contained and can be moved.
cp -R "$FRAMEWORK" "$FRAMEWORKS_DIR/"

# Compile with @rpath/Frameworks so the loader finds the framework next to the exe.
xcrun swiftc \
  -target arm64-apple-macos13 \
  -parse-as-library \
  -F "$FRAMEWORK_DIR" \
  -framework EngagementCloudSDK \
  -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
  -o "$MACOS_DIR/MacosApp" \
  "$HERE/Sources/main.swift"

# Optional: codesign ad-hoc so Gatekeeper doesn't kill the run.
codesign --force --sign - --deep "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "built: $APP_BUNDLE"
