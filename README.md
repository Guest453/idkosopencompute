# idk os

a standalone graphical desktop and app platform for opencomputers. openos is only
used to launch the destructive installer.

## install

```sh
wget -f https://raw.githubusercontent.com/Guest453/idkosopencompute/main/install.lua /tmp/idkos-install.lua
/tmp/idkos-install.lua
```

the installer first downloads and validates the complete image in openos. it then
visibly transitions to the idk os ram installer running entirely
from ram. disks are discovered only after that transition, and the installer
reboots automatically after the selected image is fully verified.

**destructive warning:** the installer asks you to select a raw filesystem
component, then permanently erases every file on it. this can be the filesystem
currently booting and running openos. there is no backup and no rollback after
erasure begins. after showing the selected address again, the final prompt requires `erase` exactly;
there is no default disk. the volatile temporary filesystem is identified and
cannot be selected because it cannot boot after a restart.

before entering the ram ui, the installer downloads the complete image into ram,
syntax-checks every lua payload, and validates the image manifest. from the ram
transition onward, raw gpu and keyboard signals provide the interface and disk
selection has no default. disk discovery, current root/boot and temporary-disk
labels, writable and capacity checks, explicit `erase` confirmation, erasure, writing,
read-back verification, firmware boot-address update, and reboot use only captured
ram data plus raw component, computer, and selected filesystem APIs. openos `io`,
paths, packages, internet, and shell services are never used in this phase. no
target change occurs until every payload is resident in ram and the exact
`erase` confirmation succeeds.

the installed disk boots directly through its root `/init.lua`. that bootstrap
loads `/idkos/system/runtime.lua`, which supplies the filesystem, io, event,
keyboard, unicode, component, computer, internet, require, loadfile, and dofile
interfaces used by the desktop and bundled apps. paths are rooted on the selected
boot filesystem; no openos libraries or shell remain. the terminal app is a
small built-in system console rather than an openos command shell.

the source-to-image mapping is declared in `image.lua`; `/init.lua` and every
runtime, desktop, and built-in app dependency are explicit entries.

maintainers can run `node tools/validate-image.js` with the `luaparse` module
available. it parses every lua source as lua 5.2, checks duplicate and unsafe
image paths, verifies required boot files, and ensures every `src` lua file is
present in the image.

## desktop

the desktop is a lightweight cell gui with a top panel, polished app cards, layered windows, larger touch targets, focus styling, and a centered adaptive icon dock. its original native palette-row format stores eight-by-twelve logical-pixel artwork and combines each pair of vertical pixels with upper-half block glyphs into eight-by-six gpu cells. transparent logical pixels are composed against the current surface rather than painted as boxes. the dock uses adaptive five-by-six logical-pixel variants in five-by-three cells. files uses an original finder-inspired two-tone blue face with a vertical split, eyes, facial seam, and smile; every built-in and catalog app has distinct higher-detail artwork. unknown package names receive deterministic generated artwork, cache growth is bounded, clipping remains compositor-controlled, and low-depth screens map artwork to a safe two-tone form.

the wallpaper combines half-cell gradient waves, a drifting orb, and sparse stars at four frames per second on suitable color displays. animation falls back to a static composition on compact, low-depth, or non-semi-pixel screens. the compositor keeps flat background, foreground, and character planes, clips all image and window content, and groups adjacent changed cells with matching colors into gpu writes. unchanged cells are not resent. apps can submit a copied, packed background/optional foreground/glyph cell canvas as one bounded draw object; canvases are clipped to window content and limited to 4,096 cells per reset, and never expose the compositor's gpu. compact, balanced, and native/max modes remain available in settings, with safe fallback to the current resolution if a mode is rejected. built-in apps include files, calculator, terminal shortcuts, settings, task manager, app store, and system information.

opencomputers gpus cannot combine to accelerate one screen. idk os instead discovers up to three compatible secondary gpu/screen pairs and mirrors changed compositor runs to them. already-bound secondary pairs are retained; otherwise an unbound extra gpu may be paired only with an unused screen. a mirror must support the primary resolution and color depth. incompatible devices are skipped, and a mirror that fails while drawing is dropped without stopping the primary desktop. display-mode and relevant component changes rebuild the mirror set. touch, drag, and drop from active same-resolution mirror screens are accepted as normal desktop input. system information reports the active count explicitly as mirrored, not accelerated. desktop exit restores only the primary gpu's original mode and colors; unrelated gpu state is not restored or cleared.

