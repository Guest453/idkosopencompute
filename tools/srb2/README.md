# srb2 asset tools

these rebuild the data files of `store/apps/srb2.app` from a local copy of
sonic robo blast 2. point `SRB2_DIR` at a directory holding the game's
`srb2.pk3`, `characters.pk3` and `zones.pk3` (default `/tmp/opencode/srb2/extracted`).

| tool | output | what it does |
| --- | --- | --- |
| `make_level.py` | `GFZ1.wad` | copies srb2's own MAP01 geometry lumps out of `zones.pk3` byte for byte, and resolves sidedefs and sector flats into small colour lumps by averaging the real textures and flats the map names. keeps the file under the app store's 256 KiB per-file limit. |
| `make_sprites.py` | `sprites.lua` | decodes the sprite lumps the map's objects use, translates sonic through the engine's SKINCOLOR_BLUE ramp, downsamples for the cell grid and re-quantises to PLAYPAL. one shared palette plus one byte per pixel. |
| `make_title.py` | `TITLE.wad` | the alacroix title screen `SOC_TITL` selects, frame by frame, at the size the cell grid can show. |

`srb2lib.py` holds the shared pk3 reader and a doom picture decoder that handles
the padding bytes around every post (getting that wrong is what garbles sprites).

none of these invent artwork: every pixel and every vertex comes from the game's
own files. the resulting package therefore contains sonic team junior's
copyrighted level and sprite data — check how you are allowed to redistribute it
before publishing the package anywhere.
