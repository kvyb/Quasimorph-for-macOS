# Third-party notices

This repository does not contain Quasimorph or its assets.

The CLI downloads these pinned components from their official publishers:

| Component | Version | Source | License |
|---|---:|---|---|
| Sikarugir wrapper template | 1.0.11 | [Sikarugir-App/Wrapper](https://github.com/Sikarugir-App/Wrapper/releases/tag/v1.0) | Publisher terms; not covered by this repository's MIT license |
| Sikarugir Wine engine | WS12WineSikarugir10.0_6 | [Sikarugir-App/Engines](https://github.com/Sikarugir-App/Engines/releases/tag/v1.0) | Wine and bundled component licenses |
| DXMT | 0.74, included by Sikarugir | [Sikarugir-App/dxmt](https://github.com/Sikarugir-App/dxmt) | LGPL-2.1 |
| 7-Zip | 26.02 | [ip7z/7zip](https://github.com/ip7z/7zip/releases/tag/26.02) | LGPL-2.1-or-later with unRAR restriction; BSD portions |

Exact URLs and SHA-256 values are recorded in [`Dependencies.lock.json`](Dependencies.lock.json).

The builder copies a user's local game files only into that user's local output. It does not download, modify, publish, or provide license-bypass logic for the game.
