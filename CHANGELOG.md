# Changelog

## 1.0.0 (2026-09-11)

First release.

- Keeps the Mac awake while any app plays sound. It reads which app is playing from CoreAudio (macOS 14.2 or newer).
- Turns the screen off when the lid closes during playback, and restores the brightness when it opens.
- Never leaves the Mac unable to sleep: the power assertions end with the app, and `disablesleep` is reset when the app quits, when it is stopped, and every time it starts.
- Asks once for permission to prevent sleep with the lid closed, so no install script is needed.
- Settings window with the current song, the album cover and the toggles.
- Animated menu bar icon while music plays: bars, pulse or off.
- Dictation does not count as playback.
- DMG installer.
