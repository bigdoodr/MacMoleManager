#!/bin/bash
#
# build-pkg.sh — wraps a signed, notarized MacMoleManager.app in a signed,
# notarized .pkg with scripts/postinstall attached.
#
# Run from the repo root:  ./Packaging/build-pkg.sh
#
# Two ways to get the .app this script wraps:
#
#   1. (Recommended) Xcode Organizer → Product ▸ Archive, then
#      Distribute App ▸ Direct Distribution. That signs AND notarizes
#      AND staples the app in one flow using whatever Developer ID
#      identity/notarization credentials Xcode already has configured —
#      no separate notarytool setup needed. Export it to a folder, then
#      point this script at it:
#          PREBUILT_APP_PATH=/path/to/exported/MacMoleManager.app ./Packaging/build-pkg.sh
#
#   2. Let this script do the archive+export itself (no Xcode UI) by
#      leaving PREBUILT_APP_PATH unset — it runs `xcodebuild archive`
#      and `-exportArchive` with method "developer-id", which also
#      notarizes/staples automatically as long as Xcode has notarization
#      credentials on file (Xcode ▸ Settings ▸ Accounts, or a
#      `xcrun notarytool store-credentials` profile).
#
# Either way, the resulting .pkg itself STILL needs its own separate
# notarization — Apple notarizes packages independently of the app
# inside them. Set NOTARY_PROFILE (see below) to have this script submit
# and staple the .pkg automatically; otherwise it's built signed but
# un-notarized, which Gatekeeper will flag for anyone who downloads it.
#
# Requires Xcode command-line tools and, for a distributable package, a
# "Developer ID Installer" certificate in your keychain (separate from
# the "Developer ID Application" cert used to sign the .app itself).
#
set -euo pipefail

# --- Configuration — edit these, or pass as environment variables --------
SCHEME="MacMoleManager"
PROJECT="MacMoleManager.xcodeproj"
BUNDLE_ID="rocks.scruggsfam.MacMoleManager"
VERSION="$(defaults read "$(dirname "$0")/../MacMoleManager/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")"

# Path to an already-exported, already-notarized .app (see option 1
# above). When set, this script skips `xcodebuild archive`/`-exportArchive`
# entirely and just wraps this app as-is.
PREBUILT_APP_PATH="${PREBUILT_APP_PATH:-}"

# Leave unset to build an UNSIGNED package (fine for local testing, not
# for distribution). Set to your installer identity's common name, e.g.
# "Developer ID Installer: Casey Scruggs (TEAMID1234)" — find it with:
#   security find-identity -v -p basic
INSTALLER_SIGNING_IDENTITY="${INSTALLER_SIGNING_IDENTITY:-}"

# Name of a notarytool keychain profile (one-time setup:
#   xcrun notarytool store-credentials "<profile-name>" \
#       --apple-id you@example.com --team-id TEAMID1234 --password <app-specific-password>
# ). Leave unset to skip notarizing/stapling the .pkg — only meaningful
# alongside INSTALLER_SIGNING_IDENTITY, since Apple won't notarize an
# unsigned package.
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# ---------------------------------------------------------------------------
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
COMPONENT_PKG="$BUILD_DIR/$SCHEME-component.pkg"
FINAL_PKG="$BUILD_DIR/$SCHEME-$VERSION.pkg"

mkdir -p "$BUILD_DIR"

if [ -n "$PREBUILT_APP_PATH" ]; then
    echo "==> Using prebuilt app: $PREBUILT_APP_PATH"
    if [ ! -d "$PREBUILT_APP_PATH" ]; then
        echo "error: PREBUILT_APP_PATH ($PREBUILT_APP_PATH) doesn't exist." >&2
        exit 1
    fi
    rm -rf "$EXPORT_PATH"
    mkdir -p "$EXPORT_PATH"
    cp -R "$PREBUILT_APP_PATH" "$EXPORT_PATH/$SCHEME.app"
else
    echo "==> Archiving $SCHEME..."
    rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
    xcodebuild archive \
        -project "$ROOT_DIR/$PROJECT" \
        -scheme "$SCHEME" \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS"

    echo "==> Exporting archive (developer-id: signs, notarizes, and staples if Xcode has credentials on file)..."
    EXPORT_OPTIONS_PLIST="$ROOT_DIR/Packaging/ExportOptions.plist"
    if [ ! -f "$EXPORT_OPTIONS_PLIST" ]; then
        cat > "$EXPORT_OPTIONS_PLIST" << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST_EOF
        echo "    (wrote a default Packaging/ExportOptions.plist — commit it once it matches your team)"
    fi

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
fi

APP_PATH="$EXPORT_PATH/$SCHEME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "error: expected app at $APP_PATH, not found." >&2
    exit 1
fi

echo "==> Building component package (with postinstall)..."
pkgbuild \
    --root "$EXPORT_PATH" \
    --install-location "/Applications" \
    --scripts "$ROOT_DIR/Packaging/scripts" \
    --identifier "$BUNDLE_ID.pkg" \
    --version "$VERSION" \
    "$COMPONENT_PKG"

if [ -n "$INSTALLER_SIGNING_IDENTITY" ]; then
    echo "==> Signing final package..."
    productsign --sign "$INSTALLER_SIGNING_IDENTITY" "$COMPONENT_PKG" "$FINAL_PKG"
    rm "$COMPONENT_PKG"

    if [ -n "$NOTARY_PROFILE" ]; then
        echo "==> Submitting package for notarization (this can take a few minutes)..."
        xcrun notarytool submit "$FINAL_PKG" --keychain-profile "$NOTARY_PROFILE" --wait
        echo "==> Stapling notarization ticket..."
        xcrun stapler staple "$FINAL_PKG"
    else
        echo "==> NOTARY_PROFILE not set — package is signed but NOT notarized. Gatekeeper will warn/block on other Macs until it is."
    fi
else
    echo "==> INSTALLER_SIGNING_IDENTITY not set — leaving package UNSIGNED (local testing only)."
    mv "$COMPONENT_PKG" "$FINAL_PKG"
fi

echo "==> Done: $FINAL_PKG"
