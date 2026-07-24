return {
  {
    id="notes", name="notes", version="1.1.0", author="idk os",
    category="productivity", icon="notes", color=0x5d8ed6,
    description="a tiny keyboard-driven notepad",
    details="capture plain-text lines locally with staged, recoverable saves.",
    path="store/apps/notes.app", files={"manifest.lua","main.lua"}
  },
  {
    id="timer", name="clock & timer", version="1.0.0", author="idk os",
    category="utilities", icon="timer", color=0x7d65c1,
    description="clock and countdown timer",
    details="a low-overhead uptime clock and configurable countdown.",
    path="store/apps/timer.app", files={"manifest.lua","main.lua"}
  },
  {
    id="todo", name="todo list", version="1.0.0", author="idk os",
    category="productivity", icon="todo", color=0x35a870,
    description="persistent task list",
    details="track up to one hundred local tasks with completion state.",
    path="store/apps/todo.app", files={"manifest.lua","main.lua"}
  },
  {
    id="diskusage", name="disk usage", version="1.0.0", author="idk os",
    category="system", icon="diskusage", color=0x377fa8,
    description="filesystem capacity inspector",
    details="inspect used and available capacity across mounted filesystems.",
    path="store/apps/diskusage.app", files={"manifest.lua","main.lua"}
  },
  {
    id="calendar", name="calendar", version="1.0.0", author="idk os",
    category="productivity", icon="calendar", color=0xd85b62,
    description="lightweight month calendar",
    details="browse a deterministic gregorian calendar without background work.",
    path="store/apps/calendar.app", files={"manifest.lua","main.lua"}
  },
  {
    id="components", name="component browser", version="1.0.0", author="idk os",
    category="system", icon="components", color=0x4c6f87,
    description="inspect connected hardware components",
    details="list component addresses, types, and exported method names safely.",
    path="store/apps/components.app", files={"manifest.lua","main.lua"}
  },
  {
    id="recoveryupdater", name="recovery updater", version="1.0.1", author="idk os",
    category="system", icon="recoveryupdater", color=0x397fca,
    description="reboot into a ram-resident full-system updater",
    details="uses component.invoke-compatible networking, stages every official image file, updates /init.lua last, and rolls back failed writes.",
    path="store/apps/recoveryupdater.app", package="idkos-recovery-updater",
    files={"manifest.lua","main.lua","bridge.lua","updater.lua"}
  },
  {
    id="blockmerge", name="block merge", version="1.0.0", author="idk os",
    category="games", icon="blockmerge", color=0xf4c95d,
    description="a compact 2048-style number merging game",
    details="combine matching blocks with arrow keys or touch controls and chase a new high score.",
    path="store/apps/blockmerge.app", package="block-merge-original",
    files={"manifest.lua","main.lua"}
  },
  {
    id="lightsout", name="lights out", version="1.0.0", author="idk os",
    category="games", icon="lightsout", color=0xffd84d,
    description="turn every light off in as few moves as possible",
    details="a compact touch puzzle with randomized, always-reachable boards.",
    path="store/apps/lightsout.app", package="lights-out-original",
    files={"manifest.lua","main.lua"}
  },
  {
    id="inferno", name="inferno: transformed wad geometry", version="2.2.0", author="idk os / SuyaSS",
    category="games", icon="inferno", color=0xd05a3a,
    description="a transformed BFS1H MAP01 geometry demo",
    details="parses and rasterizes map geometry for custom raycaster gameplay; not Doom or full WAD semantics.",
    path="store/apps/inferno.app", package="inferno-bfs1h-map01-demo",
    files={"manifest.lua","main.lua","BFS1H.wad","LICENSE-BFS1H.txt"}
  },
  {
    id="chicken3d", name="chicken run 3d", version="1.0.0", author="idk os",
    category="games", icon="chicken3d", color=0x66a84f,
    description="catch wandering chickens in a genuine low-poly 3d arena",
    details="perspective triangles, near-plane clipping, a depth buffer, adaptive resolution, and a timed eight-chicken challenge.",
    path="store/apps/chicken3d.app", package="chicken3d-original", files={"manifest.lua","main.lua"}
  },
  {
    id="snake", name="garden snake", version="1.0.0", author="idk os",
    category="games", icon="snake", color=0x55d98b,
    description="a responsive wrap-free arcade snake game",
    details="grow through a compact garden with accelerating rounds, keyboard and directional touch steering.",
    path="store/apps/snake.app", package="garden-snake-original", files={"manifest.lua","main.lua"}
  },
  {
    id="pong", name="neon pong", version="1.0.0", author="idk os",
    category="games", icon="pong", color=0x65c8ff,
    description="adaptive single-player neon pong",
    details="race the cpu to seven with angle-sensitive rebounds, keyboard controls, and direct touch positioning.",
    path="store/apps/pong.app", package="neon-pong-original", files={"manifest.lua","main.lua"}
  },
  {
    id="minesweeper", name="pocket mines", version="1.0.0", author="idk os",
    category="games", icon="minesweeper", color=0x9aabc0,
    description="a polished compact minesweeper board",
    details="first-move-safe minesweeper with flood reveal, flags, scoring, keyboard, and direct touch controls.",
    path="store/apps/minesweeper.app", package="pocket-mines-original", files={"manifest.lua","main.lua"}
  },
  {
    id="breakout", name="prism breakout", version="1.0.0", author="idk os",
    category="games", icon="breakout", color=0x55c8ff,
    description="a bright adaptive brick-breaking game",
    details="clear three waves with keyboard or touch paddle control, scoring, lives, and bounded physics.",
    path="store/apps/breakout.app", package="prism-breakout-original", files={"manifest.lua","main.lua"}
  },
  {
    id="spamtontrash", name="SPAMTON TRASH", version="1.0.0", author="idk os",
    category="art", icon="spamtontrash", color=0xff4db8,
    description="an original native-pixel puppet portrait",
    details="displays a black-backed half-cell portrait with mismatched lenses, angular pose, and no gameplay.",
    path="store/apps/spamtontrash.app", package="spamton-trash-native-art",
    files={"manifest.lua","main.lua"}
  }
}
