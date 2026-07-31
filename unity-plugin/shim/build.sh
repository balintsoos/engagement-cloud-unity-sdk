#!/usr/bin/env bash
# Build EngagementCloudSDKUnity.bundle (Mach-O loadable bundle) linked against Phase-1's
# EngagementCloudSDK.framework.
#
# The bundle is a plain Mach-O with `-bundle` linkage — Unity's macOS Player loads it via
# `dlopen` when a `[DllImport("EngagementCloudSDKUnity")]` fires. The trailing `.bundle`
# extension is Unity's plugin convention; we produce a proper `.bundle` **directory** with an
# Info.plist so Unity's plugin importer classifies it correctly.
#
# Prerequisites:
#   ./gradlew :engagement-cloud-sdk:linkDebugFrameworkMacosArm64
#
# Output:
#   unity-plugin/shim/build/EngagementCloudSDKUnity.bundle/
#     Contents/
#       Info.plist
#       MacOS/EngagementCloudSDKUnity
#
# The framework it links against is copied next to the bundle for local runs, and copied a
# second time into unity-plugin/com.sap.ec.unity/Plugins/macOS/ so an in-project import picks
# it up automatically.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

FRAMEWORK_DIR_DEBUG="$REPO_ROOT/engagement-cloud-sdk/build/bin/macosArm64/debugFramework"
FRAMEWORK_DIR_RELEASE="$REPO_ROOT/engagement-cloud-sdk/build/bin/macosArm64/releaseFramework"
if   [[ -d "$FRAMEWORK_DIR_RELEASE/EngagementCloudSDK.framework" ]]; then FRAMEWORK_DIR="$FRAMEWORK_DIR_RELEASE";
elif [[ -d "$FRAMEWORK_DIR_DEBUG/EngagementCloudSDK.framework"   ]]; then FRAMEWORK_DIR="$FRAMEWORK_DIR_DEBUG";
else
    echo "error: EngagementCloudSDK.framework not found" >&2
    echo "  build it first with: ./gradlew :engagement-cloud-sdk:linkDebugFrameworkMacosArm64" >&2
    exit 1
fi

BUILD_DIR="$HERE/build"
BUNDLE="$BUILD_DIR/EngagementCloudSDKUnity.bundle"
CONTENTS="$BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
BIN="$MACOS_DIR/EngagementCloudSDKUnity"

rm -rf "$BUNDLE"
mkdir -p "$MACOS_DIR" "$CONTENTS/Frameworks"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>       <string>com.sap.ec.unity.shim</string>
    <key>CFBundleName</key>             <string>EngagementCloudSDKUnity</string>
    <key>CFBundleExecutable</key>       <string>EngagementCloudSDKUnity</string>
    <key>CFBundlePackageType</key>      <string>BNDL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0-poc</string>
    <key>CFBundleVersion</key>          <string>1</string>
    <key>LSMinimumSystemVersion</key>   <string>13.0</string>
</dict>
</plist>
PLIST

echo "Framework: $FRAMEWORK_DIR"
echo "Compiling shim → $BIN"

# We compile with:
#   -bundle                 : produce a Mach-O bundle (dlopen'able, not a dylib)
#   -F <dir>                : framework search path (host-side, at build time)
#   -framework EngagementCloudSDK : link against the Kotlin/Native framework
#   -rpath @loader_path/../Frameworks : first place Unity looks for the framework at runtime
#   -rpath @loader_path             : fallback when Unity places both peers in Plugins/macOS
#   -fmodules -fcxx-modules        : enables `#import <Foundation/Foundation.h>` clean parse
#   -std=gnu++17                    : Obj-C++ requires C++11+; gnu17 matches modern Unity toolchain
#   -fobjc-arc                      : ARC lifetimes for the Obj-C blocks (blocks are the callback shape)
#   -O2                             : release-grade optimisation; strip is done post-link below
#   -mmacosx-version-min=13.0       : matches Info.plist LSMinimumSystemVersion
#
# `@loader_path/../Frameworks` covers the layout Unity produces in a built .app:
#   <App>.app/Contents/PlugIns/EngagementCloudSDKUnity.bundle/
#   <App>.app/Contents/Frameworks/EngagementCloudSDK.framework/
# and `@loader_path` covers the dev layout where both peers sit in Plugins/macOS/ side-by-side.
xcrun clang++ \
    -bundle \
    -arch arm64 \
    -target arm64-apple-macos13 \
    -mmacosx-version-min=13.0 \
    -fobjc-arc \
    -fmodules \
    -fcxx-modules \
    -std=gnu++17 \
    -O2 \
    -Wall -Wextra -Wno-unused-parameter -Wno-nullability-completeness \
    -F "$FRAMEWORK_DIR" \
    -framework Foundation \
    -framework AppKit \
    -framework EngagementCloudSDK \
    -Xlinker -install_name -Xlinker "@rpath/EngagementCloudSDKUnity.bundle/Contents/MacOS/EngagementCloudSDKUnity" \
    -Xlinker -rpath -Xlinker "@loader_path/../Frameworks" \
    -Xlinker -rpath -Xlinker "@loader_path" \
    -Xlinker -rpath -Xlinker "@loader_path/../../.." \
    -o "$BIN" \
    "$HERE/src/EngagementCloudSDKUnity.mm"

# Stage the framework alongside the bundle for local runs (from build/), and inside the UPM
# package's Plugins/macOS for in-Editor use.
cp -R "$FRAMEWORK_DIR/EngagementCloudSDK.framework" "$BUILD_DIR/"

PLUGINS_MACOS="$REPO_ROOT/unity-plugin/com.sap.ec.unity/Plugins/macOS"
mkdir -p "$PLUGINS_MACOS"
rm -rf "$PLUGINS_MACOS/EngagementCloudSDKUnity.bundle" "$PLUGINS_MACOS/EngagementCloudSDK.framework"
cp -R "$BUNDLE"                                       "$PLUGINS_MACOS/"
cp -R "$FRAMEWORK_DIR/EngagementCloudSDK.framework"   "$PLUGINS_MACOS/"

# Ad-hoc sign so Gatekeeper doesn't block dlopen on local runs. Unity re-signs on Player build.
codesign --force --sign - "$BIN"                                                     >/dev/null 2>&1 || true
codesign --force --sign - "$PLUGINS_MACOS/EngagementCloudSDKUnity.bundle"            >/dev/null 2>&1 || true
codesign --force --sign - "$PLUGINS_MACOS/EngagementCloudSDK.framework"              >/dev/null 2>&1 || true

echo ""
echo "built: $BUNDLE"
echo "staged into: $PLUGINS_MACOS/"
echo ""
echo "verify:"
echo "  lipo -info    $BIN"
echo "  otool -L      $BIN"
echo "  nm -gU        $BIN | grep '^_ec_'"
