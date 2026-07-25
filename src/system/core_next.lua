local component = require("component")
local computer = require("computer")
local event = require("event")
local filesystem = require("filesystem")
local keyboard = require("keyboard")
local unicode = require("unicode")
local ui = dofile("/idkos/system/ui_next.lua")
local core = {
apps = {}, tasks = {}, windows = {}, nextPid = 100,
running = true, focused = nil, dragging = nil, dirty = true,
menu = false, menuPage = 1,
theme = {
desktopTop = 0x0f2c42, desktopMid = 0x16445e, desktopBottom = 0x1b5870,
desktopLine = 0x2a6a80, menubar = 0xedf3f7, menubarLine = 0xb8c8d4,
menubarText = 0x21384a, panel = 0xf4f7fa, panelSoft = 0xe8eef3,
panelDark = 0xc9d4dd, window = 0xf8fafc, windowAlt = 0xf0f4f7,
titleActive = 0xe6edf3, titleInactive = 0xcbd5dd, border = 0x91a5b5,
accent = 0x3188c9, accentSoft = 0xb9ddf5, text = 0x1c2f3e,
muted = 0x64798a, lightText = 0xffffff, danger = 0xe45b67,
warning = 0xf1b94e, success = 0x51b77a, shadow = 0x071822,
dockGlass = 0xd9e8f2, dockMid = 0x8ca4b5, dockBase = 0x3e5568,
dockDark = 0x203646, card = 0x224f68, overlay = 0x0b2334,
selection = 0xb9ddf5, selectionText = 0x173247
}
}
local gpu = component.gpu
if not gpu then error("primary gpu is unavailable", 0) end
local resolutionOk, oldW, oldH = pcall(gpu.getResolution)
if not resolutionOk then error("gpu resolution is unavailable: " .. tostring(oldW), 0) end
local foregroundOk, oldFg, oldFgPalette = pcall(gpu.getForeground)
local backgroundOk, oldBg, oldBgPalette = pcall(gpu.getBackground)
local depthOk, oldDepth = pcall(gpu.getDepth)
local W, H, display
local function dockHeight()
if not H then return 1 end
if H >= 19 then return 5 end
if H >= 15 then return 4 end
return 1
end
local function workspaceBottom()
return math.max(2, H - dockHeight())
end
local function primaryScreen()
local ok, screen = pcall(gpu.getScreen)
return ok and screen or nil
end
local function sortedWindows()
local out = {}
for _, win in pairs(core.windows) do out[#out + 1] = win end
table.sort(out, function(a, b) return a.z < b.z end)
return out
end
function core.restore()
pcall(gpu.setResolution, oldW, oldH)
if depthOk then pcall(gpu.setDepth, oldDepth) end
if foregroundOk then pcall(gpu.setForeground, oldFg, oldFgPalette) end
if backgroundOk then pcall(gpu.setBackground, oldBg, oldBgPalette) end
pcall(gpu.fill, 1, 1, oldW, oldH, " ")
end
function core.scanApps()
core.apps = {}
for _, root in ipairs({"/idkos/apps", "/home/Apps"}) do
if filesystem.exists(root) then
local iterator = filesystem.list(root)
for name in iterator or function() end do
name = tostring(name):gsub("/$", "")
if name:sub(-4) == ".app" then
local path = filesystem.concat(root, name)
local manifestPath = filesystem.concat(path, "manifest.lua")
if filesystem.exists(manifestPath) then
local ok, manifest = pcall(dofile, manifestPath)
if ok and type(manifest) == "table" and type(manifest.id) == "string" then
manifest.path = path
manifest.name = manifest.name or manifest.id
manifest.entry = manifest.entry or "main.lua"
manifest.icon = type(manifest.icon) == "string" and manifest.icon or manifest.id
if type(manifest.color) ~= "number" then manifest.color = nil end
core.apps[manifest.id] = manifest
end
end
end
end
end
end
end
local Window = {}
Window.__index = Window
function Window:clear(bg)
self.bg = bg or self.bg
self.dirty = true
end
function Window:text(x, y, text, fg, bg)
self.draws[#self.draws + 1] = {kind = "text", x = x, y = y, text = tostring(text), fg = fg, bg = bg}
self.dirty = true
end
function Window:fill(x, y, w, h, bg, char)
self.draws[#self.draws + 1] = {kind = "fill", x = x, y = y, w = w, h = h, bg = bg, char = char}
self.dirty = true
end
function Window:icon(x, y, name, color, size)
self.draws[#self.draws + 1] = {kind = "icon", x = x, y = y, name = name, color = color, size = size}
self.dirty = true
end
function Window:button(id, x, y, w, label, active)
self.buttons[id] = {x = x, y = y, w = w, h = 1, label = label, active = active and true or false, hidden = false}
self.dirty = true
end
function Window:hit(id, x, y, w, h)
self.buttons[id] = {x = x, y = y, w = w, h = h or 1, hidden = true}
self.dirty = true
end
function Window:reset()
self.draws, self.buttons, self.canvasCells = {}, {}, 0
self.dirty = true
end
function Window:size()
return self.width, math.max(0, self.height - 1)
end
function Window:canvas(x, y, width, height, cells)
x, y = math.floor(tonumber(x) or 1), math.floor(tonumber(y) or 1)
width, height = math.floor(tonumber(width) or 0), math.floor(tonumber(height) or 0)
if type(cells) ~= "table" or type(cells.backgrounds) ~= "table" then return nil, "invalid canvas" end
local maxWidth, maxHeight = math.max(0, self.width - x + 1), math.max(0, self.height - y)
width, height = math.min(math.max(0, width), maxWidth), math.min(math.max(0, height), maxHeight)
local count = width * height
if x < 1 or y < 1 or count < 1 or count > 4096 or self.canvasCells + count > 4096 then
return nil, "canvas exceeds window bounds"
end
local backgrounds, foregrounds, glyphs = {}, {}, {}
for i = 1, count do
local bg = tonumber(cells.backgrounds[i])
backgrounds[i] = (bg and bg >= 0 and bg <= 0xffffff) and bg or 0x000000
local fg = cells.foregrounds and tonumber(cells.foregrounds[i])
foregrounds[i] = (fg and fg >= 0 and fg <= 0xffffff) and fg or nil
local glyph = cells.glyphs and cells.glyphs[i]
if glyph ~= nil then glyphs[i] = unicode.sub(tostring(glyph), 1, 1) end
end
self.draws[#self.draws + 1] = {
kind = "canvas", x = x, y = y, w = width, h = height,
backgrounds = backgrounds, foregrounds = foregrounds, glyphs = glyphs
}
self.canvasCells = self.canvasCells + count
self.dirty = true
return true
end
function Window:close()
core.closeTask(self.pid)
end
local function fitWindows()
for _, win in pairs(core.windows) do
if win.maximized then
win.x, win.y, win.width, win.height = 1, 2, W, math.max(1, workspaceBottom() - 1)
else
win.width = ui.clip(win.width, math.min(26, math.max(1, W - 2)), math.max(1, W - 2))
win.height = ui.clip(win.height, math.min(8, math.max(1, workspaceBottom() - 1)), math.max(1, workspaceBottom() - 1))
win.x = ui.clip(win.x, 1, math.max(1, W - win.width + 1))
win.y = ui.clip(win.y, 2, math.max(2, workspaceBottom() - win.height + 1))
end
win.dirty = true
end
end
local function toggleMaximize(win)
if win.maximized then
if win.restoreGeometry then win.x, win.y, win.width, win.height = table.unpack(win.restoreGeometry) end
win.maximized, win.restoreGeometry = false, nil
else
win.restoreGeometry = {win.x, win.y, win.width, win.height}
win.x, win.y, win.width, win.height = 1, 2, W, math.max(1, workspaceBottom() - 1)
win.maximized = true
end
fitWindows()
core.dirty = true
end
local function useResolution(width, height, setGpu)
local maxOk, maxW, maxH = pcall(gpu.maxResolution)
if not maxOk then return nil, maxW end
width = ui.clip(math.floor(tonumber(width) or 1), 1, maxW)
height = ui.clip(math.floor(tonumber(height) or 1), 1, maxH)
if setGpu then
local ok, changed, reason = pcall(gpu.setResolution, width, height)
if not ok or changed == false then return nil, reason or changed end
end
local ok, actualW, actualH = pcall(gpu.getResolution)
if not ok then return nil, actualW end
local renderOk, newDisplay = pcall(ui.renderer, gpu, actualW, actualH)
if not renderOk then return nil, newDisplay end
W, H, display = actualW, actualH, newDisplay
fitWindows()
core.dirty = true
return true
end
function core.setDisplay(mode)
local ok, maxW, maxH = pcall(gpu.maxResolution)
if not ok then return nil, maxW end
local limits = {compact = {60, 20}, balanced = {80, 25}}
if mode == "native" or mode == "maximum" then
local freeOk, freeMemory = pcall(computer.freeMemory)
local totalOk, totalMemory = pcall(computer.totalMemory)
local safe, required = ui.memorySafe(maxW, maxH, freeOk and freeMemory, totalOk and totalMemory)
if not safe then return nil, "native mode needs " .. tostring(required or "more") .. " bytes" end
return useResolution(maxW, maxH, true)
end
local size = limits[mode]
if not size then return nil, "unknown display mode" end
return useResolution(math.min(maxW, size[1]), math.min(maxH, size[2]), true)
end
function core.createWindow(pid, options)
options = options or {}
local width = ui.clip(options.width or 54, math.min(26, math.max(1, W - 2)), math.max(1, W - 2))
local height = ui.clip(options.height or 18, math.min(8, math.max(1, workspaceBottom() - 1)), math.max(1, workspaceBottom() - 1))
local count = 0
for _ in pairs(core.windows) do count = count + 1 end
local win = setmetatable({
pid = pid, title = options.title or "app",
x = options.x or (3 + (count * 3) % math.max(3, W - width - 3)),
y = options.y or (3 + (count * 2) % math.max(3, H - height - 4)),
width = width, height = height, bg = options.bg or core.theme.window,
draws = {}, buttons = {}, canvasCells = 0, z = computer.uptime(),
minimized = false, dirty = true
}, Window)
core.windows[pid] = win
fitWindows()
core.focused = pid
core.dirty = true
return win
end
local function appApi(task)
local api = {}
function api.window(options) return core.createWindow(task.pid, options) end
function api.pull(timeout) return coroutine.yield("pull", timeout) end
function api.sleep(seconds) return coroutine.yield("sleep", seconds or 0) end
function api.yield() return coroutine.yield("yield") end
function api.exit() return coroutine.yield("exit") end
function api.launch(id) return core.launch(id) end
function api.kill(pid) return core.closeTask(pid) end
function api.tasks() return core.tasks end
function api.apps() return core.apps end
function api.notify(text)
core.notification = {text = tostring(text), untilTime = computer.uptime() + 4}
core.dirty = true
end
function api.theme() return core.theme end
function api.screen() return W, H end
function api.focused()
local win = core.windows[task.pid]
return core.focused == task.pid and win and not win.minimized or false
end
function api.display(mode) return core.setDisplay(mode) end
function api.displays() return {primary = {screen = primaryScreen(), width = W, height = H}, mirrors = {}} end
function api.rescanApps() core.scanApps() core.dirty = true end
api.fs, api.component, api.computer = filesystem, component, computer
return api
end
function core.launch(id)
local manifest = core.apps[id]
if not manifest then return nil, "app not found: " .. tostring(id) end
local entryPath = filesystem.concat(manifest.path, manifest.entry)
local ok, entry = pcall(dofile, entryPath)
if not ok then return nil, entry end
if type(entry) ~= "function" then return nil, "app entry must return a function" end
local pid = core.nextPid
core.nextPid = pid + 1
local task = {
pid = pid, id = id, name = manifest.name, status = "starting",
wake = 0, queue = {}, started = computer.uptime(), cpu = 0
}
task.co = coroutine.create(function() return entry(appApi(task)) end)
core.tasks[pid] = task
core.focused = pid
core.dirty = true
return pid
end
function core.closeTask(pid)
core.tasks[pid] = nil
core.windows[pid] = nil
if core.focused == pid then
local wins = sortedWindows()
core.focused = wins[#wins] and wins[#wins].pid or nil
end
core.dirty = true
end
local function resumeTask(task, ...)
local before = computer.uptime()
local ok, action, arg = coroutine.resume(task.co, ...)
task.cpu = task.cpu + (computer.uptime() - before)
if not ok then
core.notification = {
text = task.name .. " crashed: " .. unicode.sub(tostring(action), 1, 46),
untilTime = computer.uptime() + 6
}
core.closeTask(task.pid)
return
end
if coroutine.status(task.co) == "dead" or action == "exit" then
core.closeTask(task.pid)
elseif action == "sleep" then
task.status, task.wake = "sleeping", computer.uptime() + (tonumber(arg) or 0)
elseif action == "pull" then
task.status, task.deadline = "waiting", arg and (computer.uptime() + arg) or nil
else
task.status = "ready"
end
end
local function send(pid, name, ...)
local task = core.tasks[pid]
if task then task.queue[#task.queue + 1] = {name, ...} end
end
local function dispatch(name, ...)
for _, task in pairs(core.tasks) do task.queue[#task.queue + 1] = {name, ...} end
end
local function scheduler()
local now = computer.uptime()
local snapshot = {}
for _, task in pairs(core.tasks) do snapshot[#snapshot + 1] = task end
for _, task in ipairs(snapshot) do
if core.tasks[task.pid] then
if task.status == "starting" or task.status == "ready" then
resumeTask(task)
elseif task.status == "sleeping" and now >= task.wake then
resumeTask(task)
elseif task.status == "waiting" then
local queued = table.remove(task.queue, 1)
if queued then
resumeTask(task, table.unpack(queued))
elseif task.deadline and now >= task.deadline then
resumeTask(task)
end
end
end
end
end
local function memoryPercent()
local freeOk, freeMemory = pcall(computer.freeMemory)
local totalOk, totalMemory = pcall(computer.totalMemory)
if not freeOk or not totalOk or not totalMemory or totalMemory <= 0 then return 0 end
return math.max(0, math.min(100, math.floor((1 - freeMemory / totalMemory) * 100)))
end
local function uptimeText()
local seconds = math.floor(computer.uptime())
local minutes = math.floor(seconds / 60)
local hours = math.floor(minutes / 60)
if hours > 0 then return string.format("%dh%02dm", hours, minutes % 60) end
return string.format("%dm", minutes)
end
local function drawWallpaper()
ui.fill(display, 1, 1, W, H, core.theme.desktopTop)
if H < 8 then return end
local mid = math.max(4, math.floor(H * 0.43))
ui.fill(display, 1, mid, W, H - mid + 1, core.theme.desktopMid)
local lower = math.max(mid + 2, math.floor(H * 0.68))
ui.fill(display, 1, lower, W, H - lower + 1, core.theme.desktopBottom)
if display.depth >= 4 then
local phase = math.floor(computer.uptime() * 2)
for x = 3, W - 2, 8 do
local y = 3 + ((x * 7 + phase) % math.max(2, mid - 3))
display.cell(x, y, (x + phase) % 3 == 0 and "+" or ".", 0x4e8296, core.theme.desktopTop)
end
for x = 1, W do
local wave = math.floor(math.sin((x + phase * 0.5) / 11) * 1.5)
local y = lower - 1 + wave
if y >= mid and y <= H then
display.cell(x, y, "~", core.theme.desktopLine, y >= lower and core.theme.desktopBottom or core.theme.desktopMid)
end
end
end
end
local function drawMenubar()
ui.fill(display, 1, 1, W, 1, core.theme.menubar)
ui.fill(display, 1, 1, 8, 1, core.theme.accent)
ui.text(display, 2, 1, "idk os", core.theme.lightText, core.theme.accent)
local focused = core.focused and core.tasks[core.focused]
local appName = focused and focused.name or "finder"
if W >= 18 then ui.text(display, 10, 1, unicode.sub(appName, 1, 14), core.theme.menubarText, core.theme.menubar) end
if W >= 68 then ui.text(display, 26, 1, "file  edit  view  window", core.theme.muted, core.theme.menubar) end
local status = "up " .. uptimeText() .. "  mem " .. tostring(memoryPercent()) .. "%"
if unicode.len(status) + 2 < W then
ui.text(display, W - unicode.len(status), 1, status, core.theme.muted, core.theme.menubar)
end
end
local function drawDesktopShortcut(id, x, y)
local manifest = core.apps[id]
if not manifest then return end
ui.fill(display, x + 1, y + 1, 7, 6, core.theme.shadow)
ui.fill(display, x, y, 7, 6, core.theme.card)
ui.image(display, x + 1, y, ui.icon(manifest.icon, manifest.color))
ui.center(display, x, y + 5, 7, unicode.sub(manifest.name, 1, 7), core.theme.lightText, core.theme.card)
core.desktopHits[#core.desktopHits + 1] = {x = x, y = y, w = 7, h = 6, id = id}
end
local function drawDesktop()
drawWallpaper()
drawMenubar()
core.desktopHits = {}
if W >= 52 and H >= 18 then
drawDesktopShortcut("files", W - 8, 3)
drawDesktopShortcut("store", W - 8, 10)
end
end
local pinned = {"files", "store", "terminal", "settings"}
local function firstTask(id)
local found
for _, task in pairs(core.tasks) do
if task.id == id and (not found or task.pid < found.pid) then found = task end
end
return found
end
local function dockSlots()
local slots = {{kind = "launchpad", id = "launchpad", name = "apps", icon = "launchpad"}}
local pinnedSet = {}
for _, id in ipairs(pinned) do
local manifest = core.apps[id]
if manifest then
pinnedSet[id] = true
local running = firstTask(id)
slots[#slots + 1] = {
kind = "app", id = id, pid = running and running.pid,
name = manifest.name, icon = manifest.icon, color = manifest.color,
running = running ~= nil
}
end
end
local tasks = {}
for _, task in pairs(core.tasks) do
if not pinnedSet[task.id] then tasks[#tasks + 1] = task end
end
table.sort(tasks, function(a, b) return a.pid < b.pid end)
for _, task in ipairs(tasks) do
local manifest = core.apps[task.id] or {}
slots[#slots + 1] = {
kind = "task", id = task.id, pid = task.pid, name = task.name,
icon = manifest.icon or task.id, color = manifest.color, running = true
}
end
return slots
end
local function drawDock()
local height = dockHeight()
core.dockButtons = {}
if height == 1 then
ui.fill(display, 1, H, W, 1, core.theme.dockDark)
ui.button(display, 2, H, 8, "apps", core.menu, core.theme.accent, core.theme.dockDark)
core.dockButtons[1] = {x = 2, y = H, w = 8, h = 1, kind = "launchpad"}
return
end
local slots = dockSlots()
local slotWidth = 5
local maxSlots = math.max(1, math.floor((W - 10) / slotWidth))
while #slots > maxSlots do table.remove(slots) end
local dockWidth = #slots * slotWidth + 6
local dockX = math.max(1, math.floor((W - dockWidth) / 2) + 1)
local shelfY = H - 1
local iconBaseY = H - 4
ui.fill(display, dockX + 3, shelfY - 2, dockWidth - 6, 1, core.theme.shadow)
ui.fill(display, dockX + 2, shelfY - 1, dockWidth - 4, 1, core.theme.dockGlass)
ui.fill(display, dockX + 1, shelfY, dockWidth - 2, 1, core.theme.dockMid)
ui.fill(display, dockX, H, dockWidth, 1, core.theme.dockBase)
display.cell(dockX, shelfY, "/", 0xe9f2f8, core.theme.dockMid)
display.cell(dockX + dockWidth - 1, shelfY, "\\", 0xe9f2f8, core.theme.dockMid)
local slotX = dockX + 3
for index, slot in ipairs(slots) do
local focused = slot.pid and core.focused == slot.pid
local iconY = focused and math.max(2, iconBaseY - 1) or iconBaseY
if focused then
ui.fill(display, slotX - 1, iconY + 2, 5, 1, 0x6ea7ca)
end
ui.image(display, slotX, iconY, ui.icon(slot.icon, slot.color, "dock"))
if slot.running then display.cell(slotX + 1, H, ".", 0xffffff, core.theme.dockBase) end
if index == 1 and #slots > 1 then display.cell(slotX + 3, shelfY, "|", 0x60798b, core.theme.dockMid) end
core.dockButtons[#core.dockButtons + 1] = {
x = slotX - 1, y = math.max(1, iconY), w = 5, h = math.min(H - iconY + 1, 5),
kind = slot.kind, id = slot.id, pid = slot.pid
}
slotX = slotX + slotWidth
end
end
local function drawWindow(win)
if win.minimized then return end
local x, y, w, h = win.x, win.y, win.width, win.height
local focused = core.focused == win.pid
if x + w <= W then ui.fill(display, x + w, y + 1, 1, math.min(h, H - y), core.theme.shadow) end
if y + h <= workspaceBottom() then ui.fill(display, x + 1, y + h, math.min(w, W - x), 1, core.theme.shadow) end
ui.fill(display, x, y, w, h, win.bg)
ui.fill(display, x, y, w, 1, focused and core.theme.titleActive or core.theme.titleInactive)
display.cell(x + 1, y, "o", 0xffffff, core.theme.danger)
display.cell(x + 3, y, "o", core.theme.text, core.theme.warning)
display.cell(x + 5, y, "o", 0xffffff, core.theme.success)
if w >= 12 then
ui.center(
display, x + 7, y, w - 8,
unicode.sub(win.title, 1, math.max(1, w - 10)),
focused and core.theme.text or core.theme.muted,
focused and core.theme.titleActive or core.theme.titleInactive
)
end
display.pushClip(x, y + 1, w, math.max(0, h - 1))
for _, draw in ipairs(win.draws) do
local dx, dy = x + draw.x - 1, y + draw.y
if draw.kind == "text" and draw.y >= 1 and draw.y < h then
ui.text(display, dx, dy, unicode.sub(draw.text, 1, math.max(0, w - draw.x + 1)), draw.fg or core.theme.text, draw.bg or win.bg)
elseif draw.kind == "fill" and draw.y < h and draw.y + draw.h > 0 then
ui.fill(
display, dx, math.max(y + 1, dy), math.min(draw.w, w - draw.x + 1),
math.min(draw.h, y + h - 1 - math.max(y + 1, dy)), draw.bg or win.bg, draw.char
)
elseif draw.kind == "icon" and draw.y >= 1 and draw.y < h then
ui.image(display, dx, dy, ui.icon(draw.name, draw.color, draw.size))
elseif draw.kind == "canvas" then
for py = 1, draw.h do
for px = 1, draw.w do
local i = (py - 1) * draw.w + px
display.cell(
dx + px - 1, dy + py - 1, draw.glyphs[i] or " ",
draw.foregrounds[i] or (draw.glyphs[i] and 0xffffff) or draw.backgrounds[i],
draw.backgrounds[i]
)
end
end
end
end
for _, button in pairs(win.buttons) do
if not button.hidden and button.y >= 1 and button.y < h and button.x <= w then
ui.button(
display, x + button.x - 1, y + button.y,
math.min(button.w, w - button.x + 1), button.label, button.active
)
end
end
display.popClip()
end
local function menuApps()
local apps = {}
for _, manifest in pairs(core.apps) do apps[#apps + 1] = manifest end
table.sort(apps, function(a, b) return a.name:lower() < b.name:lower() end)
return apps
end
local function drawMenu()
if not core.menu then return end
local apps = menuApps()
local bottom = workspaceBottom()
ui.fill(display, 1, 2, W, math.max(1, bottom - 1), core.theme.overlay)
local columns = math.max(2, math.min(6, math.floor((W - 8) / 11)))
local rows = math.max(1, math.floor((bottom - 5) / 7))
local perPage = math.max(1, columns * rows)
local pages = math.max(1, math.ceil(#apps / perPage))
core.menuPage = math.max(1, math.min(core.menuPage, pages))
local start = (core.menuPage - 1) * perPage + 1
local finish = math.min(#apps, start + perPage - 1)
core.menuHits = {}
core.menuBox = {x = 1, y = 2, w = W, h = math.max(1, bottom - 1)}
ui.center(display, 1, 3, W, "applications", 0xffffff, core.theme.overlay)
if W >= 30 then
ui.center(display, 1, 4, W, string.format("page %d of %d", core.menuPage, pages), 0x9fc0d2, core.theme.overlay)
end
local gridWidth = columns * 11
local gridX = math.max(1, math.floor((W - gridWidth) / 2) + 1)
for index = start, finish do
local relative = index - start
local column = relative % columns
local row = math.floor(relative / columns)
local x = gridX + column * 11
local y = 6 + row * 7
local manifest = apps[index]
ui.fill(display, x + 1, y + 1, 9, 5, 0x102d40)
ui.image(display, x + 3, y, ui.icon(manifest.icon, manifest.color))
ui.center(display, x, y + 5, 10, unicode.sub(manifest.name, 1, 10), 0xffffff, core.theme.overlay)
core.menuHits[#core.menuHits + 1] = {x = x, y = y, w = 10, h = 6, kind = "app", id = manifest.id}
end
if pages > 1 then
local navY = bottom - 1
ui.text(display, 3, navY, "< previous", core.menuPage > 1 and 0xffffff or 0x536c7c, core.theme.overlay)
ui.text(display, W - 10, navY, "next >", core.menuPage < pages and 0xffffff or 0x536c7c, core.theme.overlay)
core.menuHits[#core.menuHits + 1] = {x = 2, y = navY, w = 12, h = 1, kind = "previous"}
core.menuHits[#core.menuHits + 1] = {x = W - 12, y = navY, w = 12, h = 1, kind = "next"}
end
end
local function drawNotification()
if not core.notification or computer.uptime() >= core.notification.untilTime then return end
local text = unicode.sub(core.notification.text, 1, math.max(1, W - 16))
local width = math.min(W - 2, unicode.len(text) + 6)
local x = math.max(1, W - width)
ui.fill(display, x + 1, 3, width, 3, core.theme.shadow)
ui.fill(display, x, 2, width, 3, core.theme.panel)
ui.fill(display, x, 2, 2, 3, core.theme.accent)
ui.text(display, x + 3, 3, text, core.theme.text, core.theme.panel)
end
local function redraw()
display.beginFrame()
drawDesktop()
for _, win in ipairs(sortedWindows()) do drawWindow(win) end
drawMenu()
drawDock()
drawNotification()
display.flush()
core.dirty = false
for _, win in pairs(core.windows) do win.dirty = false end
end
local function acceptedScreen(screen)
return not screen or screen == primaryScreen()
end
local function focusOrLaunch(button)
if button.kind == "launchpad" then
core.menu = not core.menu
core.menuPage = 1
core.dirty = true
return
end
if button.kind == "previous" then
core.menuPage = math.max(1, core.menuPage - 1)
core.dirty = true
return
end
if button.kind == "next" then
core.menuPage = core.menuPage + 1
core.dirty = true
return
end
if button.pid and core.windows[button.pid] then
local win = core.windows[button.pid]
win.minimized = false
win.z = computer.uptime()
core.focused = button.pid
core.menu = false
core.dirty = true
return
end
if button.id then
local pid, reason = core.launch(button.id)
if not pid then core.notification = {text = tostring(reason), untilTime = computer.uptime() + 5} end
core.menu = false
core.dirty = true
end
end
local function handleTouch(_, screen, x, y, button, player)
if not acceptedScreen(screen) then return end
if y == 1 and x <= 8 then
core.menu = not core.menu
core.menuPage = 1
core.dirty = true
return
end
for _, item in ipairs(core.dockButtons or {}) do
if ui.inside(x, y, item.x, item.y, item.w, item.h) then focusOrLaunch(item) return end
end
if core.menu then
for _, item in ipairs(core.menuHits or {}) do
if ui.inside(x, y, item.x, item.y, item.w, item.h) then focusOrLaunch(item) return end
end
core.menu = false
core.dirty = true
return
end
local wins = sortedWindows()
for index = #wins, 1, -1 do
local win = wins[index]
if not win.minimized and ui.inside(x, y, win.x, win.y, win.width, win.height) then
core.focused = win.pid
win.z = computer.uptime()
core.dirty = true
if y == win.y and x == win.x + 1 then core.closeTask(win.pid) return end
if y == win.y and x == win.x + 3 then win.minimized = true core.dirty = true return end
if y == win.y and x == win.x + 5 then toggleMaximize(win) return end
if y == win.y then
core.dragging = {pid = win.pid, dx = x - win.x, dy = y - win.y}
return
end
for id, hit in pairs(win.buttons) do
if ui.inside(x, y, win.x + hit.x - 1, win.y + hit.y, hit.w, hit.h) then
send(win.pid, "idk_button", win.pid, id, player)
return
end
end
send(win.pid, "touch", screen, x - win.x + 1, y - win.y, button, player)
return
end
end
for _, item in ipairs(core.desktopHits or {}) do
if ui.inside(x, y, item.x, item.y, item.w, item.h) then focusOrLaunch(item) return end
end
end
local function handleDrag(_, screen, x, y)
if not acceptedScreen(screen) or not core.dragging then return end
local win = core.windows[core.dragging.pid]
if win then
win.x = ui.clip(x - core.dragging.dx, 1, math.max(1, W - win.width + 1))
win.y = ui.clip(y - core.dragging.dy, 2, math.max(2, workspaceBottom() - win.height + 1))
core.dirty = true
end
end
function core.run()
local depthSet, maxDepth = pcall(gpu.maxDepth)
if depthSet and type(maxDepth) == "number" then pcall(gpu.setDepth, math.min(maxDepth, 8)) end
local maxOk, maxW, maxH = pcall(gpu.maxResolution)
if not maxOk then error("gpu limits unavailable: " .. tostring(maxW)) end
local freeOk, freeMemory = pcall(computer.freeMemory)
local totalOk, totalMemory = pcall(computer.totalMemory)
local mode = ui.startupDisplayMode(maxW, maxH, freeOk and freeMemory, totalOk and totalMemory)
local resized, reason = core.setDisplay(mode)
if not resized and mode ~= "balanced" then resized, reason = core.setDisplay("balanced") end
if not resized then resized, reason = core.setDisplay("compact") end
if not resized then error("could not configure display: " .. tostring(reason)) end
core.scanApps()
local pid, launchReason = core.launch("files")
if not pid then core.notification = {text = tostring(launchReason), untilTime = computer.uptime() + 8} end
local lastDraw = 0
while core.running do
scheduler()
local now = computer.uptime()
local dirty = core.dirty
if not dirty then
for _, win in pairs(core.windows) do
if win.dirty then dirty = true break end
end
end
if dirty or now - lastDraw >= 0.35 then
redraw()
lastDraw = now
end
local incoming = {event.pull(0.05)}
if incoming[1] then
if incoming[1] == "touch" then
handleTouch(table.unpack(incoming))
elseif incoming[1] == "drag" then
handleDrag(table.unpack(incoming))
elseif incoming[1] == "drop" then
core.dragging = nil
elseif incoming[1] == "screen_resized" and acceptedScreen(incoming[2]) then
useResolution(incoming[3], incoming[4], false)
elseif incoming[1] == "key_down" and incoming[4] == 16 and keyboard.isControlDown() then
core.running = false
elseif (incoming[1] == "key_down" or incoming[1] == "key_up" or incoming[1] == "clipboard") and core.focused then
send(core.focused, table.unpack(incoming))
else
dispatch(table.unpack(incoming))
end
end
end
end
return core
