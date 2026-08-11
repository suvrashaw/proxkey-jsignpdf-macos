#!/bin/bash
# Builds JSignPdf ProxKey.app in /Applications: a double-clickable wrapper
# around run-jsignpdf.command, with JSignPdf's own icon extracted from its jar.
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JSIGNPDF_JAR="$REPO_DIR/vendor/jsignpdf-2.3.0/JSignPdf.jar"
APP="/Applications/JSignPdf ProxKey.app"

if [ ! -f "$JSIGNPDF_JAR" ]; then
  echo "vendor/jsignpdf-2.3.0/JSignPdf.jar not found."
  echo "Download JSignPdf 2.3.0 from https://github.com/intoolswetrust/jsignpdf/releases"
  echo "and unzip it into vendor/jsignpdf-2.3.0/"
  exit 1
fi

echo "Extracting icon from JSignPdf.jar..."
ICON_TMP=$(mktemp -d)
unzip -o -j "$JSIGNPDF_JAR" "net/sf/jsignpdf/signedpdf32.png" -d "$ICON_TMP" > /dev/null

mkdir -p "$ICON_TMP/icon.iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size "$ICON_TMP/signedpdf32.png" --out "$ICON_TMP/icon.iconset/icon_${size}x${size}.png" > /dev/null
  double=$((size * 2))
  sips -z $double $double "$ICON_TMP/signedpdf32.png" --out "$ICON_TMP/icon.iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$ICON_TMP/icon.iconset" -o "$ICON_TMP/AppIcon.icns"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ICON_TMP/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ICON_TMP/icon.iconset/icon_256x256@2x.png" "$APP/Contents/Resources/AppIcon.png"
cp "$ICON_TMP/icon.iconset/icon_256x256@2x.png" "$REPO_DIR/scripts/AppIcon.png"
rm -rf "$ICON_TMP"

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>JSignPdf ProxKey</string>
	<key>CFBundleDisplayName</key>
	<string>JSignPdf ProxKey</string>
	<key>CFBundleIdentifier</key>
	<string>com.jsignpdf-proxkey.launcher</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleExecutable</key>
	<string>JSignPdf ProxKey</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSMinimumSystemVersion</key>
	<string>10.10</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

cat > "$APP/Contents/MacOS/JSignPdf ProxKey" << LAUNCHER
#!/bin/bash
exec "$REPO_DIR/run-jsignpdf.command"
LAUNCHER

chmod +x "$APP/Contents/MacOS/JSignPdf ProxKey"
xattr -cr "$APP"

# Ad-hoc sign so Gatekeeper doesn't reject the app on open/double-click.
# (An unsigned freshly-built bundle fails "spctl -a" with "no usable
# signature" — direct execution of the binary bypasses that check, which
# is why testing via Terminal can look fine while double-click silently
# fails. Ad-hoc signing, not just clearing quarantine, is what fixes it.)
codesign --force --deep -s - "$APP" 2>&1

echo "Built: $APP"
echo "Launch it from Applications or Spotlight."
