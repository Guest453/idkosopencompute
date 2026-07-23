local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")
local internet = require("internet")

local base = "https://raw.githubusercontent.com/Guest453/idkosopencompute/main/"
local manifestPath = "image.lua"
local maxFileSize = 256 * 1024
local maxImageSize = 1024 * 1024

local function fail(message)
  error(tostring(message), 0)
end

local function responseCode(handle)
  local mt = getmetatable(handle)
  local response = mt and mt.__index and mt.__index.response
  if type(response) == "function" then
    local ok, code = pcall(response)
    if ok then return code end
  end
end

local function fetch(remote, limit)
  local ok, handle, reason = pcall(internet.request, base .. remote)
  if not ok then return nil, handle end
  if not handle then return nil, reason or "request failed" end
  local parts, size = {}, 0
  local readOk, readError = pcall(function()
    for chunk in handle do
      size = size + #chunk
      if size > limit then error("download exceeds size limit") end
      parts[#parts + 1] = chunk
    end
  end)
  local code = responseCode(handle)
  pcall(handle.close)
  if not readOk then return nil, readError end
  if code and (code < 200 or code >= 300) then return nil, "http " .. tostring(code) end
  local data = table.concat(parts)
  if #data == 0 then return nil, "empty response" end
  return data
end

local function validateLua(data, name)
  local fn, reason = load(data, "=" .. name, "t", {})
  if not fn then return nil, reason end
  return fn
end

local function loadManifest()
  io.write("downloading image manifest ... ")
  local data, reason = fetch(manifestPath, maxFileSize)
  if not data then fail("manifest download failed: " .. tostring(reason)) end
  local fn, syntaxError = validateLua(data, manifestPath)
  if not fn then fail("invalid image manifest lua: " .. tostring(syntaxError)) end
  local ok, manifest = pcall(fn)
  if not ok or type(manifest) ~= "table" or type(manifest.files) ~= "table" then
    fail("image manifest did not return a files table")
  end
  if #manifest.files < 1 or #manifest.files > 64 then fail("invalid image file count") end
  local targets, sources = {}, {}
  for index, item in ipairs(manifest.files) do
    if type(item) ~= "table" or type(item.source) ~= "string" or type(item.target) ~= "string" then
      fail("invalid image entry " .. index)
    end
    if not item.source:match("^[%w_.-]+/[%w_./-]+%.lua$") or item.source:find("..", 1, true) then
      fail("unsafe image source: " .. item.source)
    end
    if item.target:sub(1, 1) ~= "/" or item.target:find("//", 1, true) or item.target:find("..", 1, true)
      or not item.target:match("^/[%w_./-]+%.lua$") then
      fail("unsafe image target: " .. item.target)
    end
    if targets[item.target] or sources[item.source] then fail("duplicate image entry: " .. item.target) end
    targets[item.target], sources[item.source] = true, true
  end
  for _, required in ipairs({"/init.lua", "/idkos/boot.lua", "/idkos/system/runtime.lua", "/idkos/system/core.lua", "/idkos/system/ui.lua"}) do
    if not targets[required] then fail("image is missing required file " .. required) end
  end
  io.write("ok\n")
  return manifest
end

local function rootAddress()
  local ok, proxy = pcall(filesystem.get, "/")
  return ok and proxy and proxy.address or nil
end

local bootAddress = type(computer.getBootAddress) == "function" and computer.getBootAddress() or nil
local currentRoot = rootAddress()
local temporaryAddress = type(computer.tmpAddress) == "function" and computer.tmpAddress() or nil
local disks = {}
for address in component.list("filesystem") do
  local proxy = component.proxy(address)
  local function value(method, fallback)
    local ok, result = pcall(proxy[method])
    return ok and result or fallback
  end
  disks[#disks + 1] = {
    address = address,
    proxy = proxy,
    label = value("getLabel", "") or "",
    total = value("spaceTotal", 0) or 0,
    used = value("spaceUsed", 0) or 0,
    readOnly = value("isReadOnly", true) ~= false
  }
end
table.sort(disks, function(a, b) return a.address < b.address end)

if #disks == 0 then fail("no filesystem components found") end
print("idk os destructive standalone installer")
print("all data on the selected filesystem will be permanently erased.")
print("the selected disk may be the disk currently running OpenOS.")
print("")
for index, disk in ipairs(disks) do
  local flags = {}
  if disk.address == bootAddress then flags[#flags + 1] = "current boot" end
  if disk.address == currentRoot then flags[#flags + 1] = "current root" end
  if disk.address == temporaryAddress then flags[#flags + 1] = "temporary; not bootable" end
  if disk.readOnly then flags[#flags + 1] = "read-only" end
  print(string.format("[%d] %s  label=%q  used=%d  capacity=%d%s", index, disk.address,
    disk.label, disk.used, disk.total, #flags > 0 and ("  [" .. table.concat(flags, ", ") .. "]") or ""))
end

io.write("select target disk number (or type cancel): ")
local selection = io.read()
if selection == "cancel" then print("installation cancelled; no disk was changed.") return end
local selected = disks[tonumber(selection or "") or 0]
if not selected then fail("no valid target selected; no disk was changed") end
if selected.address == temporaryAddress then fail("the temporary filesystem cannot persist across reboot; no disk was changed") end
if selected.readOnly then fail("selected filesystem is read-only; no disk was changed") end
if type(computer.setBootAddress) ~= "function" then
  fail("the active firmware does not expose computer.setBootAddress; cannot make the selected disk bootable")
end

local manifest = loadManifest()
local image, imageBytes = {}, 0
for _, item in ipairs(manifest.files) do
  io.write("downloading " .. item.source .. " ... ")
  local data, reason = fetch(item.source, maxFileSize)
  if not data then fail("download failed for " .. item.source .. ": " .. tostring(reason)) end
  local _, syntaxError = validateLua(data, item.source)
  if syntaxError then fail("invalid lua in " .. item.source .. ": " .. tostring(syntaxError)) end
  imageBytes = imageBytes + #data
  if imageBytes > maxImageSize then fail("image exceeds the RAM safety limit") end
  image[#image + 1] = {target = item.target, data = data}
  io.write("ok\n")
end

local requiredSpace = imageBytes + #image * 1024 + 4096
if selected.total < requiredSpace then
  fail(string.format("target capacity %d is too small; image requires at least %d bytes", selected.total, requiredSpace))
end

print("")
print("danger: this is the final gate. after erasure starts there is no rollback.")
print("target: " .. selected.address .. "  label=" .. string.format("%q", selected.label))
io.write("to erase it, type exactly: erase " .. selected.address .. "\n> ")
local confirmation = io.read()
if confirmation ~= "erase " .. selected.address then
  print("confirmation did not match; no disk was changed.")
  return
end

-- no openos filesystem, io, package, or network operation is used below this point.
local target = selected.proxy
local gpuAddress = component.list("gpu")()
local screenAddress = component.list("screen")()
local gpu = gpuAddress and component.proxy(gpuAddress) or nil
local row, width, height = 1, 80, 25
if gpu then
  if screenAddress and not gpu.getScreen() then pcall(gpu.bind, screenAddress) end
  local ok, w, h = pcall(gpu.getResolution)
  if ok then width, height = w, h end
  pcall(gpu.setBackground, 0x000000)
  pcall(gpu.setForeground, 0xffffff)
  pcall(gpu.fill, 1, 1, width, height, " ")
end
local function status(message)
  message = tostring(message)
  if gpu then
    if row > height then pcall(gpu.copy, 1, 2, width, height - 1, 0, -1); row = height end
    pcall(gpu.fill, 1, row, width, 1, " ")
    pcall(gpu.set, 1, row, message:sub(1, width))
    row = row + 1
  end
end
local wiped = false
local function fatal(reason)
  status("fatal installation failure: " .. tostring(reason))
  if wiped then status("the target was erased; rollback is impossible. rerun the installer from another boot disk.")
  else status("erasure did not start; the target may be unchanged.") end
  status("computer halted.")
  computer.shutdown(false)
end

local function cleanName(name)
  if type(name) ~= "string" then fail("filesystem returned a non-string directory entry") end
  name = name:gsub("/$", "")
  if name == "" or name == "." or name == ".." or name:find("/", 1, true) or name:find("\\", 1, true) then
    fail("filesystem returned unsafe directory entry " .. string.format("%q", name))
  end
  return name
end
local function join(parent, name)
  return parent == "/" and ("/" .. name) or (parent .. "/" .. name)
end
local function wipeDirectory(path)
  local entries, reason = target.list(path)
  if not entries then fail("cannot list " .. path .. ": " .. tostring(reason)) end
  for _, rawName in ipairs(entries) do
    local child = join(path, cleanName(rawName))
    local isDir, dirReason = target.isDirectory(child)
    if isDir == nil then fail("cannot inspect " .. child .. ": " .. tostring(dirReason)) end
    if isDir then wipeDirectory(child) end
    local removed, removeReason = target.remove(child)
    if not removed then fail("cannot erase " .. child .. ": " .. tostring(removeReason)) end
  end
end
local function makeParent(path)
  local parent = path:match("^(.*)/[^/]+$")
  if parent and parent ~= "" and parent ~= "/" and not target.exists(parent) then
    local made, reason = target.makeDirectory(parent)
    if not made and not target.isDirectory(parent) then fail("cannot create " .. parent .. ": " .. tostring(reason)) end
  end
end
local function writeExact(path, data)
  makeParent(path)
  local handle, reason = target.open(path, "w")
  if not handle then fail("cannot open " .. path .. ": " .. tostring(reason)) end
  local offset = 1
  while offset <= #data do
    local chunk = data:sub(offset, offset + 2047)
    local written, writeReason = target.write(handle, chunk)
    if not written then target.close(handle); fail("cannot write " .. path .. ": " .. tostring(writeReason)) end
    offset = offset + #chunk
  end
  target.close(handle)
  handle, reason = target.open(path, "r")
  if not handle then fail("cannot verify " .. path .. ": " .. tostring(reason)) end
  local parts = {}
  while true do
    local chunk, readReason = target.read(handle, 2048)
    if chunk == nil then
      if readReason then target.close(handle); fail("cannot verify " .. path .. ": " .. tostring(readReason)) end
      break
    end
    parts[#parts + 1] = chunk
  end
  target.close(handle)
  if table.concat(parts) ~= data then fail("verification mismatch for " .. path) end
end

local ok, reason = xpcall(function()
  if target.isReadOnly() then fail("target became read-only before erasure") end
  status("erasing " .. selected.address .. " ...")
  wiped = true
  wipeDirectory("/")
  for _, file in ipairs(image) do
    status("writing " .. file.target)
    writeExact(file.target, file.data)
  end
  if type(target.setLabel) == "function" then
    local labelOk, labelResult, labelReason = pcall(target.setLabel, "idk os")
    if not labelOk or not labelResult then
      fail("image verified, but setting disk label failed: " .. tostring(labelReason or labelResult))
    end
  end
  local setOk, setReason = pcall(computer.setBootAddress, selected.address)
  if not setOk then fail("image verified, but setting boot address failed: " .. tostring(setReason)) end
  if computer.getBootAddress() ~= selected.address then fail("firmware did not retain the selected boot address") end
end, debug.traceback)
if not ok then fatal(reason) return end

status("idk os image written and verified.")
status("boot address set to " .. selected.address)
status("rebooting into /init.lua ...")
computer.shutdown(true)
