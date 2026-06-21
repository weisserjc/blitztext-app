# Roadmap

This is a preview roadmap, not a promise.

## Current Scope

- macOS menubar app
- experimental iOS app and custom keyboard extension
- local recording and hotkeys
- direct OpenAI API calls with a user-provided API key
- transcription, rewriting, calmer-message, and emoji workflows
- no hosted backend
- no packaged public release

## Next Useful Work

- Make first-run setup clearer.
- Improve credential setup, validation, and recovery UX.
- Add a small automated test layer around prompt construction and text quality filters.
- Add provider boundaries so OpenAI and future local transcription can be swapped more cleanly.
- Prototype local transcription with WhisperKit or whisper.cpp.
- Reduce the Accessibility blast radius, ideally by moving synthetic paste into a smaller helper with narrower responsibilities.
- Add stronger supply-chain checks around downloaded local speech models.
- Add signed and notarized release builds when the project is ready for non-developer users.
- Improve the iOS return flow if Apple exposes a more reliable public API or if a robust background-session architecture is added.

## Not In Scope Yet

- Production support.
- Accounts, sync, teams, or hosted infrastructure.
- Claims that the app is offline or privacy-complete.
- App Store distribution.
