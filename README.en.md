# Zipchik

[Русский](README.md) · [Licenses and notices](NOTICE.md)

Zipchik is a small macOS archive viewer and selective extractor. It is designed around Finder Quick Look rather than a full archive-manager window.

Requirements: Apple Silicon (arm64) and macOS 14 or later. The interface follows the macOS language and includes English and Russian localizations.

> Status: preview. The DMG is ad-hoc signed and **not notarized** yet. macOS may show a first-launch warning on another Mac; notarization is intentionally deferred.

## Install

1. Download `Zipchik-0.2.2-arm64.dmg` from [Releases](https://github.com/alex1362/zipchik/releases).
2. Drag Zipchik to `Applications`.
3. Select an ordinary archive in Finder and press Space for Quick Look. For a password-protected or multi-volume archive, choose **Open With → Zipchik**.

If macOS blocks this preview build, Control-click the application in Finder and choose **Open**, then confirm. This is caused by the missing notarization; it does not require disabling system protection globally.

## What it does

- Finder Quick Look: lists archive contents, lets you select files, and extracts them to a chosen folder.
- Hidden helper app: appears only when an archive is explicitly opened with Zipchik; it handles passwords, multi-volume sets, cancellation, and selective extraction through bundled `7zz`.
- No archive creation, no document-type lookup, and no online requests.
- Does not make itself the default application for archive types.

## Supported archives

Quick Look is verified in Finder for ZIP, 7z, RAR5, and `.tar.gz`. It also declares GZIP, BZIP2, XZ, Zstandard, ISO, CAB, CPIO, XAR, ARJ, and LHA/LZH where supported by the system libarchive.

The helper uses 7-Zip 26.02 for password-protected and multi-volume archives. ZIP, 7z, TAR, GZIP, BZIP2, XZ, RAR, and common variants are in scope. The current version is Apple Silicon only.

## Security boundaries

- Zipchik never extracts paths outside the chosen destination.
- Existing files are not overwritten by default.
- Quick Look extracts only ordinary files and rejects traversal paths, symlinks, and hard links.
- Passwords live only in memory. 7zz receives a password briefly as a child-process argument and Zipchik does not log it.

## Build from source

```sh
swift test
/bin/zsh Tools/build-xcode-app.sh Release
/bin/zsh Tools/create-dmg.sh Release/ZIP.app Release/Zipchik-0.2.2-arm64.dmg
```

The build machine needs Xcode, XcodeGen, Homebrew 7-Zip at `/opt/homebrew/opt/sevenzip/bin/7zz`, and Apple Silicon.

## Third-party components

The app ships the unmodified 7-Zip `7zz` executable under LGPL-2.1-or-later with its included notices. Quick Look links the macOS system libarchive; it does not ship a separate libarchive copy. See [NOTICE.md](NOTICE.md), `Resources/7-Zip-license.txt`, and `Resources/libarchive-license.txt`.

## License

Zipchik source code is available under the [MIT License](LICENSE). Third-party components retain their own licenses.
