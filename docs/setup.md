# Setup

This guide is for people who want to build and inspect the iOS preview themselves.

## Requirements

- macOS with full Xcode installed
- Xcode Command Line Tools selected
- XcodeGen
- A real iPhone or iPad
- An Apple development team for local device signing
- Your own OpenAI API key

Install XcodeGen if needed:

```bash
brew install xcodegen
```

## Clone

```bash
git clone https://github.com/weisserjc/blitztext-ios.git
cd blitztext-ios
```

## Configure Identifiers

Before building your own fork, replace the maintainer-local identifiers in `project.yml`,
the iOS entitlements, and `BlitztextShared/BlitztextKeychain.swift`:

- app bundle identifier
- keyboard extension bundle identifier
- Apple Team ID
- shared keychain access group

The app and keyboard must use the same keychain access group, otherwise they cannot share
API keys, mode state, or pending transcripts.

## Build With Xcode

```bash
xcodegen generate
open BlitztextiOS.xcodeproj
```

Then select the `BlitztextiOS` scheme, choose your connected device, configure signing,
and run.

## Build From Terminal

```bash
./build.sh --device <DEVICE_ID> --team <TEAM_ID> --install
```

You can list connected devices with:

```bash
xcrun devicectl list devices
```

## iPhone Setup

1. Open Blitztext.
2. Store your OpenAI API key in the Settings tab.
3. Enable the Blitztext keyboard in iOS Settings.
4. Allow **Full Access** for the Blitztext keyboard.
5. In any app, switch to the Blitztext keyboard and tap **Diktieren**.

## Troubleshooting

- If the app cannot record, check iOS microphone permission for Blitztext.
- If the keyboard cannot start the app or insert text, check that Full Access is enabled.
- If transcription fails, verify the OpenAI API key and billing status.
- If app and keyboard do not share state, check the keychain access group and entitlements.
- A real device is required for meaningful testing; simulator behavior is not enough for
  the keyboard/audio limitations.
