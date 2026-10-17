#!/bin/zsh
set -eu
cd "${0:A:h}"
APP="$PWD/Label Review.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -target arm64-apple-macosx13.0 -swift-version 5 -O Sources/Dataset.swift Sources/Canvas.swift Sources/App.swift -o "$APP/Contents/MacOS/LabelReview" -framework AppKit
TEMP_DIR="$(mktemp -d -t label-review-icon)"
ICONSET="$TEMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "$TEMP_DIR"' EXIT
swift Sources/GenerateIcon.swift "$ICONSET/icon-1024.png"
for size in 16 32 64 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$ICONSET/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" "$ICONSET/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LabelReview</string>
<key>CFBundleIdentifier</key><string>local.happitat.labelreview</string>
<key>CFBundleName</key><string>Label Review</string>
<key>CFBundleDisplayName</key><string>Label Review</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
