return function(app)
local keyboard = require("keyboard")
local unicode = require("unicode")
local win = app.window{title = "finder", width = 76, height = 23}
local path = "/home"
local history = {path}
local historyIndex = 1
local selected, offset, status, confirmDelete = nil, 0, "ready", nil
local favorites = {
{name = "home", path = "/home", icon = "finder"},
{name = "applications", path = "/home/Apps", icon = "launchpad"},
{name = "system", path = "/idkos", icon = "settings"},
{name = "computer", path = "/", icon = "components"}
}
local function short(text, limit)
return unicode.sub(tostring(text or ""), 1, math.max(0, limit or 1))
end
local function cleanName(name)
return tostring(name or ""):gsub("/$", "")
end
local function humanSize(bytes)
bytes = tonumber(bytes) or 0
if bytes >= 1024 * 1024 then return string.format("%.1f mb", bytes / 1024 / 1024) end
if bytes >= 1024 then return string.format("%.1f kb", bytes / 1024) end
return tostring(bytes) .. " b"
end
local function hit(id, x, y, width, height, fallbackLabel)
if type(win.hit) == "function" then
win:hit(id, x, y, width, height or 1)
else
win:button(id, x, y, width, fallbackLabel or "open")
end
end
local function remember(nextPath)
if type(nextPath) ~= "string" or not app.fs.exists(nextPath) or not app.fs.isDirectory(nextPath) then
status = "folder is unavailable"
return false
end
path = nextPath
for index = #history, historyIndex + 1, -1 do history[index] = nil end
if history[historyIndex] ~= path then
history[#history + 1] = path
historyIndex = #history
end
selected, offset, confirmDelete = nil, 0, nil
status = "opened " .. path
return true
end
local function goHistory(delta)
local nextIndex = historyIndex + delta
if history[nextIndex] and app.fs.exists(history[nextIndex]) then
historyIndex = nextIndex
path = history[nextIndex]
selected, offset, confirmDelete = nil, 0, nil
status = delta < 0 and "back" or "forward"
end
end
local function entries()
local result = {}
local iterator, reason = app.fs.list(path)
if not iterator then status = tostring(reason) return result end
for raw in iterator do
local name = cleanName(raw)
if name ~= "" then
local target = app.fs.concat(path, name)
local directory = app.fs.isDirectory(target)
result[#result + 1] = {
name = name,
target = target,
dir = directory,
size = directory and 0 or (app.fs.size(target) or 0)
}
end
end
table.sort(result, function(a, b)
if a.dir ~= b.dir then return a.dir end
return a.name:lower() < b.name:lower()
end)
return result
end
local function selectedEntry(list)
return selected and list[selected] or nil
end
local function extension(name)
return tostring(name or ""):match("%.([%w_%-]+)$") or "file"
end
local function preview(entry)
if not entry then return {"nothing selected", "choose a file or folder"} end
if entry.dir then
return {entry.name, "folder", "open to browse contents"}
end
local lines = {entry.name, humanSize(entry.size), extension(entry.name)}
if entry.size > 8192 then
lines[#lines + 1] = "preview unavailable"
lines[#lines + 1] = "file is larger than 8 kb"
return lines
end
local file, reason = io.open(entry.target, "r")
if not file then lines[#lines + 1] = tostring(reason) return lines end
local data = file:read(420) or ""
file:close()
data = data:gsub("\r", ""):gsub("[%c]", " "):gsub("%s+", " ")
local position = 1
while position <= #data and #lines < 11 do
lines[#lines + 1] = data:sub(position, position + 23)
position = position + 24
end
return lines
end
local function openEntry(entry)
if not entry then status = "select an item first" return end
confirmDelete = nil
if entry.dir then
remember(entry.target)
else
status = entry.name .. " selected"
end
end
local function runEntry(entry)
if not entry or entry.dir or entry.name:sub(-4) ~= ".lua" then
status = "select a lua file"
return
end
local ok, reason = pcall(dofile, entry.target)
status = ok and ("ran " .. entry.name) or ("script error: " .. tostring(reason))
end
local function newFolder()
local base = app.fs.concat(path, "untitled folder")
local target = base
local number = 2
while app.fs.exists(target) and number < 100 do
target = base .. " " .. number
number = number + 1
end
local ok, reason = app.fs.makeDirectory(target)
status = ok and ("created " .. cleanName(target:match("[^/]+$") or target)) or tostring(reason)
selected, confirmDelete = nil, nil
end
local function deleteEntry(entry)
if not entry then status = "select an item first" return end
if confirmDelete ~= entry.target then
confirmDelete = entry.target
status = "press delete again to confirm"
return
end
local ok, reason = app.fs.remove(entry.target)
status = ok and ("deleted " .. entry.name) or ("delete failed: " .. tostring(reason))
selected, confirmDelete = nil, nil
end
local function drawToolbar(width)
win:fill(1, 1, width, 3, 0xe7edf2)
win:button("back", 2, 1, 6, "back")
win:button("forward", 9, 1, 8, "forward")
win:button("up", 18, 1, 5, "up")
win:button("home", 24, 1, 6, "home")
win:button("refresh", 31, 1, 8, "refresh")
if width >= 56 then
win:text(width - 15, 1, "finder", 0x5f7485, 0xe7edf2)
end
win:fill(2, 2, width - 3, 1, 0xf8fafc)
win:text(3, 2, short(path, width - 6), 0x29485d, 0xf8fafc)
end
local function drawSidebar(sidebarWidth, height)
if sidebarWidth <= 0 then return end
win:fill(1, 4, sidebarWidth, height - 6, 0xdce5ec)
win:text(2, 4, "favorites", 0x617487, 0xdce5ec)
for index, item in ipairs(favorites) do
local y = 5 + (index - 1) * 3
local active = path == item.path
local background = active and 0xb9ddf5 or 0xdce5ec
win:fill(1, y, sidebarWidth, 2, background)
win:icon(2, y, item.icon, active and 0x3188c9 or 0x60798b, "small")
win:text(6, y + 1, short(item.name, sidebarWidth - 7), active and 0x173247 or 0x40596b, background)
hit("favorite:" .. index, 1, y, sidebarWidth, 2, item.name)
end
win:text(2, height - 2, "idk finder", 0x7b8e9d, 0xdce5ec)
end
local function drawList(list, mainX, mainWidth, height, rows)
win:fill(mainX, 4, mainWidth, height - 6, 0xf8fafc)
win:fill(mainX, 4, mainWidth, 1, 0xe8eef3)
win:text(mainX + 1, 4, "name", 0x617487, 0xe8eef3)
if mainWidth >= 30 then win:text(mainX + mainWidth - 10, 4, "size", 0x617487, 0xe8eef3) end
for row = 1, rows do
local index = offset + row
local entry = list[index]
local y = 4 + row
local rowBackground = row % 2 == 0 and 0xf0f4f7 or 0xf8fafc
if entry then
local selectedNow = selected == index
local background = selectedNow and 0xb9ddf5 or rowBackground
local foreground = selectedNow and 0x173247 or 0x294052
win:fill(mainX, y, mainWidth, 1, background)
win:text(mainX + 1, y, entry.dir and ">" or "-", entry.dir and 0x3188c9 or 0x8aa0b0, background)
local labelWidth = mainWidth - (mainWidth >= 30 and 13 or 4)
win:text(mainX + 3, y, short(entry.name, labelWidth), foreground, background)
if mainWidth >= 30 then
win:text(mainX + mainWidth - 10, y, entry.dir and "folder" or humanSize(entry.size), 0x617487, background)
end
hit("select:" .. index, mainX, y, mainWidth, 1, entry.name)
else
win:fill(mainX, y, mainWidth, 1, rowBackground)
end
end
end
local function drawPreview(entry, previewX, previewWidth, height)
if previewWidth <= 0 then return end
win:fill(previewX, 4, previewWidth, height - 6, 0xedf3f7)
win:text(previewX + 1, 4, "preview", 0x617487, 0xedf3f7)
local info = preview(entry)
for index, line in ipairs(info) do
if index + 5 < height - 1 then
local foreground = index == 1 and 0x1d2b3a or 0x617487
win:text(previewX + 1, index + 5, short(line, previewWidth - 2), foreground, 0xedf3f7)
end
end
end
local function drawFooter(width, height, count, rows)
local actionY = height - 2
win:fill(1, actionY - 1, width, 3, 0xe7edf2)
win:button("open", 2, actionY, 7, "open")
win:button("newfolder", 10, actionY, 11, "new folder")
win:button("delete", 22, actionY, 9, confirmDelete and "confirm" or "delete")
win:button("run", 32, actionY, 6, "run")
win:button("prev", 39, actionY, 7, "prev")
win:button("next", 47, actionY, 7, "next")
if width >= 66 then win:text(width - 13, actionY, tostring(count) .. " items", 0x617487, 0xe7edf2) end
win:text(2, height - 1, short(status or "ready", width - 4), 0x38536a, 0xe7edf2)
return rows
end
local function draw()
local width, height = win.width, win.height
local sidebarWidth = width >= 52 and 16 or 0
local previewWidth = width >= 68 and 20 or 0
local mainX = sidebarWidth > 0 and sidebarWidth + 1 or 1
local mainRight = previewWidth > 0 and width - previewWidth or width
local mainWidth = math.max(14, mainRight - mainX)
local rows = math.max(4, height - 10)
local list = entries()
if selected and not list[selected] then selected = nil end
offset = math.max(0, math.min(offset, math.max(0, #list - rows)))
win:reset()
drawToolbar(width)
drawSidebar(sidebarWidth, height)
drawList(list, mainX, mainWidth, height, rows)
drawPreview(selectedEntry(list), width - previewWidth + 1, previewWidth, height)
drawFooter(width, height, #list, rows)
return list, rows
end
while true do
local list, rows = draw()
local name, address, id, code, player = app.pull()
if name == "idk_button" then
if id == "back" then goHistory(-1)
elseif id == "forward" then goHistory(1)
elseif id == "up" then remember(app.fs.path(path) or "/")
elseif id == "home" then remember("/home")
elseif id == "refresh" then status = "refreshed" selected = nil confirmDelete = nil
elseif id == "open" then openEntry(selectedEntry(list))
elseif id == "run" then runEntry(selectedEntry(list))
elseif id == "newfolder" then newFolder()
elseif id == "delete" then deleteEntry(selectedEntry(list))
elseif id == "prev" then offset = math.max(0, offset - rows) selected = nil
elseif id == "next" then if offset + rows < #list then offset = offset + rows selected = nil end
else
local favorite = tonumber(tostring(id):match("^favorite:(%d+)$"))
local index = tonumber(tostring(id):match("^select:(%d+)$"))
if favorite and favorites[favorite] then
remember(favorites[favorite].path)
elseif index and list[index] then
if selected == index then openEntry(list[index])
else selected = index status = list[index].name confirmDelete = nil end
end
end
elseif name == "key_down" then
if code == keyboard.keys.up then
selected = math.max(1, (selected or 1) - 1)
if selected <= offset then offset = math.max(0, selected - 1) end
elseif code == keyboard.keys.down then
selected = math.min(#list, (selected or 0) + 1)
if selected > offset + rows then offset = selected - rows end
elseif code == keyboard.keys.enter then
openEntry(selectedEntry(list))
elseif code == keyboard.keys.back then
goHistory(-1)
elseif code == keyboard.keys.delete then
deleteEntry(selectedEntry(list))
end
end
end
end
