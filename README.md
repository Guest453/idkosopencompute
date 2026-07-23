# idk os

a standalone graphical desktop and app platform for opencomputers. openos is only
used to launch the destructive installer.

## install

```sh
wget -f https://raw.githubusercontent.com/Guest453/idkosopencompute/main/install.lua /tmp/idkos-install.lua
/tmp/idkos-install.lua
```

the installer reboots automatically after the selected image is fully verified.

**destructive warning:** the installer asks you to select a raw filesystem
component, then permanently erases every file on it. this can be the filesystem
currently booting and running openos. there is no backup and no rollback after
erasure begins. the final prompt requires `erase <full-target-address>` exactly;
there is no default disk. the volatile temporary filesystem is identified and
cannot be selected because it cannot boot after a restart.

before that final prompt, the installer downloads the complete image into ram,
syntax-checks every lua payload, validates the image manifest, checks target
capacity and read-only state, and makes no target changes. after confirmation it
uses only the ram-held raw filesystem proxy: it recursively wipes that component,
writes and reads back every image file, sets the label, sets the firmware boot
address, and reboots. no network or openos file is needed after erasure starts.

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

the macos-inspired text desktop has a top menu bar, centered task dock, familiar window controls, and a palette designed to remain readable at every gpu depth. it starts at the gpu's native maximum resolution when supported; compact, balanced, and native/max modes are available in settings, with safe fallback to the current resolution if a mode is rejected. rendering uses an in-memory frame diff so unchanged cells are not sent to the gpu. built-in apps include files, calculator, terminal shortcuts, settings, task manager, app store, and system information.

the app store catalog also offers lightweight downloadable apps. notes and todo use staged replacement writes for persistent data, while clock & timer and disk usage provide low-overhead utilities. downloadable catalog apps stay separate from the built-in installer payload.

## app packages

apps are directories ending in `.app`:

```text
hello.app/
  manifest.lua
  main.lua
  icon.lua       optional
```

`manifest.lua` returns metadata and `main.lua` returns the app entry function. the extension is only a package marker; the actual code remains normal lua.

apps run as managed coroutines. they should call `app.pull`, `app.sleep`, or `app.yield` regularly so the desktop and task manager remain responsive.
