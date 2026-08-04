# Quasimorph for macOS

Builds a macOS app from **your own Windows copy** of Quasimorph.

No game files are included here. Nothing is uploaded.

## You need

- Apple Silicon Mac
- macOS 13 or newer
- Portable Quasimorph copy: RAR, 7Z, ZIP, folder, or `Quasimorph.exe`
- Internet for the first build

## Do this

1. Download `Quasimorph-for-macOS.zip` from [Releases](../../releases/latest).
2. Unzip it.
3. Open Terminal.
4. Run:

```bash
cd ~/Downloads/Quasimorph-for-macOS
```

5. Type this, add one space, then drag your Quasimorph archive into Terminal:

```bash
./quasimorph-macos build
```

6. Press Return.
7. Open the DMG created on your Desktop.

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

- Portable Windows copies only. Windows installers and Steam setup are not supported.
- The tool downloads checksum-verified Sikarugir, Wine, DXMT, and 7-Zip components.
- The generated DMG contains your game. **Do not redistribute it.**
- This is an unofficial compatibility tool. It is not affiliated with Quasimorph or Magnum Scriptum.

## Build from source

Requires Xcode Command Line Tools:

```bash
swift test
swift build -c release
```

Own code is MIT licensed. Downloaded components keep their original licenses. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