the app store provides browse and category views, package details, installed/version status, updates, retry feedback, and confirmed uninstall. downloads have strict paths, file counts, per-file limits, and a 4 mib package limit. packages may contain `.lua`, `.wad`, and `.txt` files with strict flat filenames; only lua is syntax checked, while wad headers, directories, lump bounds, and counts are validated before any staged activation. declared package identity and files are matched against the manifest. an existing version is backed up, the exact activated app is verified after rescanning, and failures restore the backup. uninstall is recursively bounded to the selected package below `/home/Apps` and never removes built-ins.

the downloadable catalog contains thirteen apps across productivity, utilities, system, art, and games categories: notes, todo, clock & timer, disk usage, calendar, component browser, inferno: transformed wad geometry, chicken run 3d, garden snake, neon pong, pocket mines, prism breakout, and `SPAMTON TRASH`. downloadable apps remain catalog-only and are not included in the standalone installer image.

chicken run 3d is an original low-poly game rather than a raycaster. it transforms world-space triangle meshes through a perspective camera, clips polygons against a guarded near plane, corrects character-cell aspect ratio, fills projected triangles, and resolves visibility through a per-cell depth buffer. its adaptive canvas is capped at 56 by 22 cells (42 by 18 below 1 mib of memory) and approximately seven frames per second. the arena has ground, boundary fencing, obstacles, and five wandering box-built chickens with white bodies and heads, yellow beaks and legs, and red combs. use `w`/`s` or up/down to move, `a`/`d` or left/right to turn, and space or `e` to catch an aimed nearby chicken. bottom-screen touch regions turn, advance, and catch. catch eight in 75 seconds; space or touch restarts the summary. held movement is cleared whenever focus is lost.

garden snake uses wasd/arrows or a touch relative to the snake's head; collect stars without striking the border or yourself, then press or tap to restart. neon pong uses w/s or up/down, or direct vertical touch, and races an adaptive cpu to seven. pocket mines provides a first-move-safe 12-by-10 board, bounded flood reveal, keyboard cursor and flags, direct touch reveal, elapsed-time scoring, and restart states. prism breakout provides three adaptive brick waves, lives, score, bounded delta-time physics, keyboard steps, and direct touch paddle control. game loops use capped timed pulls, reset timing while unfocused, and use short rate-limited `computer.beep` cues instead of continuous sound work. the games use original code and generated cell visuals with no third-party game assets.

`SPAMTON TRASH` is an image app, not a game. it reconstructs the supplied visual idea as original 24-by-32 logical-pixel palette art: a black-backed white/gray puppet-like figure with an angular nose, pink and yellow lenses, red mouth, raised arms, dark suit details, and white shoes. a small reusable palette-row decoder converts pairs of logical rows directly to a bounded half-cell canvas. no png is bundled and no general png decoder was added: pure png decoding would require deflate and substantial code/memory overhead that is wasteful under the 4 mib package ceiling for one native image.

inferno is a two-minute transformed wad geometry demo based on `MAP01` from **Beginner's First Speedmap (1 Hour)** (`BFS1H.wad`) by SuyaSS, released 22 may 2022 under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). the official [idgames zip](https://www.gamers.org/pub/idgames/levels/doom2/Ports/a-c/bfs1h.zip) and [metadata](https://www.gamers.org/pub/idgames/levels/doom2/Ports/a-c/bfs1h.txt) identify the source map. the 32,635-byte (31.87 kib) wad has sha-256 `fc17fdc406cd7e7c9647b4fba9a6084051153ff39345b644986e1a5aa33510ac`.

at startup, inferno safely parses selected map structures, then scales and rasterizes one-sided and impassable geometry into a bounded collision grid for custom raycaster gameplay. it is not a doom player, does not run doom, and does not implement full wad or boom semantics. gameplay uses a transformed subset of map things and a generated reachable exit; it does not reproduce doom's engine, textures, sounds, music, graphics, or other assets. no doom iwad is included or required. every reset starts a strict 120-second deadline, after which the demo ends and can be restarted. the app keeps this limitation visible during play. attribution and the indication of changes are installed with the package in `LICENSE-BFS1H.txt`.

## app packages

apps are directories ending in `.app`:

```text
hello.app/
  manifest.lua
  main.lua
```

`manifest.lua` returns metadata and `main.lua` returns the app entry function. manifests may optionally provide an icon name in `icon` and a 24-bit numeric `color`; packages without either receive deterministic generated cell art. store entries additionally accept sanitized `category`, `description`, `details`, `author`, icon, and color metadata while older entries can omit optional fields. the extension is only a package marker; the actual code remains normal lua.

apps run as managed coroutines. they should call `app.pull`, `app.sleep`, or `app.yield` regularly so the desktop and task manager remain responsive.
