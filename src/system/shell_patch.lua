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

  local wallpaper = [[local function drawWallpaper()
ui.fill(display, 1, 1, W, H, core.theme.desktopTop)
if H < 8 then return end
local middle = math.max(4, math.floor(H * 0.43))
local lower = math.max(middle + 2, math.floor(H * 0.68))
ui.fill(display, 1, middle, W, H - middle + 1, core.theme.desktopMid)
ui.fill(display, 1, lower, W, H - lower + 1, core.theme.desktopBottom)
if display.depth >= 4 then
ui.fill(display, 1, middle, W, 1, 0x1a4d67)
ui.fill(display, 1, lower, W, 1, core.theme.desktopLine)
end
end]]

  local menubar = [[local function drawMenubar()
ui.fill(display, 1, 1, W, 1, core.theme.menubar)
ui.fill(display, 1, 1, 8, 1, core.theme.accent)
ui.text(display, 2, 1, "idk os", core.theme.lightText, core.theme.accent)
local focused = core.focused and core.tasks[core.focused]
local appName = focused and focused.name or "finder"
if W >= 18 then ui.text(display, 10, 1, unicode.sub(appName, 1, 18), core.theme.menubarText, core.theme.menubar) end
local status = "up " .. uptimeText() .. "  mem " .. tostring(memoryPercent()) .. "%"
if unicode.len(status) + 2 < W then
ui.text(display, W - unicode.len(status), 1, status, core.theme.muted, core.theme.menubar)
end
end]]

  local dock = [[local function drawDock()
local height = dockHeight()
core.dockButtons = {}
if height == 1 then
ui.fill(display, 1, H, W, 1, core.theme.dockDark)
ui.button(display, 2, H, 8, "apps", core.menu, core.theme.accent, core.theme.dockDark)
core.dockButtons[1] = {x = 2, y = H, w = 8, h = 1, kind = "launchpad"}
return
end
local slots = dockSlots()
local slotWidth = 7
local maxSlots = math.max(1, math.floor((W - 8) / slotWidth))
while #slots > maxSlots do table.remove(slots) end
local dockWidth = #slots * slotWidth + 4
local dockX = math.max(1, math.floor((W - dockWidth) / 2) + 1)
local glassY, middleY, baseY = H - 2, H - 1, H
local iconY = H - 4
ui.fill(display, dockX + 2, glassY, dockWidth - 4, 1, core.theme.dockGlass)
ui.fill(display, dockX + 1, middleY, dockWidth - 2, 1, core.theme.dockMid)
ui.fill(display, dockX, baseY, dockWidth, 1, core.theme.dockBase)
local slotX = dockX + 2
for _, slot in ipairs(slots) do
local focused = slot.pid and core.focused == slot.pid
local drawY = focused and math.max(2, iconY - 1) or iconY
if focused then ui.fill(display, slotX, drawY + 2, 6, 1, 0x6ea7ca) end
local iconName = slot.kind == "launchpad" and "startbutton" or slot.icon
ui.image(display, slotX, drawY, ui.icon(iconName, slot.color, "dock"))
if slot.running then display.cell(slotX + 2, H, " ", 0xffffff, 0xffffff) end
core.dockButtons[#core.dockButtons + 1] = {
x = slotX, y = math.max(1, drawY), w = 6, h = math.min(H - drawY + 1, 5),
kind = slot.kind, id = slot.id, pid = slot.pid
}
slotX = slotX + slotWidth
end
end]]

  local ok
  source, ok = replaceFunction(source, "drawWallpaper", "drawMenubar", wallpaper)
  if not ok then return nil, "could not patch wallpaper" end
  source, ok = replaceFunction(source, "drawMenubar", "drawDesktopShortcut", menubar)
  if not ok then return nil, "could not patch menu bar" end
  source, ok = replaceFunction(source, "drawDock", "drawWindow", dock)
  if not ok then return nil, "could not patch dock" end

  source = source:gsub(
    'display.cell%(x %+ 1, y, "o", 0xffffff, core.theme.danger%)',
    'display.cell(x + 1, y, " ", core.theme.danger, core.theme.danger)', 1
  )
  source = source:gsub(
    'display.cell%(x %+ 3, y, "o", core.theme.text, core.theme.warning%)',
    'display.cell(x + 3, y, " ", core.theme.warning, core.theme.warning)', 1
  )
  source = source:gsub(
    'display.cell%(x %+ 5, y, "o", 0xffffff, core.theme.success%)',
    'display.cell(x + 5, y, " ", core.theme.success, core.theme.success)', 1
  )

  return source
end

return patch
