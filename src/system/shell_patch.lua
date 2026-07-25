local patch = {}

local function replaceFunction(source, name, nextName, replacement)
  local pattern = "local function " .. name .. "%b().-\nend\nlocal function " .. nextName
  local changed = 0
  source, changed = source:gsub(pattern, function()
    return replacement .. "\nlocal function " .. nextName
  end, 1)
  return source, changed == 1
end

function patch.apply(source)
  if type(source) ~= "string" then return nil, "shell source is unavailable" end

  local dockHeight = [[local function dockHeight()
if not H then return 1 end
if H >= 30 then return 8 end
if H >= 22 then return 7 end
if H >= 18 then return 6 end
return 1
end]]

  local wallpaper = [[local function mixChannel(a, b, amount)
return math.floor(a + (b - a) * amount + 0.5)
end
local function mixColor(a, b, amount)
amount = math.max(0, math.min(1, amount))
local ar, ag, ab = math.floor(a / 0x10000) % 0x100, math.floor(a / 0x100) % 0x100, a % 0x100
local br, bg, bb = math.floor(b / 0x10000) % 0x100, math.floor(b / 0x100) % 0x100, b % 0x100
return mixChannel(ar, br, amount) * 0x10000 + mixChannel(ag, bg, amount) * 0x100 + mixChannel(ab, bb, amount)
end
local function drawEllipse(cx, cy, rx, ry, color)
for semiY = math.max(3, cy - ry), math.min(H * 2, cy + ry) do
local dy = (semiY - cy) / math.max(1, ry)
local span = math.floor(rx * math.sqrt(math.max(0, 1 - dy * dy)))
if span > 0 then ui.pixelRect(display, math.max(1, cx - span), semiY, math.min(W, cx + span) - math.max(1, cx - span) + 1, 1, color) end
end
end
local function drawWallpaper()
local first = 3
local last = H * 2
local top = 0x071a2d
local middle = 0x123a55
local bottom = 0x263f70
for semiY = first, last do
local amount = (semiY - first) / math.max(1, last - first)
local color = amount < 0.62 and mixColor(top, middle, amount / 0.62) or mixColor(middle, bottom, (amount - 0.62) / 0.38)
ui.pixelRect(display, 1, semiY, W, 1, color)
end
if display.depth >= 4 and H >= 18 then
drawEllipse(math.floor(W * 0.18), math.floor(H * 0.76), math.floor(W * 0.34), math.floor(H * 0.28), 0x184f69)
drawEllipse(math.floor(W * 0.18), math.floor(H * 0.76), math.floor(W * 0.26), math.floor(H * 0.21), 0x1d6678)
drawEllipse(math.floor(W * 0.84), math.floor(H * 1.18), math.floor(W * 0.38), math.floor(H * 0.34), 0x354b83)
drawEllipse(math.floor(W * 0.84), math.floor(H * 1.18), math.floor(W * 0.28), math.floor(H * 0.25), 0x405b92)
ui.pixelRect(display, 1, H * 2 - 1, W, 1, 0x5d79aa)
end
end]]

  local menubar = [[local function drawMenubar()
ui.fill(display, 1, 1, W, 1, 0x13243a)
ui.pixelRect(display, 1, 2, W, 1, 0x324a63)
ui.fill(display, 1, 1, 9, 1, 0x2f87bb)
ui.text(display, 2, 1, "idk os", 0xffffff, 0x2f87bb)
local focused = core.focused and core.tasks[core.focused]
local appName = focused and focused.name or "finder"
if W >= 20 then ui.text(display, 11, 1, unicode.sub(appName, 1, 20), 0xe7eef4, 0x13243a) end
local status = "up " .. uptimeText() .. "  mem " .. tostring(memoryPercent()) .. "%"
if unicode.len(status) + 2 < W then ui.text(display, W - unicode.len(status), 1, status, 0xaac0d0, 0x13243a) end
end]]

  local desktopShortcut = [[local function drawDesktopShortcut(id, x, y)
local manifest = core.apps[id]
if not manifest then return end
x = math.max(2, x - 7)
local icon = ui.icon(manifest.icon, manifest.color, "large")
ui.image(display, x + 1, y, icon)
ui.pixelRect(display, x + 1, (y + 6) * 2, 12, 1, 0x071522)
ui.fill(display, x, y + 6, 14, 1, 0x163047)
ui.center(display, x, y + 6, 14, unicode.sub(manifest.name, 1, 14), 0xf5f8fa, 0x163047)
core.desktopHits[#core.desktopHits + 1] = {x = x, y = y, w = 14, h = 7, id = id}
end]]

  local dock = [[local function drawDock()
local height = dockHeight()
core.dockButtons = {}
if height == 1 then
ui.fill(display, 1, H, W, 1, 0x1b2b3b)
ui.button(display, 2, H, 8, "apps", core.menu, core.theme.accent, 0x1b2b3b)
core.dockButtons[1] = {x = 2, y = H, w = 8, h = 1, kind = "launchpad"}
return
end
local slots = dockSlots()
local slotWidth = 13
local maxSlots = math.max(1, math.floor((W - 12) / slotWidth))
while #slots > maxSlots do table.remove(slots) end
local dockWidth = #slots * slotWidth + 6
local dockX = math.max(1, math.floor((W - dockWidth) / 2) + 1)
local bottom = H * 2
local top = bottom - 7
ui.pixelRect(display, dockX + 3, top - 2, dockWidth - 6, 1, 0x08131e)
ui.pixelRect(display, dockX + 2, top - 1, dockWidth - 4, 1, 0x526777)
ui.pixelRect(display, dockX + 1, top, dockWidth - 2, 1, 0xdde6ec)
ui.pixelRect(display, dockX, top + 1, dockWidth, 2, 0xa9bac5)
ui.pixelRect(display, dockX, top + 3, dockWidth, 2, 0x6c8090)
ui.pixelRect(display, dockX + 1, top + 5, dockWidth - 2, 2, 0x34495a)
local slotX = dockX + 3
local iconY = H - 7
for _, slot in ipairs(slots) do
local focused = slot.pid and core.focused == slot.pid
local drawY = focused and math.max(2, iconY - 1) or iconY
local iconName = slot.kind == "launchpad" and "startbutton" or slot.icon
if focused then ui.pixelRect(display, slotX, top - 3, 10, 1, 0x70c3e8) end
ui.image(display, slotX, drawY, ui.icon(iconName, slot.color, "dock"))
if slot.running then ui.pixelRect(display, slotX + 4, top - 1, 2, 1, 0xffffff) end
core.dockButtons[#core.dockButtons + 1] = {x = slotX, y = math.max(1, drawY), w = 10, h = math.min(H - drawY + 1, 7), kind = slot.kind, id = slot.id, pid = slot.pid}
slotX = slotX + slotWidth
end
end]]

  local window = [[local function drawWindow(win)
if win.minimized then return end
local x, y, w, h = win.x, win.y, win.width, win.height
local focused = core.focused == win.pid
if x + w <= W then ui.pixelRect(display, x + w, y * 2 + 1, 2, math.max(1, h * 2 - 1), 0x07131d) end
if y + h <= workspaceBottom() then ui.pixelRect(display, x + 1, (y + h) * 2 - 1, math.max(1, w), 2, 0x07131d) end
ui.fill(display, x, y, w, h, win.bg)
local titleColor = focused and 0xeaf0f4 or 0xd5dde3
ui.fill(display, x, y, w, 1, titleColor)
ui.pixelRect(display, x, y * 2 - 1, w, 1, 0xffffff)
ui.pixelRect(display, x, y * 2, w, 1, focused and 0x8ba6b8 or 0xaab7c0)
ui.pixelRect(display, x + 1, y * 2 - 1, 2, 2, core.theme.danger)
ui.pixelRect(display, x + 4, y * 2 - 1, 2, 2, core.theme.warning)
ui.pixelRect(display, x + 7, y * 2 - 1, 2, 2, core.theme.success)
if w >= 15 then ui.center(display, x + 10, y, w - 11, unicode.sub(win.title, 1, math.max(1, w - 13)), focused and core.theme.text or core.theme.muted, titleColor) end
display.pushClip(x, y + 1, w, math.max(0, h - 1))
for _, draw in ipairs(win.draws) do
local dx, dy = x + draw.x - 1, y + draw.y
if draw.kind == "text" and draw.y >= 1 and draw.y < h then
ui.text(display, dx, dy, unicode.sub(draw.text, 1, math.max(0, w - draw.x + 1)), draw.fg or core.theme.text, draw.bg or win.bg)
elseif draw.kind == "fill" and draw.y < h and draw.y + draw.h > 0 then
ui.fill(display, dx, math.max(y + 1, dy), math.min(draw.w, w - draw.x + 1), math.min(draw.h, y + h - 1 - math.max(y + 1, dy)), draw.bg or win.bg, draw.char)
elseif draw.kind == "icon" and draw.y >= 1 and draw.y < h then
ui.image(display, dx, dy, ui.icon(draw.name, draw.color, draw.size))
elseif draw.kind == "canvas" then
for py = 1, draw.h do
for px = 1, draw.w do
local i = (py - 1) * draw.w + px
display.cell(dx + px - 1, dy + py - 1, draw.glyphs[i] or " ", draw.foregrounds[i] or (draw.glyphs[i] and 0xffffff) or draw.backgrounds[i], draw.backgrounds[i])
end
end
end
end
for _, button in pairs(win.buttons) do
if not button.hidden and button.y >= 1 and button.y < h and button.x <= w then ui.button(display, x + button.x - 1, y + button.y, math.min(button.w, w - button.x + 1), button.label, button.active) end
end
display.popClip()
end]]

  local menu = [[local function drawMenu()
if not core.menu then return end
local apps = menuApps()
local bottom = workspaceBottom()
ui.fill(display, 1, 2, W, math.max(1, bottom - 1), 0x0b1928)
local columns = math.max(2, math.min(7, math.floor((W - 8) / 15)))
local rows = math.max(1, math.floor((bottom - 5) / 8))
local perPage = math.max(1, columns * rows)
local pages = math.max(1, math.ceil(#apps / perPage))
core.menuPage = math.max(1, math.min(core.menuPage, pages))
local start = (core.menuPage - 1) * perPage + 1
local finish = math.min(#apps, start + perPage - 1)
core.menuHits = {}
core.menuBox = {x = 1, y = 2, w = W, h = math.max(1, bottom - 1)}
ui.center(display, 1, 3, W, "applications", 0xffffff, 0x0b1928)
if W >= 30 then ui.center(display, 1, 4, W, string.format("page %d of %d", core.menuPage, pages), 0x86a7ba, 0x0b1928) end
local gridWidth = columns * 15
local gridX = math.max(1, math.floor((W - gridWidth) / 2) + 1)
for index = start, finish do
local relative = index - start
local column = relative % columns
local row = math.floor(relative / columns)
local x = gridX + column * 15
local y = 6 + row * 8
local manifest = apps[index]
ui.pixelRect(display, x + 1, y * 2, 12, 1, 0x28445a)
ui.pixelRect(display, x, y * 2 + 1, 14, 11, 0x132c40)
ui.image(display, x + 2, y, ui.icon(manifest.icon, manifest.color))
ui.center(display, x + 1, y + 5, 12, unicode.sub(manifest.name, 1, 12), 0xf4f8fb, 0x132c40)
core.menuHits[#core.menuHits + 1] = {x = x, y = y, w = 14, h = 7, kind = "app", id = manifest.id}
end
if pages > 1 then
local navY = bottom - 1
ui.text(display, 3, navY, "previous", core.menuPage > 1 and 0xffffff or 0x536c7c, 0x0b1928)
ui.text(display, W - 6, navY, "next", core.menuPage < pages and 0xffffff or 0x536c7c, 0x0b1928)
core.menuHits[#core.menuHits + 1] = {x = 2, y = navY, w = 10, h = 1, kind = "previous"}
core.menuHits[#core.menuHits + 1] = {x = W - 8, y = navY, w = 8, h = 1, kind = "next"}
end
end]]

  local notification = [[local function drawNotification()
if not core.notification or computer.uptime() >= core.notification.untilTime then return end
local text = unicode.sub(core.notification.text, 1, math.max(1, W - 16))
local width = math.min(W - 2, unicode.len(text) + 6)
local x = math.max(1, W - width)
ui.pixelRect(display, x + 1, 6, width, 5, 0x07131d)
ui.fill(display, x, 2, width, 3, 0xf0f4f7)
ui.pixelRect(display, x, 3, width, 1, 0xffffff)
ui.pixelRect(display, x, 4, 2, 4, 0x3188c9)
ui.text(display, x + 3, 3, text, 0x1c2f3e, 0xf0f4f7)
end]]

  local ok
  source, ok = replaceFunction(source, "dockHeight", "workspaceBottom", dockHeight)
  if not ok then return nil, "could not patch dock height" end
  source, ok = replaceFunction(source, "drawWallpaper", "drawMenubar", wallpaper)
  if not ok then return nil, "could not patch wallpaper" end
  source, ok = replaceFunction(source, "drawMenubar", "drawDesktopShortcut", menubar)
  if not ok then return nil, "could not patch menu bar" end
  source, ok = replaceFunction(source, "drawDesktopShortcut", "drawDesktop", desktopShortcut)
  if not ok then return nil, "could not patch desktop shortcuts" end
  source, ok = replaceFunction(source, "drawDock", "drawWindow", dock)
  if not ok then return nil, "could not patch dock" end
  source, ok = replaceFunction(source, "drawWindow", "menuApps", window)
  if not ok then return nil, "could not patch windows" end
  source, ok = replaceFunction(source, "drawMenu", "drawNotification", menu)
  if not ok then return nil, "could not patch app menu" end
  source, ok = replaceFunction(source, "drawNotification", "redraw", notification)
  if not ok then return nil, "could not patch notifications" end

  return source
end

return patch
