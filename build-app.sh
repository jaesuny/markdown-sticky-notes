#!/bin/bash

# Build script to create a proper macOS .app bundle

set -e

echo "Building StickyNotes.app..."

# Build the web editor first
echo "Building web editor..."
cd editor-web
npm run build
cp dist/editor.bundle.js ../Sources/StickyNotes/Resources/Editor/editor.bundle.js
cd ..
echo "✅ Web editor built"

# Build the executable
swift build -c release

# Create app bundle structure
APP_NAME="StickyNotes"
APP_DIR="build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean and create directories
rm -rf build
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp ".build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# Copy resources
cp -R "Sources/StickyNotes/Resources/" "$RESOURCES_DIR/"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.mdstickynotes</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MD Sticky Notes</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Ad-hoc code signing (allows "right-click → Open" instead of "damaged" error)
echo "Signing app..."
codesign --force --deep --sign - "$APP_DIR"
echo "✅ App signed (ad-hoc)"

echo "✅ StickyNotes.app created successfully at: $APP_DIR"

# Create styled DMG for distribution
echo "Creating DMG..."
DMG_TMP="build/tmp.dmg"
DMG_PATH="build/MDStickyNotes.dmg"
VOL_NAME="MD Sticky Notes"
DMG_DIR="build/dmg"
rm -rf "$DMG_DIR" "$DMG_PATH" "$DMG_TMP"
mkdir -p "$DMG_DIR"
cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

# Create read-write DMG first (for styling)
hdiutil create -volname "$VOL_NAME" -srcfolder "$DMG_DIR" -ov -format UDRW "$DMG_TMP"
rm -rf "$DMG_DIR"

# Mount and style with AppleScript
MOUNT_DIR="/Volumes/$VOL_NAME"
hdiutil attach "$DMG_TMP" -readwrite -noverify -noautoopen
sleep 3

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 400, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set position of item "StickyNotes.app" of container window to {150, 80}
        set position of item "Applications" of container window to {150, 260}
        close
        open
    end tell
end tell
APPLESCRIPT

# Wait for Finder to apply changes
sleep 2
sync

# Unmount
hdiutil detach "$MOUNT_DIR"

# Convert to compressed read-only DMG
hdiutil convert "$DMG_TMP" -format UDZO -o "$DMG_PATH"
rm -f "$DMG_TMP"
echo "✅ DMG created at: $DMG_PATH"

echo "To run: open $APP_DIR"
