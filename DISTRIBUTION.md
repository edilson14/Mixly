# Mixly Distribution Guide

## Quick Start

```bash
./build_and_distribute.sh YOUR_TEAM_ID
```

## Full Process

### 1️⃣ Prerequisites

- **Apple Developer Account** (personal/team)
- Find your **Team ID**: [developer.apple.com/account](https://developer.apple.com/account/#/membership/)
  - Looks like: `ABC123DEF4`

### 2️⃣ Build & Package

```bash
./build_and_distribute.sh ABC123DEF4 your.email@apple.com
```

This will:
- ✅ Clean and build Release version
- ✅ Sign with your Developer ID Application certificate
- ✅ Create `Mixly.dmg` with installer layout

### 3️⃣ Notarization (Recommended for Web Distribution)

If distributing via internet, notarize to bypass Gatekeeper warnings:

```bash
# First, generate app-specific password at:
# https://appleid.apple.com/account/manage → Security → App Passwords

xcrun notarytool submit Mixly.app \
  --apple-id your.email@apple.com \
  --team-id ABC123DEF4 \
  --password "xxxx-xxxx-xxxx-xxxx" \
  --wait
```

Then staple the notarization:

```bash
xcrun stapler staple Mixly.app
```

### 4️⃣ Distribution Options

#### Local File (No Notarization Needed)
- User downloads `Mixly.dmg`
- Double-clicks to mount and drag `Mixly.app` to Applications

#### Web Distribution (Needs Notarization)
- Upload `Mixly.dmg` to your server
- macOS will verify via notarization, no "unidentified developer" warnings

#### App Store
- Requires separate setup in App Store Connect
- Different code signing and provisioning

## Project Config

- **Bundle ID**: `sound.Mixly`
- **Team ID**: `{Your Team ID}`
- **Signing ID**: `Developer ID Application`
- **Entitlements**: Audio capture (system permission required)

## Files

```
build_and_distribute.sh    # Automated build script
Mixly.dmg                  # Distribution package (after running script)
build/Products/Release/    # Build artifacts
```

## Troubleshooting

### "No provisioning profile" warning
- Ignore—auto-selected for Developer ID signing

### App won't start ("damaged")
- Run: `xattr -rd com.apple.quarantine Mixly.app`
- Or: Re-download and notarize

### Notarization takes too long
- Use `--wait` flag to poll for completion

---

**Version**: 1.0  
**Last Updated**: 2026-08-15
