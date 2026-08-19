# Third-party notices

This repository does not contain Quasimorph or its assets.

The CLI downloads these pinned components from their linked release pages:

| Component | Version | Source | License |
|---|---:|---|---|
| Sikarugir wrapper template | 1.0.11 | [Sikarugir-App/Wrapper](https://github.com/Sikarugir-App/Wrapper/releases/tag/v1.0) | Publisher terms; not covered by this repository's MIT license |
| Whisky Wine runtime | 4.5.105-beta.1 (Wine 11.15) | [frankea/Whisky](https://github.com/frankea/Whisky/releases/tag/v4.5.105-beta.1) | Wine and bundled component licenses |
| DXVK-macOS | 1.10.3, included by the Whisky runtime | [Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) | zlib |
| 7-Zip | 26.02 | [ip7z/7zip](https://github.com/ip7z/7zip/releases/tag/26.02) | LGPL-2.1-or-later with unRAR restriction; BSD portions |
| Steam installer | Pinned 2026-08-05 download | [Valve](https://store.steampowered.com/about/) | Valve terms; downloaded only for Steam mode |

Exact URLs and SHA-256 values are recorded in [`Dependencies.lock.json`](Dependencies.lock.json).

Local mode copies a user's game files only into that user's local output. Steam mode lets Valve's client download the game after ownership verification. This project does not publish or provide license-bypass logic for the game.
