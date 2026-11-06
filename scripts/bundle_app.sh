#!/usr/bin/env bash
set -e

APP_NAME="Osprey"
# Single source of truth for the version: Cargo.toml
VERSION="$(grep -m1 '^version' Cargo.toml | cut -d'"' -f2)"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Building Rust CLI..."
cargo build --release

echo "==> Building Native Swift macOS App..."
SWIFT_BUILD_DIR="${TMPDIR:-/tmp}/osprey-macos-build"
rm -rf "$SWIFT_BUILD_DIR"
(cd macos && swift build -c release --build-path "$SWIFT_BUILD_DIR")

echo "==> Packaging $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

# Copy Native Mach-O Executable
SWIFT_FOUND=$(find "$SWIFT_BUILD_DIR" -name "Osprey" -type f ! -path "*/dSYM/*" | head -n 1)
if [ -n "$SWIFT_FOUND" ] && [ -f "$SWIFT_FOUND" ]; then
    cp "$SWIFT_FOUND" "$MACOS/Osprey"
else
    echo "Error: Swift executable Osprey not found in $SWIFT_BUILD_DIR"
    exit 1
fi

# Also include CLI tool inside bundle
if [ -f "target/aarch64-apple-darwin/release/osprey" ]; then
    cp target/aarch64-apple-darwin/release/osprey "$MACOS/osprey-cli"
elif [ -f "target/release/osprey" ]; then
    cp target/release/osprey "$MACOS/osprey-cli"
fi

# Copy AppIcon.icns
if [ -f "assets/AppIcon.icns" ]; then
    cp assets/AppIcon.icns "$RESOURCES/AppIcon.icns"
fi

# Create Info.plist
cat <<EOF > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Osprey</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.kraloveckey.osprey</string>
    <key>CFBundleName</key>
    <string>Osprey</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

chmod +x "$MACOS/Osprey"
chmod +x "$MACOS/osprey-cli"

# Ad-hoc sign for local execution and notification center authorization
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "==> Successfully created $APP_BUNDLE (v$VERSION)"
