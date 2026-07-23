# idk os

a graphical desktop and app platform for opencomputers/openos.

## install

```sh
wget -f https://raw.githubusercontent.com/Guest453/idkosopencompute/main/install.lua /tmp/idkos-install.lua
/tmp/idkos-install.lua
```

then run `/idkos/boot.lua` or reboot.

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
