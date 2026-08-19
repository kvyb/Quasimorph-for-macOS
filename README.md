# Quasimorph for macOS

Builds a macOS app for **your own Steam or Windows copy** of Quasimorph.

No game files are included here. Nothing is uploaded.

## It works

![Quasimorph 1.0 running in the generated macOS wrapper](assets/quasimorph-running-macos.webp)

*Quasimorph 1.0 running on Apple Silicon macOS from a wrapper produced by this tool.*

## You need

- Apple Silicon Mac
- macOS 15 or newer
- Quasimorph in your Steam account, or a local Windows copy
- Internet for the first build

## Do this

1. Download `Quasimorph-for-macOS.zip` from [Releases](../../releases/latest).
2. Unzip it.
3. Open Terminal.
4. Run:

```bash
cd ~/Downloads/Quasimorph-for-macOS
```

## Steam version

The Steam install/updater flow is verified and works.

Run:

```bash
./quasimorph-macos steam
```

Then:

1. Open the DMG created on your Desktop.
2. Drag `Quasimorph.app` to Applications.
3. Open it. The official Windows Steam client installs.
4. Sign in and install Quasimorph when Steam asks.
5. Open `Quasimorph.app` again to play.

Your password and Steam Guard stay inside Valve's Steam client. The CLI never asks for them.

## Local copy

Type this, add one space, then drag your RAR, ZIP, folder, or `Quasimorph.exe` into Terminal:

```bash
./quasimorph-macos build
```

Then press Return and open the DMG created on your Desktop.

Example:

```bash
./quasimorph-macos build "/Users/me/Downloads/Quasimorph.v1.0.rar"
```

No path? Use the picker:

```bash
./quasimorph-macos build
```

## Output

```text
Desktop/Quasimorph macOS/
├── Quasimorph.app
├── Quasimorph-macOS-v1.0.dmg
└── BUILD-REPORT.txt
```

## First launch

If macOS blocks it:

1. Right-click `Quasimorph.app`.
2. Click **Open**.
3. Click **Open** again.

## Controls stop after Cmd+Tab?

Rebuild the app with CLI `0.3.0` or newer. Older wrappers used Wine 10, which can lose all mouse and keyboard input after macOS changes focus. The new runtime uses Wine 11.15, where that focus bug is fixed.

If you still use an older build, relaunching the app is the only reliable workaround. Repeatedly switching away and back may restore input, but it is not a permanent fix.

On macOS 13 or 14, use the older `0.2.1` release. It can run there, but it cannot include this Wine 11 fix.

## Updating an existing app

Back up your saves before replacing `Quasimorph.app`:

1. Right-click the old app and choose **Show Package Contents**.
2. Open `Contents/SharedSupport/prefix/drive_c/users/<your user>/AppData/LocalLow/`.
3. Copy the `Magnum Scriptum LTD` folder somewhere safe.
4. Build and open the new app once, then quit it.
5. Put the backup in the new app under `Contents/SharedSupport/prefix/drive_c/users/crossover/AppData/LocalLow/`.

Steam Cloud may restore saves automatically, but make the backup anyway.

## Stuck?

Run:

```bash
./quasimorph-macos doctor
```

Then retry with details:

```bash
./quasimorph-macos build "/path/to/game.rar" --verbose
```

## Important

- Steam mode downloads the game through the account that owns it. It does not bypass Steam.
- Steam remains responsible for Cloud, Workshop, achievements, ownership checks, and updates.
- Local mode supports RAR, 7Z, ZIP, folders, or `Quasimorph.exe`; other Windows installers are not supported.
- The tool downloads a checksum-verified Sikarugir template, Wine 11.15 runtime, DXVK-macOS, and 7-Zip helper.
- After Steam installs the game, the app contains account-managed game files. **Do not redistribute it.**
- This is an unofficial compatibility tool. It is not affiliated with Quasimorph or Magnum Scriptum.

## Build from source

Requires Xcode Command Line Tools:

```bash
swift test
swift build -c release
```

Own code is MIT licensed. Downloaded components keep their original licenses. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
