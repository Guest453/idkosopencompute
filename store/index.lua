return {
  {
    id="notes", name="notes", version="1.1.0", author="idk os",
    category="productivity", icon="notes", color=0x5d8ed6,
    description="a tiny keyboard-driven notepad",
    details="capture plain-text lines locally with staged, recoverable saves.",
    path="store/apps/notes.app",
    files={"manifest.lua","main.lua"}
  },
  {
    id="timer", name="clock & timer", version="1.0.0", author="idk os",
    category="utilities", icon="timer", color=0x7d65c1,
    description="clock and countdown timer",
    details="a low-overhead uptime clock and configurable countdown.",
    path="store/apps/timer.app",
    files={"manifest.lua","main.lua"}
  },
  {
    id="todo", name="todo list", version="1.0.0", author="idk os",
    category="productivity", icon="todo", color=0x35a870,
    description="persistent task list",
    details="track up to one hundred local tasks with completion state.",
    path="store/apps/todo.app",
    files={"manifest.lua","main.lua"}
  },
  {
    id="diskusage", name="disk usage", version="1.0.0", author="idk os",
    category="system", icon="diskusage", color=0x377fa8,
    description="filesystem capacity inspector",
    details="inspect used and available capacity across mounted filesystems.",
    path="store/apps/diskusage.app",
    files={"manifest.lua","main.lua"}
  },
  {
    id="calendar", name="calendar", version="1.0.0", author="idk os",
    category="productivity", icon="calendar", color=0xd85b62,
    description="lightweight month calendar",
    details="browse a deterministic gregorian calendar without background work.",
    path="store/apps/calendar.app",
    files={"manifest.lua","main.lua"}
  },
  {
    id="components", name="component browser", version="1.0.0", author="idk os",
    category="system", icon="components", color=0x4c6f87,
    description="inspect connected hardware components",
    details="list component addresses, types, and exported method names safely.",
    path="store/apps/components.app",
    files={"manifest.lua","main.lua"}
  },
  {
    id="inferno", name="inferno: bfs1h demo", version="2.0.0", author="idk os / SuyaSS",
    category="games", icon="game", color=0xd05a3a,
    description="a two-minute transformed MAP01 raycaster demo",
    details="rasterizes SuyaSS's CC BY 4.0 BFS1H map geometry; no Doom IWAD assets.",
    path="store/apps/inferno.app",
    package="inferno-bfs1h-map01-demo",
    files={"manifest.lua","main.lua","BFS1H.wad","LICENSE-BFS1H.txt"}
  }
}
