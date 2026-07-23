local component = require("component")
local filesystem = require("filesystem")
local shell = require("shell")

if not component.isAvailable("internet") then
  io.stderr:write("idk os installer needs an internet card.\n")
  return
end

local base = "https://raw.githubusercontent.com/Guest453/idkosopencompute/main/"
local files = {
  "src/boot.lua",
  "src/system/json.lua",
  "src/system/core.lua",
  "src/system/ui.lua",
  "src/apps/taskmanager.app/manifest.lua",
  "src/apps/taskmanager.app/main.lua",
  "src/apps/files.app/manifest.lua",
  "src/apps/files.app/main.lua",
  "src/apps/terminal.app/manifest.lua",
  "src/apps/terminal.app/main.lua",
  "src/apps/settings.app/manifest.lua",
  "src/apps/settings.app/main.lua",
  "src/apps/store.app/manifest.lua",
  "src/apps/store.app/main.lua"
}

local function parent(path)
  return path:match("^(.*)/[^/]+$")
end

local function download(remote, localPath)
  local dir = parent(localPath)
  if dir then filesystem.makeDirectory(dir) end
  io.write("downloading " .. remote .. " ... ")
  local ok, reason = shell.execute("wget -fq " .. base .. remote .. " " .. localPath)
  if not ok then
    io.write("failed\n")
    error(reason or ("failed to download " .. remote))
  end
  io.write("ok\n")
end

filesystem.makeDirectory("/idkos")
for _, path in ipairs(files) do
  download(path, "/idkos/" .. path:gsub("^src/", ""))
end

local shrc = "/home/.shrc"
local marker = "# idk os autostart"
local existing = ""
if filesystem.exists(shrc) then
  local f = io.open(shrc, "r")
  if f then existing = f:read("*a") or "" f:close() end
end
if not existing:find(marker, 1, true) then
  local f = assert(io.open(shrc, "a"))
  f:write("\n" .. marker .. "\n/idkos/boot.lua\n")
  f:close()
end

print("idk os installed. run /idkos/boot.lua or reboot.")
