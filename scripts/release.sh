#!/bin/bash
set -euo pipefail

# Generic Tiny* app release script
# Builds, signs, notarizes, and publishes to GitHub Releases.
#
# Usage:
#   ./scripts/release.sh v1.0.0                  # build + notarize + GitHub release
#   ./scripts/release.sh v1.0.0 --skip-notarize  # build + GitHub release (no notarization)
#
# Prerequisites:
#   - Xcode command line tools
#   - gh CLI (brew install gh), authenticated
#   - For notarization: Developer ID Application cert + keychain profile:
#       xcrun notarytool store-credentials "notarize" \
#         --apple-id "mz@centaur-labs.io" --team-id "992N457T8D" --password "APP_SPECIFIC_PW"

VERSION="${1:?Usage: release.sh <version-tag> [--skip-notarize]}"
SKIP_NOTARIZE=false
[[ "${2:-}" == "--skip-notarize" ]] && SKIP_NOTARIZE=true

# Auto-detect app name from .xcodeproj
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODEPROJ=$(ls -d "$PROJECT_DIR"/*.xcodeproj 2>/dev/null | head -1)
if [[ -z "$XCODEPROJ" ]]; then
    echo "ERROR: No .xcodeproj found in $PROJECT_DIR"
    exit 1
fi
APP_NAME=$(basename "$XCODEPROJ" .xcodeproj)

# Strip leading 'v' for the marketing version (v1.1.0 → 1.1.0)
MARKETING_VERSION="${VERSION#v}"

SIGN_IDENTITY="Developer ID Application: CENTAUR LABS OU (992N457T8D)"
TEAM_ID="992N457T8D"

BUILD_DIR="$PROJECT_DIR/.build/xcode"
APP_NAME_LOWER=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')
INSTALL_ROOT="/tmp/${APP_NAME_LOWER}-release"
APP_PATH="$INSTALL_ROOT/Applications/$APP_NAME.app"
ZIP_PATH="/tmp/$APP_NAME-${VERSION}.zip"

echo "==> Building $APP_NAME ${VERSION} (signed with Developer ID)..."
rm -rf "$INSTALL_ROOT" "$BUILD_DIR"
xcodebuild -project "$XCODEPROJ" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    OTHER_CODE_SIGN_FLAGS="--options=runtime" \
    MARKETING_VERSION="$MARKETING_VERSION" \
    DSTROOT="$INSTALL_ROOT" \
    install 2>&1 | tee /tmp/${APP_NAME_LOWER}-build.log | grep -E "error:|warning:|SUCCEEDED|FAILED" | tail -20
# Check for build failure
if grep -q "BUILD FAILED\|** INSTALL FAILED" /tmp/${APP_NAME_LOWER}-build.log; then
    echo "ERROR: Build failed. See /tmp/${APP_NAME_LOWER}-build.log"
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: Build failed — $APP_PATH not found"
    exit 1
fi

echo "==> App built at $APP_PATH"

# Verify code signature
echo "==> Verifying signature..."
codesign --verify --deep --strict "$APP_PATH"
echo "    Signature OK"

# Notarize unless skipped
if ! $SKIP_NOTARIZE; then
    echo "==> Creating zip for notarization..."
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    echo "==> Submitting for notarization..."
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "notarize" \
        --wait

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"

    # Re-zip with stapled ticket
    rm -f "$ZIP_PATH"
fi

echo "==> Creating distribution zip..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

SIZE=$(du -h "$ZIP_PATH" | cut -f1)
echo "    $ZIP_PATH ($SIZE)"

# Create GitHub release
echo "==> Publishing GitHub release ${VERSION}..."
gh release create "$VERSION" "$ZIP_PATH" \
    --title "$APP_NAME ${VERSION}" \
    --notes "$(cat <<EOF
## $APP_NAME ${VERSION}

### Installation
Download **$APP_NAME-${VERSION}.zip**, unzip, and drag to /Applications.
EOF
)" \
    --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"

echo ""
echo "==> Done! Release published:"
gh release view "$VERSION" --json url -q .url

# Cleanup
rm -f "$ZIP_PATH"
rm -rf "$INSTALL_ROOT"
