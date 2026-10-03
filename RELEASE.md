# Releasing Lanes

Lanes is free and distributed as a notarized disk image on GitHub Releases. It is not on the Mac App Store (see "Why not the App Store" below).

## One-time setup (about an hour, plus Apple's approval)

1. **Join the Apple Developer Program** at https://developer.apple.com/programs ($99 a year). Approval usually takes 1–2 days.
2. **Create a Developer ID certificate.** In Xcode: Settings › Accounts › your team › Manage Certificates › **+** › **Developer ID Application**. It lands in your login keychain.
3. **Create an App Store Connect API key** at https://appstoreconnect.apple.com › Users and Access › Integrations › **Individual Keys**. Download the `.p8` file (Apple lets you download it once) and note its Key ID.
4. **Save the notarization login** in your keychain:

   ```sh
   xcrun notarytool store-credentials lanes-notary --key ~/Downloads/ApiKey_KEYID.p8 --key-id KEYID
   ```

   An individual key has no Issuer ID: press Return when asked. If Apple answers "A required agreement is missing or has expired" (403), accept the pending agreement under App Store Connect › Business, wait a few minutes and try again.

Keychain items are unreadable while the screen is locked, and the first `codesign` asks for your Mac password: choose **Always Allow** so later releases run unattended.

## Every release (about 15 minutes)

1. Bump `CFBundleShortVersionString` (for example 1.0.1) and `CFBundleVersion` (one higher) in `Info.plist`.
2. Run the checks: `./test.sh`
3. Build, sign, notarize and staple: `./release.sh`

   The disk image opens to a window with Lanes, an arrow and Applications (layout in `Tools/dmg-settings.py`, background drawn by `Tools/render-dmg-background.swift`). It finds your Developer ID certificate on its own and ends with `Ready to publish: dist/Lanes-<version>.dmg`. Without the certificate it makes a local-only build and says so; do not publish that one.
4. Check it the way a stranger would: copy the disk image to another Mac (or another user account), open it, drag Lanes to Applications and open it. macOS should show only the normal "downloaded from the internet" question.
5. Publish it: `gh release create v<version> dist/Lanes-<version>.dmg --title "Lanes <version>" --notes "…"`, and update the version in README.md.

## Before the first public release

Lanes has only run on one Mac with a 5120 × 1440 display. Try these on a second Mac or with a friend before announcing:

- A 14" or 16" MacBook screen on its own, and a MacBook plus an external display.
- A fresh user account: first launch, the permission step, Organize, Restore, Quit.
- Full-screen apps, several Spaces, and Stage Manager on.
- Open at login on and off.
- Uninstall steps in README.md.

## What is deliberately not included

- **No automatic updates.** An updater would check a server, and Lanes promises no network requests. People get new versions from GitHub Releases. If you change your mind later, Sparkle is the standard choice.
- **No analytics or crash reporting**, for the same reason. Ask for feedback by email instead.

## Why not the App Store

App Store apps must run in Apple's sandbox. Lanes watches windows of every app, reacts when they open, and listens for a double tap of Right Command, so it would need rework and might not pass review. Every update would also wait for review. A notarized download avoids both. You can revisit this once Lanes is stable.
