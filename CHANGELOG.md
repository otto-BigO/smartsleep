# Changelog

## 1.0.2 (2026-09-13)

- When "Keep awake while playing" is off, the menu bar shows a pause icon and the menu and settings window say "Paused". Before, it looked the same as nothing playing, so it was easy to switch off by accident and not notice.
- macOS alert and notification sounds no longer count as playback.
- If the sudoers rule is added or removed while the app runs, the app notices the next time it runs pmset, or when you open it again. Before, it only checked at launch.

## 1.0.1 (2026-09-11)

- The sudoers rule now allows only `pmset -a disablesleep 0` and `pmset -a disablesleep 1`. Before, it allowed any extra arguments after `disablesleep`, which let any program running as you change other power settings as root.
- MIT license.

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
