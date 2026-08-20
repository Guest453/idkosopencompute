-- emu.lua - a small opencomputers host for running idk os off the source tree.
-- it provides the component/computer/event/filesystem/keyboard/unicode modules
-- core.lua requires, a deterministic virtual clock, a text-cell gpu that records
-- frames, and a scripted input driver. it is a development harness only.
--
--   lua tools/emu/emu.lua tools/emu/scripts/<script>.lua [outdir]

local repo = os.getenv("IDKOS_REPO") or "."
local scriptPath = arg[1] or error("usage: emu.lua <script.lua> [outdir]")
local outDir = arg[2] or "emu-out"
os.execute("mkdir -p '" .. outDir .. "'")

--------------------------------------------------------------------- virtual fs
-- virtual disk layout -> source tree. the installer writes exactly these paths.
local mounts = {
  {"/idkos/system/", repo .. "/src/system/"},
  {"/idkos/apps/",   repo .. "/src/apps/"},
  {"/home/Apps/",    repo .. "/store/apps/"},
  {"/idkos/",        repo .. "/src/"},
}

local function real(path)
  path = tostring(path)
  for _, m in ipairs(mounts) do
    if path:sub(1, #m[1]) == m[1] then return m[2] .. path:sub(#m[1] + 1) end
  end
  if path == "/idkos/apps" then return repo .. "/src/apps" end
  if path == "/home/Apps" then return repo .. "/store/apps" end
  return repo .. "/emu-root" .. path
end

local function isDir(p)
  local ok = os.execute("test -d '" .. p .. "'")
  return ok == true or ok == 0
end
local function isFile(p)
  local f = io.open(p, "rb")
  if f then f:close() return true end
  return false
end

local filesystem = {}
function filesystem.concat(a, b, ...)
  local out = tostring(a):gsub("/+$", "") .. "/" .. tostring(b):gsub("^/+", "")
  if ... then return filesystem.concat(out, ...) end
  return out
end
function filesystem.exists(p)
  local r = real(p)
  return isFile(r) or isDir(r)
end
function filesystem.isDirectory(p) return isDir(real(p)) end
function filesystem.list(p)
  local r = real(p)
  if not isDir(r) then return nil end
  local names = {}
  local pipe = io.popen("ls -1 '" .. r .. "' 2>/dev/null")
  for line in pipe:lines() do
    names[#names + 1] = isDir(r .. "/" .. line) and (line .. "/") or line
  end
  pipe:close()
  local i = 0
  return function() i = i + 1 return names[i] end
end
function filesystem.open(p, mode) return io.open(real(p), mode or "r") end

-- io.open / dofile / loadfile take virtual paths inside the os and its apps.
local nativeOpen = io.open
io.open = function(path, mode)
  if type(path) == "string" and path:sub(1, 1) == "/" then return nativeOpen(real(path), mode) end
  return nativeOpen(path, mode)
end
local nativeLoadfile = loadfile
loadfile = function(path, ...)
  if type(path) == "string" and path:sub(1, 1) == "/" then return nativeLoadfile(real(path), ...) end
  return nativeLoadfile(path, ...)
end
dofile = function(path, ...)
  local chunk, err = loadfile(path)
  if not chunk then error(err, 0) end
  return chunk(...)
end

------------------------------------------------------------------------ unicode
local unicode = {}
function unicode.len(s) return utf8.len(tostring(s)) or #tostring(s) end
function unicode.char(...) return utf8.char(...) end
function unicode.sub(s, i, j)
  s = tostring(s)
  local n = utf8.len(s)
  if not n then return s:sub(i, j) end
  if i < 0 then i = n + i + 1 end
  if j == nil then j = n elseif j < 0 then j = n + j + 1 end
  if i < 1 then i = 1 end
  if j > n then j = n end
  if i > j then return "" end
  local a = utf8.offset(s, i)
  local b = utf8.offset(s, j + 1)
  return s:sub(a, (b or (#s + 1)) - 1)
end
function unicode.wlen(s) return unicode.len(s) end
function unicode.isWide() return false end
function unicode.charWidth() return 1 end

----------------------------------------------------------------------- computer
local clock = 0
local computer = {}
-- stock: two tier 3.5 sticks at 1024 KB, scaled 1.8 for the 64 bit vm.
-- forked: two 1 GB sticks, scale 1.0.
local FORK_RAM = os.getenv("IDKOS_FORK") ~= nil
local TOTAL_MEMORY = FORK_RAM and (2048 * 1024 * 1024) or math.floor(2 * 1024 * 1024 * 1.8)
function computer.uptime() return clock end
function computer.freeMemory() return math.floor(TOTAL_MEMORY * 0.8) end
function computer.totalMemory() return TOTAL_MEMORY end
function computer.beep() end
function computer.address() return "emu-computer" end
function computer.pushSignal() end
function computer.shutdown() error("shutdown", 0) end

---------------------------------------------------------------------------- gpu
-- the gpu models opencomputers 1.8: page 0 is the screen, higher indices are
-- video ram pages.  it also charges each call the same budget the real
-- GraphicsCard.scala charges, so a script can report what a frame would really
-- cost on a tier 3 card -- writes to a vram page are free, only the screen and
-- the bitblt that pushes a page to it are billed.
-- IDKOS_FORK=1 models the forked mod: bigger tier 3 screen, eight times cheaper
-- gpu calls, far higher call budget and a nearly free bitblt.
local FORK = os.getenv("IDKOS_FORK") ~= nil
local MAXW, MAXH, MAXDEPTH = 160, 50, 8
if FORK then MAXW, MAXH = 320, 100 end
local gpu = {address = "emu-gpu", type = "gpu"}
local screenAddr = "emu-screen"
local W, H, DEPTH = 80, 25, MAXDEPTH
local TIER = 2                                  -- zero based, so a tier 3 card

-- GraphicsCard.scala
local div = FORK and 8 or 1
local setCosts = {1 / (64 * div), 1 / (128 * div), 1 / (256 * div)}
local fillCosts = {1 / (32 * div), 1 / (64 * div), 1 / (128 * div)}
local copyCosts = {1 / (16 * div), 1 / (32 * div), 1 / (64 * div)}
local colorCosts = {1 / (32 * div), 1 / (64 * div), 1 / (128 * div)}
local BITBLT_BASE = FORK and 0.05 or 0.5        -- Settings gpu.bitbltCost
local CALL_BUDGET = FORK and 32.0 or 1.5        -- Settings computer.callBudgets[3]

local budgetSpent = 0
local function charge(cost) budgetSpent = budgetSpent + cost end

local pages = {}
local active = 0

local function page(i)
  if i == 0 then return pages[0] end
  return pages[i]
end

local function newPage(w, h)
  local p = {w = w, h = h, chars = {}, fgs = {}, bgs = {}, dirty = false}
  for k = 1, w * h do p.chars[k], p.fgs[k], p.bgs[k] = " ", 0xffffff, 0x000000 end
  return p
end

local curFg, curBg = 0xffffff, 0x000000

local function clear()
  pages[0] = newPage(W, H)
end
clear()

function gpu.getScreen() return screenAddr end
function gpu.bind(a) screenAddr = a return true end
function gpu.maxResolution() return MAXW, MAXH end
function gpu.getResolution() return W, H end
function gpu.setResolution(w, h)
  w, h = math.floor(w), math.floor(h)
  if w < 1 or h < 1 or w > MAXW or h > MAXH then return false end
  W, H = w, h clear() return true
end
function gpu.maxDepth() return MAXDEPTH end
function gpu.getDepth() return DEPTH end
function gpu.setDepth(d) DEPTH = d return true end
function gpu.getForeground() return curFg, false end
function gpu.getBackground() return curBg, false end
function gpu.setForeground(c)
  local o = curFg curFg = c
  if active == 0 then charge(colorCosts[TIER + 1]) end
  return o, false
end
function gpu.setBackground(c)
  local o = curBg curBg = c
  if active == 0 then charge(colorCosts[TIER + 1]) end
  return o, false
end

function gpu.set(x, y, value)
  local p = page(active)
  if not p then return false end
  x, y = math.floor(x), math.floor(y)
  if y < 1 or y > p.h then return false end
  local n = unicode.len(value)
  for i = 1, n do
    local px = x + i - 1
    if px >= 1 and px <= p.w then
      local idx = (y - 1) * p.w + px
      p.chars[idx], p.fgs[idx], p.bgs[idx] = unicode.sub(value, i, i), curFg, curBg
    end
  end
  p.dirty = true
  if active == 0 then charge(setCosts[TIER + 1]) end
  return true
end

function gpu.fill(x, y, w, h, ch)
  local p = page(active)
  if not p then return false end
  x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
  for py = math.max(1, y), math.min(p.h, y + h - 1) do
    for px = math.max(1, x), math.min(p.w, x + w - 1) do
      local idx = (py - 1) * p.w + px
      p.chars[idx], p.fgs[idx], p.bgs[idx] = ch, curFg, curBg
    end
  end
  p.dirty = true
  if active == 0 then charge(fillCosts[TIER + 1]) end
  return true
end

function gpu.copy(x, y, w, h, tx, ty)
  if active == 0 then charge(copyCosts[TIER + 1]) end
  return true
end

function gpu.getPaletteColor(i) return i end
function gpu.setPaletteColor(i, v) return v end

-- video ram pages
function gpu.totalMemory() return MAXW * MAXH * 3 end
function gpu.freeMemory()
  local used = 0
  for i, p in pairs(pages) do if i ~= 0 then used = used + p.w * p.h end end
  return gpu.totalMemory() - used
end
function gpu.allocateBuffer(w, h)
  w = math.floor(w or W) h = math.floor(h or H)
  if w < 1 or h < 1 then return nil, "invalid size" end
  if w * h > gpu.freeMemory() then return nil, "not enough video memory" end
  local i = 1
  while pages[i] do i = i + 1 end
  pages[i] = newPage(w, h)
  return i
end
function gpu.freeBuffer(i)
  if i == 0 or not pages[i] then return false end
  pages[i] = nil
  if active == i then active = 0 end
  return true
end
function gpu.freeAllBuffers()
  local n = 0
  for i in pairs(pages) do if i ~= 0 then pages[i] = nil n = n + 1 end end
  active = 0
  return n
end
function gpu.getActiveBuffer() return active end
function gpu.setActiveBuffer(i)
  i = math.floor(i or 0)
  if i ~= 0 and not pages[i] then return nil, "invalid buffer" end
  local old = active
  active = i
  return old
end
function gpu.getBufferSize(i)
  local p = page(i)
  if not p then return nil, "invalid buffer" end
  return p.w, p.h
end
function gpu.bitblt(dst, col, row, w, h, src, fromCol, fromRow)
  dst = math.floor(dst or 0)
  src = math.floor(src or active)
  local d, s = page(dst), page(src)
  if not d or not s then return nil, "invalid buffer" end
  col = math.floor(col or 1) row = math.floor(row or 1)
  w = math.floor(w or d.w) h = math.floor(h or d.h)
  fromCol = math.floor(fromCol or 1) fromRow = math.floor(fromRow or 1)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local sx, sy = fromCol + x, fromRow + y
      local dx, dy = col + x, row + y
      if sx >= 1 and sx <= s.w and sy >= 1 and sy <= s.h
         and dx >= 1 and dx <= d.w and dy >= 1 and dy <= d.h then
        local si = (sy - 1) * s.w + sx
        local di = (dy - 1) * d.w + dx
        d.chars[di], d.fgs[di], d.bgs[di] = s.chars[si], s.fgs[si], s.bgs[si]
      end
    end
  end
  -- determineBitbltBudgetCost: page -> screen costs by area, page -> page is free
  if dst == 0 and src ~= 0 then
    charge(s.dirty and (BITBLT_BASE * 2 ^ TIER * (s.w * s.h) / (MAXW * MAXH)) or 0.001)
    s.dirty = false
  end
  d.dirty = true
  return true
end

-- IDKOS_NO_VRAM hides the 1.8 page api, to compare against the old direct path
if os.getenv("IDKOS_NO_VRAM") then
  gpu.allocateBuffer, gpu.setActiveBuffer, gpu.bitblt = nil, nil, nil
  gpu.freeBuffer, gpu.freeAllBuffers, gpu.getActiveBuffer = nil, nil, nil
  gpu.getBufferSize, gpu.totalMemory, gpu.freeMemory = nil, nil, nil
end

-- budget reporting for scripts
function gpu.__budget() return budgetSpent, CALL_BUDGET end
function gpu.__resetBudget() budgetSpent = 0 end
function gpu.__buffers()
  local n = 0
  for i in pairs(pages) do if i ~= 0 then n = n + 1 end end
  return n
end

------------------------------------------------------------------- component api
local screen = {address = screenAddr, type = "screen"}
function screen.getAspectRatio() return 1, 1 end
function screen.setTouchModeInverted() end
function screen.getKeyboards() return {"emu-keyboard"} end

local components = {
  ["emu-gpu"] = {type = "gpu", proxy = gpu},
  ["emu-screen"] = {type = "screen", proxy = screen},
  ["emu-keyboard"] = {type = "keyboard", proxy = {address = "emu-keyboard", type = "keyboard"}},
}

local component = {}
component.gpu = gpu
component.screen = screen
function component.list(kind, exact)
  local found = {}
  for addr, c in pairs(components) do
    if not kind or (exact and c.type == kind) or (not exact and c.type:find(kind, 1, true)) then
      found[#found + 1] = addr
    end
  end
  table.sort(found)
  local i = 0
  return function() i = i + 1 return found[i], found[i] and components[found[i]].type end
end
function component.proxy(addr)
  local c = components[addr]
  return c and c.proxy or nil, c and nil or "no such component"
end
function component.type(addr) local c = components[addr] return c and c.type end
function component.invoke(addr, method, ...)
  local c = components[addr]
  return c.proxy[method](...)
end

local keyboard = {}
function keyboard.isControlDown() return false end
function keyboard.isShiftDown() return false end
function keyboard.isAltDown() return false end

--------------------------------------------------------------- scripted driver
local frames = {}
local shots = {}
local emu = {}
local driver

function emu.shot(name)
  coroutine.yield({shot = name})
end
function emu.key(char, code)
  coroutine.yield({event = {"key_down", "emu-keyboard", char or 0, code or 0, "emu"}})
  coroutine.yield({event = {"key_up", "emu-keyboard", char or 0, code or 0, "emu"}})
end
function emu.down(char, code)
  coroutine.yield({event = {"key_down", "emu-keyboard", char or 0, code or 0, "emu"}})
end
function emu.up(char, code)
  coroutine.yield({event = {"key_up", "emu-keyboard", char or 0, code or 0, "emu"}})
end
function emu.touch(x, y)
  coroutine.yield({event = {"touch", screenAddr, x, y, 0, "emu"}})
end
function emu.idle(n)
  for _ = 1, (n or 1) do coroutine.yield({}) end
end
function emu.quit() coroutine.yield({quit = true}) end
emu.repo = repo

local core -- set after load

local function dumpFrame(name)
  local out = {}
  out[#out + 1] = string.format("%d %d", W, H)
  local scr = pages[0]
  for y = 1, H do
    local row = {}
    for x = 1, W do
      local i = (y - 1) * W + x
      row[#row + 1] = string.format("%06x,%06x,%s", scr.fgs[i] or 0xffffff, scr.bgs[i] or 0, scr.chars[i] or " ")
    end
    out[#out + 1] = table.concat(row, "\t")
  end
  local f = assert(nativeOpen(outDir .. "/" .. name .. ".fb", "w"))
  f:write(table.concat(out, "\n"))
  f:close()
  shots[#shots + 1] = name
  io.stderr:write("shot: " .. name .. " (" .. W .. "x" .. H .. ")\n")
end

local pending = {}
local event = {}
function event.pull(timeout)
  clock = clock + (tonumber(timeout) or 0.05)
  if #pending > 0 then return table.unpack(table.remove(pending, 1)) end
  while true do
    local ok, res = coroutine.resume(driver)
    if not ok then
      io.stderr:write("driver error: " .. tostring(res) .. "\n")
      core.running = false
      return nil
    end
    if coroutine.status(driver) == "dead" then
      core.running = false
      return nil
    end
    res = res or {}
    if res.quit then core.running = false return nil end
    if res.shot then dumpFrame(res.shot)
    elseif res.event then return table.unpack(res.event)
    else return nil end
  end
end
function event.push(...) pending[#pending + 1] = {...} end

--------------------------------------------------------------------- module wiring
local modules = {
  component = component, computer = computer, event = event,
  filesystem = filesystem, keyboard = keyboard, unicode = unicode,
}
local nativeRequire = require
require = function(name)
  if modules[name] then return modules[name] end
  return nativeRequire(name)
end

_G.component, _G.computer, _G.unicode = component, computer, unicode

-- lua 5.2/5.3 compatibility shims the os assumes exist on opencomputers
if not loadstring then loadstring = load end
if not table.maxn then table.maxn = function(t) local n = 0 for k in pairs(t) do if type(k) == "number" and k > n then n = k end end return n end end

local scriptChunk = assert(nativeLoadfile(scriptPath))
driver = coroutine.create(function() scriptChunk(emu) end)

core = dofile("/idkos/system/core.lua")
_G.__core = core
emu.core = core

-- the driver needs the shot hook to see the composited screen, so expose it.
emu.dump = dumpFrame
emu.gpu = gpu

local ok, err = pcall(core.run)
if not ok then io.stderr:write("core.run: " .. tostring(err) .. "\n") end
io.stderr:write("frames: " .. #shots .. "\n")
