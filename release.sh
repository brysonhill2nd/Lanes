#!/bin/zsh
# Builds Lanes for release: one app for Apple Silicon and Intel, hardened,
# packed in dist/Lanes-<version>.dmg with an Applications shortcut.
#
# With a "Developer ID Application" certificate in your keychain and a notarytool
# profile (see RELEASE.md) the app and disk image are signed, notarized and
# stapled, so the download opens on any Mac. Without them this makes a
# local-only build that opens on this Mac and is blocked everywhere else.
set -euo pipefail
cd "${0:A:h}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
APP=dist/Lanes.app
DMG=dist/Lanes-$VERSION.dmg
NOTARY_PROFILE=${LANES_NOTARY_PROFILE:-lanes-notary}
SOURCES=(Sources/Model.swift Sources/WindowManager.swift Sources/Views.swift Sources/Editor.swift Sources/NativeResizeGrip.swift Sources/LanePicker.swift Sources/HoverScrollView.swift Sources/Tour.swift Sources/main.swift)
FRAMEWORKS=(-framework AppKit -framework SwiftUI -framework ApplicationServices -framework Carbon -framework ServiceManagement)

rm -rf dist build/release
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources build/release build/module-cache

print "Building Lanes $VERSION for Apple Silicon and Intel…"
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -module-cache-path build/module-cache -target $arch-apple-macosx14.0 $SOURCES -o build/release/Lanes-$arch $FRAMEWORKS
done
lipo -create build/release/Lanes-arm64 build/release/Lanes-x86_64 -output $APP/Contents/MacOS/Lanes
cp Info.plist $APP/Contents/Info.plist
xcrun swift -module-cache-path build/module-cache Tools/render-icon.swift build/release/Lanes.iconset
iconutil -c icns build/release/Lanes.iconset -o $APP/Contents/Resources/Lanes.icns

IDENTITY=${LANES_DEVELOPER_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}
if [[ -n "$IDENTITY" ]]; then
  print "Signing with $IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" $APP
  DISTRIBUTABLE=1
else
  print "No Developer ID certificate found. Making a LOCAL-ONLY build: it opens on this Mac, other Macs will block it."
  if [[ ! -f .signing/imported ]]; then print "Run Tools/setup-signing.py --import first." >&2; exit 1; fi
  security unlock-keychain -p "$(cat .signing/keychain-password)" "$PWD/.signing/lanes-signing.keychain-db"
  hash="$(/usr/bin/openssl x509 -in .signing/certificate.pem -outform DER | /usr/bin/shasum -a 1 | cut -d ' ' -f 1)"
  codesign --force --options runtime --sign 'Lanes Local Development' --keychain "$PWD/.signing/lanes-signing.keychain-db" --identifier com.bryson.lanes --requirements "=designated => identifier \"com.bryson.lanes\" and certificate leaf = H\"$hash\"" $APP
  DISTRIBUTABLE=0
fi
codesign --verify --deep --strict $APP

print "Packing $DMG…"
# dmgbuild lays out the window: Lanes on the left, an arrow, Applications on the right.
if [[ ! -x build/dmgbuild-venv/bin/dmgbuild ]]; then
  python3 -m venv build/dmgbuild-venv
  build/dmgbuild-venv/bin/pip install --quiet dmgbuild==1.6.7
fi
xcrun swift -module-cache-path build/module-cache Tools/render-dmg-background.swift build/release/dmg
build/dmgbuild-venv/bin/dmgbuild -s Tools/dmg-settings.py -D app=$APP -D background=build/release/dmg/background.png -D volume_icon=$APP/Contents/Resources/Lanes.icns "Lanes" $DMG

if (( DISTRIBUTABLE )); then
  codesign --force --timestamp --sign "$IDENTITY" $DMG
  print "Notarizing (usually a few minutes)…"
  xcrun notarytool submit $DMG --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple $DMG
  spctl --assess --type open --context context:primary-signature -vv $DMG
  print "Ready to publish: $DMG"
else
  print "Local-only disk image: $DMG (not for publishing)"
fi
print "Architectures: $(lipo -archs $APP/Contents/MacOS/Lanes)"
print "SHA-256: $(shasum -a 256 $DMG | cut -d ' ' -f 1)"
