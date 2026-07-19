#!/usr/bin/env bash
# Builds the Swift package and packages it as a proper .app bundle.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Meeting Transcriber"
APP_DIR="$SCRIPT_DIR/$APP_NAME.app"
BUNDLE_EXECUTABLE="MeetingTranscriber"
BUNDLE_ID="com.wasim.media-summarizer"

# Prefer a full Xcode toolchain if one is present — the Command Line Tools SDK
# can fail release builds in some environments.
if [ -z "$DEVELOPER_DIR" ] && compgen -G "/Applications/Xcode*.app" >/dev/null; then
  export DEVELOPER_DIR="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -n1)/Contents/Developer"
fi

cd "$SCRIPT_DIR"

echo ""
echo "═══════════════════════════════════════════════"
echo "  Building Meeting Transcriber (native Swift)"
echo "═══════════════════════════════════════════════"
echo ""

# ── Resolve + build ──────────────────────────────────────────────────────────
echo "▸ Resolving Swift packages (downloads WhisperKit on first build)…"
swift package resolve

echo "▸ Compiling (release, arm64)…"
swift build -c release --arch arm64

BINARY="$SCRIPT_DIR/.build/arm64-apple-macosx/release/$BUNDLE_EXECUTABLE"
if [ ! -f "$BINARY" ]; then
    echo "Error: Build succeeded but binary not found at $BINARY"
    exit 1
fi

# ── Assemble .app bundle ─────────────────────────────────────────────────────
echo "▸ Assembling .app bundle…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/$BUNDLE_EXECUTABLE"

cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>    <string>$BUNDLE_EXECUTABLE</string>
    <key>CFBundleIdentifier</key>    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>          <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>   <string>$APP_NAME</string>
    <key>CFBundleVersion</key>       <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>   <string>APPL</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSPrincipalClass</key>      <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>NSHumanReadableCopyright</key><string>© 2025 Wasim Osman</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

# ── Ad-hoc code sign ─────────────────────────────────────────────────────────
echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_DIR"

echo ""
echo "✅  Done: $APP_DIR"
echo ""
echo "   • Double-click to launch from Finder"
echo "   • Or drag to /Applications"
echo "   • First Transcribe click: downloads WhisperKit model (~1 GB)"
echo "   • Process Summary uses on-device Apple Intelligence (no download)"
echo ""
