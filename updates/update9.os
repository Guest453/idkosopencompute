return {
  format = "idk-os-update-1",
  version = 9,
  name = "update9.os",
  ref = "7711e97033dddbcc9139c7ec27919dcc9c897a12",
  channel = "main",
  notes = {
    "installer app: copy the running os onto a hard disk and boot from it",
    "app store reports real download errors instead of a bare nil",
    "filesystem failures without reasons get real messages",
    "native display capped at 720p (160x45)",
    "update staging moved to ram so floppy installs can update too"
  },
  files = {
    {source="src/system/version.lua", target="/idkos/version.lua"},
    {source="src/system/runtime.lua", target="/idkos/system/runtime.lua"},
    {source="src/system/core.lua", target="/idkos/system/core.lua"},
    {source="src/system/core_next.lua", target="/idkos/system/core_next.lua"},
    {source="src/system/shell_patch.lua", target="/idkos/system/shell_patch.lua"},
    {source="src/system/update_runner.lua", target="/idkos/system/update_runner.lua"},
    {source="src/apps/store.app/manifest.lua", target="/idkos/apps/store.app/manifest.lua"},
    {source="src/apps/store.app/main.lua", target="/idkos/apps/store.app/main.lua"},
    {source="src/apps/installer.app/manifest.lua", target="/idkos/apps/installer.app/manifest.lua"},
    {source="src/apps/installer.app/main.lua", target="/idkos/apps/installer.app/main.lua"}
  }
}
