# Blitztext for iOS

Blitztext for iOS is an experimental open-source iPhone variant of
[Blitztext](https://github.com/cmagnussen/blitztext-app) for turning speech into text —
not in one app, but in **any** app, through a custom keyboard.

Like the original, it is intentionally small and hackable. The goal is to make a real
mobile dictation workflow visible: switch to the Blitztext keyboard, dictate, get clean
text back, and have it inserted where you were typing.

This is a learning and experimentation project, not a polished product.

> Preview status: bring your own OpenAI API key, no hosted backend, no warranty, no
> support guarantee.

## What It Does

- **Blitztext (Wörtlich)**: dictate in any app via the Blitztext keyboard; the spoken
  text is transcribed 1:1 and inserted into the field you were using.
- **Blitztext+ (Verbessert)**: same flow, but the rough transcript is rewritten into
  cleaner, shorter writing — spelling and grammar fixed, filler removed — while the
  meaning stays intact.

The mode is a toggle that lives in the keyboard, on the recording screen, and as a
default in settings.

## How It Works

iOS does not let a keyboard extension record the microphone reliably (on current devices
the audio unit is refused outright, even with Full Access). So Blitztext splits the work:

1. You tap **Diktieren** on the Blitztext keyboard.
2. The keyboard opens the Blitztext app, which **records immediately** (the microphone
   works in a normal app) and transcribes via OpenAI Whisper.
3. The finished text is placed in the shared keychain.
4. You tap the iOS **"‹ Back"** chip (top-left) to return to your app — an animated hint
   points to it.
5. The keyboard sees the prepared text and inserts it via the text document proxy.

There is no public iOS API to return to an arbitrary previous app automatically, so the
system "‹ Back" chip is the deliberate, reliable return path.

The transcript is exchanged between app and keyboard through the **shared keychain**, not
the clipboard: the keyboard never reads the pasteboard, which avoids the recurring iOS
"Allow Paste?" prompt (and pulling content off the Mac via Universal Clipboard).

## Important Preview Notes

- iPhone only; a **real device** is required (the keyboard-microphone limitation does not
  reproduce in the Simulator).
- **Full Access** must be enabled for the Blitztext keyboard (needed for the keychain
  and for opening the app).
- Bring your own OpenAI API key (stored in the keychain by the app, shared with the
  keyboard). No hosted Blitztext backend is included or provided.
- The improve/cleanup mode sends the transcript to OpenAI for rewriting.

## Build & Run

The iOS targets (`BlitztextiOS` app + `BlitztextKeyboard` extension) are defined in
`BlitztextMac/project.yml` (xcodegen) alongside the macOS app. See
[`docs/ios-keyboard-mvp.md`](docs/ios-keyboard-mvp.md) for the full build/install
commands. In short: `xcodegen generate`, build the `BlitztextiOS` scheme to a connected
device with your own signing team, install with `xcrun devicectl`.

Note: the bundle identifiers (`de.johannesweisser.blitztext.ios*`) and signing team in
`project.yml` are personal placeholders — replace them with your own.

## Relationship to the original

This is a fork of [cmagnussen/blitztext-app](https://github.com/cmagnussen/blitztext-app)
that adds the iOS app and keyboard. The macOS menubar app is unchanged. Same spirit, same
MIT license.
