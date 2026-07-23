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
erasure begins. the final prompt requires `erase <full-target-address>` exactly;
there is no default disk. the volatile temporary filesystem is identified and
cannot be selected because it cannot boot after a restart.

before entering the ram ui, the installer downloads the complete image into ram,
syntax-checks every lua payload, and validates the image manifest. from the ram
transition onward, raw gpu and keyboard signals provide the interface and disk
selection has no default. disk discovery, current root/boot and temporary-disk
labels, writable and capacity checks, full-address confirmation, erasure, writing,
read-back verification, firmware boot-address update, and reboot use only captured
ram data plus raw component, computer, and selected filesystem APIs. openos `io`,
paths, packages, internet, and shell services are never used in this phase. no
target change occurs until every payload is resident in ram and the exact
`erase <full-target-address>` confirmation succeeds.

the installed disk boots directly through its root `/init.lua`. that bootstrap
loads `/idkos/system/runtime.lua`, which supplies the filesystem, io, event,
keyboard, unicode, component, computer, internet, require, loadfile, and dofile
interfaces used by the desktop and bundled apps. paths are rooted on the selected
boot filesystem; no openos libraries or shell remain. the terminal app is a
small built-in system console rather than an openos command shell.

the source-to-image mapping is declared in `image.lua`; `/init.lua` and every
runtime, desktop, and built-in app dependency are explicit entries.

maintainers can run `node tools/validate-image.js` with the `luaparse` module
available. it parses every lua source as lua 5.3, checks duplicate and unsafe
image paths, verifies required boot files, and ensures every `src` lua file is
present in the image.

## desktop

the desktop is a lightweight cell gui with a top panel, polished app cards, layered windows, larger touch targets, focus styling, and a centered adaptive icon dock. its original compact cell-art format uses transparent seven-by-five images with a per-icon palette; dock icons resample to five-by-three cells. files, store, terminal, settings, calculator, system information, task manager, notes, timer, todo, disk usage, calendar, and component browser all have distinct multi-color artwork. unknown package names receive deterministic generated artwork, and low-depth screens map artwork to a safe two-tone form.

the wallpaper combines half-cell gradient waves, a drifting orb, and sparse stars at four frames per second on suitable color displays. animation falls back to a static composition on compact, low-depth, or non-semi-pixel screens. the compositor keeps flat background, foreground, and character planes, clips all image and window content, and groups adjacent changed cells with matching colors into gpu writes. unchanged cells are not resent. compact, balanced, and native/max modes remain available in settings, with safe fallback to the current resolution if a mode is rejected. built-in apps include files, calculator, terminal shortcuts, settings, task manager, app store, and system information.

the app store provides browse and category views, package details, installed/version status, updates, retry feedback, and confirmed uninstall. downloads have strict paths, file counts, per-file limits, and a 4 mib package limit. packages may contain `.lua`, `.wad`, and `.txt` files with strict flat filenames; only lua is syntax checked, while wad headers, directories, lump bounds, and counts are validated before any staged activation. declared package identity and files are matched against the manifest. an existing version is backed up, the exact activated app is verified after rescanning, and failures restore the backup. uninstall is recursively bounded to the selected package below `/home/Apps` and never removes built-ins.

the downloadable catalog contains seven lightweight apps across productivity, utilities, system, and games categories: notes, todo, clock & timer, disk usage, calendar, component browser, and the inferno bfs1h demo. downloadable apps remain catalog-only and are not included in the standalone installer image.

inferno is a two-minute transformed demo of `MAP01` from **Beginner's First Speedmap (1 Hour)** (`BFS1H.wad`) by SuyaSS, released 22 May 2022 under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). the official [idgames zip](https://www.gamers.org/pub/idgames/levels/doom2/Ports/a-c/bfs1h.zip) and [metadata](https://www.gamers.org/pub/idgames/levels/doom2/Ports/a-c/bfs1h.txt) identify the single Boom-format map. the 32,635-byte (31.87 kib) wad has sha-256 `fc17fdc406cd7e7c9647b4fba9a6084051153ff39345b644986e1a5aa33510ac`.

at startup, idk os safely parses the map's things, linedefs, and vertices, then scales and rasterizes one-sided and impassable geometry into a bounded raycasting and collision grid. gameplay uses a bounded transformed subset of map things and a reachable generated exit; it does not reproduce Doom's engine, textures, sounds, music, graphics, or other assets. no Doom IWAD is included or required. every reset starts a strict 120-second deadline, after which the demo ends and can be restarted. attribution and the indication of these changes are installed with the package in `LICENSE-BFS1H.txt`.

## app packages

apps are directories ending in `.app`:

```text
hello.app/
  manifest.lua
  main.lua
```

`manifest.lua` returns metadata and `main.lua` returns the app entry function. manifests may optionally provide an icon name in `icon` and a 24-bit numeric `color`; packages without either receive deterministic generated cell art. store entries additionally accept sanitized `category`, `description`, `details`, `author`, icon, and color metadata while older entries can omit optional fields. the extension is only a package marker; the actual code remains normal lua.

apps run as managed coroutines. they should call `app.pull`, `app.sleep`, or `app.yield` regularly so the desktop and task manager remain responsive.
