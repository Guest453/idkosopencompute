# emu — an opencomputers host for idk os

`emu.lua` runs the real `src/system/core.lua` desktop on a desktop lua 5.4, so
apps can be developed and screenshotted without a minecraft world. it supplies
the `component` / `computer` / `event` / `filesystem` / `keyboard` / `unicode`
modules core.lua requires, a deterministic virtual clock, a 160x50 text-cell gpu
that records frames, and a scripted input driver. it is a development harness,
not an emulator of opencomputers' cpu limits — real hardware is much slower and
has far less memory.

```sh
IDKOS_REPO=. lua tools/emu/emu.lua tools/emu/scripts/srb2.lua out
python3 tools/emu/fb2png.py out/*.fb
```

a script receives the `emu` table: `emu.idle(n)`, `emu.key(char, code)`,
`emu.down` / `emu.up`, `emu.touch(x, y)`, `emu.shot(name)`, `emu.quit()`, and
`emu.core` for launching apps directly.

virtual disk paths map onto the source tree the way the installer lays them out:
`/idkos/system` -> `src/system`, `/idkos/apps` -> `src/apps`, `/home/Apps` ->
`store/apps`.
