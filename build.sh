#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/Lanes.app/Contents/MacOS build/Lanes.app/Contents/Resources build/module-cache
xcrun swiftc -swift-version 5 -O -module-cache-path build/module-cache -target arm64-apple-macosx14.0 Sources/Model.swift Sources/WindowManager.swift Sources/Views.swift Sources/Editor.swift Sources/NativeResizeGrip.swift Sources/LanePicker.swift Sources/HoverScrollView.swift Sources/Tour.swift Sources/main.swift -o build/Lanes.app/Contents/MacOS/Lanes -framework AppKit -framework SwiftUI -framework ApplicationServices -framework Carbon -framework ServiceManagement
cp Info.plist build/Lanes.app/Contents/Info.plist
xcrun swift -module-cache-path build/module-cache Tools/render-icon.swift build/Lanes.iconset
iconutil -c icns build/Lanes.iconset -o build/Lanes.app/Contents/Resources/Lanes.icns
if [[ -f .signing/imported ]]; then
  lanes_keychain_password="$(cat .signing/keychain-password)"
  security unlock-keychain -p "$lanes_keychain_password" "$PWD/.signing/lanes-signing.keychain-db"
  lanes_certificate_hash="$(/usr/bin/openssl x509 -in .signing/certificate.pem -outform DER | /usr/bin/shasum -a 1 | cut -d ' ' -f 1)"
  codesign --force --sign 'Lanes Local Development' --keychain "$PWD/.signing/lanes-signing.keychain-db" --identifier com.bryson.lanes --requirements "=designated => identifier \"com.bryson.lanes\" and certificate leaf = H\"$lanes_certificate_hash\"" build/Lanes.app
else
  # No local identity: sign ad hoc. macOS asks for window access again after every rebuild.
  printf 'No local signing identity (Tools/setup-signing.py --import). Signing ad hoc.\n'
  codesign --force --sign - build/Lanes.app
fi
codesign --verify --deep --strict build/Lanes.app
printf 'Built %s/build/Lanes.app\n' "$PWD"
