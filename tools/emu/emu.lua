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
function computer.uptime() return clock end
function computer.freeMemory() return 1.6 * 1024 * 1024 end
function computer.totalMemory() return 2 * 1024 * 1024 end
function computer.beep() end
function computer.address() return "emu-computer" end
function computer.pushSignal() end
function computer.shutdown() error("shutdown", 0) end

---------------------------------------------------------------------------- gpu
local MAXW, MAXH, MAXDEPTH = 160, 50, 8
local gpu = {address = "emu-gpu", type = "gpu"}
local screenAddr = "emu-screen"
local W, H, DEPTH = 80, 25, MAXDEPTH
local chars, fgs, bgs = {}, {}, {}
local curFg, curBg = 0xffffff, 0x000000
local touched = 0

local function clear()
  for i = 1, W * H do chars[i], fgs[i], bgs[i] = " ", 0xffffff, 0x000000 end
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
function gpu.setForeground(c) local o = curFg curFg = c return o, false end
function gpu.setBackground(c) local o = curBg curBg = c return o, false end
function gpu.set(x, y, value)
  x, y = math.floor(x), math.floor(y)
  if y < 1 or y > H then return false end
  local n = unicode.len(value)
  for i = 1, n do
    local px = x + i - 1
    if px >= 1 and px <= W then
      local idx = (y - 1) * W + px
      chars[idx], fgs[idx], bgs[idx] = unicode.sub(value, i, i), curFg, curBg
      touched = touched + 1
    end
  end
  return true
end
function gpu.fill(x, y, w, h, ch)
  x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
  for py = math.max(1, y), math.min(H, y + h - 1) do
    for px = math.max(1, x), math.min(W, x + w - 1) do
      local idx = (py - 1) * W + px
      chars[idx], fgs[idx], bgs[idx] = ch, curFg, curBg
      touched = touched + 1
    end
  end
  return true
end
function gpu.copy() return true end
function gpu.getPaletteColor(i) return i end
function gpu.setPaletteColor(i, v) return v end

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
  for y = 1, H do
    local row = {}
    for x = 1, W do
      local i = (y - 1) * W + x
      row[#row + 1] = string.format("%06x,%06x,%s", fgs[i] or 0xffffff, bgs[i] or 0, chars[i] or " ")
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

local ok, err = pcall(core.run)
if not ok then io.stderr:write("core.run: " .. tostring(err) .. "\n") end
io.stderr:write("frames: " .. #shots .. "\n")
