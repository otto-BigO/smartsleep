<p align="center">
  <img src="docs/banner.png" alt="SmartSleep" width="800">
</p>

<h4 align="center">A macOS menu bar app that keeps your Mac awake while music plays, and turns the screen off when you close the lid.</h4>

<p align="center">
  <img src="docs/settings.png" alt="Settings window" width="300">
  &nbsp;&nbsp;&nbsp;
  <img src="docs/icon.png" alt="App icon" width="170">
</p>

<p align="center">
  <img src="docs/menubar-bars.gif" alt="Menu bar icon while music plays" height="60">
  &nbsp;&nbsp;
  <img src="docs/menubar-pulse.gif" alt="Menu bar icon, pulse style" height="60">
</p>

## What it does

- When an app plays sound, the Mac stays awake. Close the lid and the music keeps going.
- If you close the lid while something plays, the screen turns off. It comes back at the same brightness when you open it.
- When the sound stops, the Mac sleeps normally again.
- The menu bar icon moves while music plays. The settings window shows what is playing, with the album cover from Spotify or the video thumbnail from YouTube in Brave.

## Requirements

- An Apple Silicon Mac with macOS 14.2 or newer. It runs on older versions, but cannot tell which app is playing.
- Xcode Command Line Tools: `xcode-select --install`

## Install

```bash
./install.sh
```

This builds the app, copies it to `~/Applications` and starts it. The first time, it asks for your password to add one sudoers rule, `/etc/sudoers.d/smartsleep`, so the app can run `pmset -a disablesleep` without a password. That command is the only way to stop a Mac from sleeping when the lid closes.

To build without installing, run `./build.sh`. The app ends up in `build/SmartSleep.app`.

## Good to know

- If the app quits or crashes, the Mac does not get stuck awake. It resets `disablesleep` when it exits and again every time it starts.
- macOS asks once whether SmartSleep may control Spotify and Brave. That is only used to read the title and the cover.
- Logs: `/usr/bin/log stream --predicate 'subsystem == "com.personal.SmartSleep"'`
