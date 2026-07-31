#!/usr/bin/env bash
# Local dev helper: stage both frameworks into a scratch directory and run
# xcodegen + xcodebuild. Not the CI build path — that's driven by Gradle
# tasks in unity-plugin/build.gradle.kts (see Section F of the phase-2 plan).
#
# Prereqs: brew install xcodegen
# From the repo root:
#   ./gradlew :engagement-cloud-sdk:linkReleaseFrameworkMacosArm64 \
#             :unity-plugin:kotlin:linkReleaseFrameworkMacosArm64
#   unity-plugin/shim/build-local.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MAIN_FRAMEWORK="$REPO_ROOT/engagement-cloud-sdk/build/bin/macosArm64/releaseFramework/EngagementCloudSDK.framework"
UNITY_KOTLIN_FRAMEWORK="$REPO_ROOT/unity-plugin/kotlin/build/bin/macosArm64/releaseFramework/EngagementCloudSDKUnityKotlin.framework"

if [[ ! -d "$MAIN_FRAMEWORK" ]]; then
  echo "ERROR: main framework not built. Run:" >&2
  echo "  ./gradlew :engagement-cloud-sdk:linkReleaseFrameworkMacosArm64" >&2
  exit 1
fi
if [[ ! -d "$UNITY_KOTLIN_FRAMEWORK" ]]; then
  echo "ERROR: unity-kotlin framework not built. Run:" >&2
  echo "  ./gradlew :unity-plugin:kotlin:linkReleaseFrameworkMacosArm64" >&2
  exit 1
fi

# xcodegen resolves FRAMEWORK_SEARCH_PATHS at compile time. Stage a directory
# with symlinks to both frameworks so a single search path finds them both.
FRAMEWORKS_STAGE="$SCRIPT_DIR/.build/frameworks"
rm -rf "$FRAMEWORKS_STAGE"
mkdir -p "$FRAMEWORKS_STAGE"
ln -s "$MAIN_FRAMEWORK" "$FRAMEWORKS_STAGE/EngagementCloudSDK.framework"
ln -s "$UNITY_KOTLIN_FRAMEWORK" "$FRAMEWORKS_STAGE/EngagementCloudSDKUnityKotlin.framework"

pushd "$SCRIPT_DIR" > /dev/null

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: xcodegen not on PATH. Install with: brew install xcodegen" >&2
  exit 1
fi

echo "[shim] xcodegen generate"
xcodegen generate

WRAPPER_VERSION="${EC_WRAPPER_VERSION:-0.0.0-dev}"

echo "[shim] xcodebuild (wrapper version: $WRAPPER_VERSION)"
xcodebuild \
  -project EngagementCloudSDKUnity.xcodeproj \
  -scheme EngagementCloudSDKUnity \
  -configuration Release \
  -sdk macosx \
  -destination 'generic/platform=macOS' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  EC_FRAMEWORKS_DIR="$FRAMEWORKS_STAGE" \
  EC_WRAPPER_VERSION_STR="$WRAPPER_VERSION" \
  BUILD_DIR="$SCRIPT_DIR/.build/products" \
  build

BUNDLE_PATH="$SCRIPT_DIR/.build/products/Release/EngagementCloudSDKUnity.bundle"
if [[ ! -d "$BUNDLE_PATH" ]]; then
  echo "ERROR: build succeeded but bundle not found at $BUNDLE_PATH" >&2
  exit 1
fi

echo "[shim] built: $BUNDLE_PATH"
echo "[shim] linked-against frameworks:"
otool -L "$BUNDLE_PATH/Contents/MacOS/EngagementCloudSDKUnity" 2>/dev/null | tail -n +2 | head -6

popd > /dev/null
