#!/usr/bin/env bash
# Build the SwiftUI app with SwiftPM and wrap it into spacectl-ui.app (no Xcode project needed).
# Usage: ./build.sh          build a universal (arm64 + x86_64) spacectl-ui.app
#        ./build.sh dist     also create dist/spacectl-ui-<version>.zip for sharing
set -euo pipefail
cd "$(dirname "$0")"

version=$(cat VERSION)
app=spacectl-ui.app

# Both triples share one output dir, so copy each binary out before the next build overwrites it.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bins=()
for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx14.0"
  cp "$(swift build -c release --triple "$arch-apple-macosx14.0" --show-bin-path)/spacectl-ui" "$tmp/$arch"
  bins+=("$tmp/$arch")
done

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
lipo -create "${bins[@]}" -output "$app/Contents/MacOS/spacectl-ui"

# App icon: round the source PNG, then build the .icns with sips + iconutil.
mkdir -p "$app/Contents/Resources"
swift make-icon.swift Resources/AppIcon.png "$tmp/icon-1024.png"
iconset="$tmp/AppIcon.iconset"
mkdir -p "$iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$tmp/icon-1024.png" --out "$iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$tmp/icon-1024.png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Spacelift Stacks</string>
  <key>CFBundleExecutable</key><string>spacectl-ui</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>io.github.luispcoutinho.spacectl-ui</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

# Ad-hoc signature: no Developer ID, so teammates must clear quarantine once (see README).
codesign --force --sign - "$app" >/dev/null 2>&1 || echo "warning: codesign failed (app may still run)"
echo "built: $(pwd)/$app ($(lipo -archs "$app/Contents/MacOS/spacectl-ui"))"

if [[ "${1:-}" == "dist" ]]; then
  out="dist/spacectl-ui-$version"
  rm -rf dist
  mkdir -p "$out"
  cp -R "$app" "$out/"
  cp README.md "$out/"
  # ditto keeps the bundle's signature and permissions intact, unlike plain zip.
  ditto -c -k --keepParent "$out" "$out.zip"
  rm -rf "$out"
  echo "package: $(pwd)/$out.zip ($(du -h "$out.zip" | cut -f1))"
fi
