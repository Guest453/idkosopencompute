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

-- openos phase: acquire and validate every byte before showing any target disk.
local manifest = loadManifest()
local image, imageBytes = {}, 0
for _, item in ipairs(manifest.files) do
  io.write("downloading " .. item.source .. " ... ")
  local data, reason = fetch(item.source, maxFileSize)
  if not data then fail("download failed for " .. item.source .. ": " .. tostring(reason)) end
  local _, syntaxError = validateLua(data, item.source)
  if syntaxError then fail("invalid lua in " .. item.source .. ": " .. tostring(syntaxError)) end
  imageBytes = imageBytes + #data
  if imageBytes > maxImageSize then fail("image exceeds the ram safety limit") end
  image[#image + 1] = {target = item.target, data = data}
  io.write("ok\n")
end
local requiredSpace = imageBytes + #image * 1024 + 4096

local function rootAddress()
  local ok, proxy = pcall(filesystem.get, "/")
  return ok and proxy and proxy.address or nil
end

-- capture all state and raw entry points while openos is still available.
local currentRoot = rootAddress()
local getBootAddress = computer.getBootAddress
local setBootAddress = computer.setBootAddress
local temporaryAddress = type(computer.tmpAddress) == "function" and computer.tmpAddress() or nil
local bootAddress = type(getBootAddress) == "function" and getBootAddress() or nil
local componentList = component.list
local componentProxy = component.proxy
local pullSignal = computer.pullSignal
local shutdown = computer.shutdown
local traceback = debug and debug.traceback or tostring

if type(componentList) ~= "function" or type(componentProxy) ~= "function" or type(pullSignal) ~= "function"
  or type(shutdown) ~= "function" or type(getBootAddress) ~= "function" or type(setBootAddress) ~= "function" then
  fail("raw component or computer services are unavailable")
end

local gpuAddress = componentList("gpu")()
local screenAddress = componentList("screen")()
if not gpuAddress or not screenAddress then fail("a gpu and screen are required for the ram installer") end
local gpu = componentProxy(gpuAddress)
if not gpu then fail("cannot access the gpu for the ram installer") end
if not gpu.getScreen() then
  local bound, bindReason = gpu.bind(screenAddress)
  if not bound then fail("cannot bind installer screen: " .. tostring(bindReason)) end
end
local resolutionOk, width, height = pcall(gpu.getResolution)
if not resolutionOk or type(width) ~= "number" or type(height) ~= "number" or width < 40 or height < 12 then
  fail("the ram installer requires a working screen of at least 40x12")
end

-- ram phase: nothing below this transition uses io, filesystem, internet, require, package, or shell.
local contentTop, contentBottom = 4, height - 4
local logRow = contentTop

local function paint(foreground, background)
  pcall(gpu.setForeground, foreground)
  pcall(gpu.setBackground, background)
end

local function put(x, y, text, foreground, background)
  text = tostring(text)
  if foreground or background then paint(foreground or 0xf2f2f7, background or 0x101116) end
  pcall(gpu.set, x, y, text:sub(1, math.max(0, width - x + 1)))
end

local function clearLine(y, background)
  pcall(gpu.setBackground, background or 0x101116)
  pcall(gpu.fill, 1, y, width, 1, " ")
end

local function drawChrome()
  paint(0xf2f2f7, 0x101116)
  pcall(gpu.fill, 1, 1, width, height, " ")
  paint(0xffffff, 0x2457d6)
  pcall(gpu.fill, 1, 1, width, 1, " ")
  put(3, 1, "idk os installer", 0xffffff, 0x2457d6)
  put(math.max(1, width - 21), 1, "ram recovery session", 0xffffff, 0x2457d6)
  put(3, 2, "running entirely from ram", 0x67d5ff, 0x101116)
  put(3, 3, "openos and network services are no longer in use", 0x8e8e93, 0x101116)
  clearLine(height, 0x25262c)
  put(3, height, "return: submit   backspace: edit   type cancel to power off", 0xc7c7cc, 0x25262c)
end

local function clearContent()
  for y = contentTop, contentBottom do clearLine(y) end
  logRow = contentTop
end

local function status(message, color)
  if logRow > contentBottom then
    pcall(gpu.copy, 1, contentTop + 1, width, contentBottom - contentTop, 0, -1)
    logRow = contentBottom
  end
  clearLine(logRow)
  put(3, logRow, tostring(message), color or 0xf2f2f7, 0x101116)
  logRow = logRow + 1
end

local function powerOff(reboot)
  pcall(shutdown, reboot)
  while true do pcall(pullSignal) end
end

local wiped = false
local function fatal(reason)
  status("fatal installation failure: " .. tostring(reason), 0xff6961)
  if wiped then
    status("the target was erased; rollback is impossible. boot another disk to retry.", 0xff9f0a)
  else
    status("erasure did not start; the target was not intentionally changed.", 0x67d5ff)
  end
  status("computer halted.", 0xff6961)
  powerOff(false)
end

local function promptLine(prompt)
  local buffer = ""
  while true do
    clearLine(height - 3)
    clearLine(height - 2)
    put(3, height - 3, prompt, 0xf2f2f7, 0x101116)
    local visible = buffer
    local available = math.max(1, width - 5)
    if #visible > available then visible = visible:sub(#visible - available + 1) end
    put(3, height - 2, "> " .. visible, 0xffffff, 0x101116)
    local signal, _, char, code = pullSignal()
    if signal == "key_down" then
      if code == 28 then
        clearLine(height - 3)
        clearLine(height - 2)
        return buffer
      elseif code == 14 then
        buffer = buffer:sub(1, -2)
      elseif type(char) == "number" and char >= 32 and char <= 126 then
        buffer = buffer .. string.char(char)
      end
    end
  end
end

local function rawValue(proxy, method, fallback)
  if type(proxy[method]) ~= "function" then return fallback end
  local ok, result = pcall(proxy[method])
  if not ok then return fallback end
  return result
end

local function cleanName(name)
  if type(name) ~= "string" then fail("filesystem returned a non-string directory entry") end
  name = name:gsub("/$", "")
  if name == "" or name == "." or name == ".." or name:find("/", 1, true) or name:find("\\", 1, true) then
    fail("filesystem returned unsafe directory entry " .. string.format("%q", name))
  end
  return name
end

local ramOk, ramReason = xpcall(function()
  drawChrome()
  status("image validated: " .. #image .. " files, " .. imageBytes .. " bytes", 0x30d158)
  status("discovering raw filesystem components ...", 0x67d5ff)

  -- enumeration deliberately occurs only after the visible ram transition.
  local disks = {}
  for address in componentList("filesystem") do
    local proxyOk, proxy = pcall(componentProxy, address)
    if proxyOk and proxy then
      local readOnlyValue = rawValue(proxy, "isReadOnly", nil)
      disks[#disks + 1] = {
        address = address,
        proxy = proxy,
        label = rawValue(proxy, "getLabel", "") or "",
        total = rawValue(proxy, "spaceTotal", 0) or 0,
        used = rawValue(proxy, "spaceUsed", 0) or 0,
        readOnly = readOnlyValue ~= false
      }
    end
  end
  table.sort(disks, function(a, b) return a.address < b.address end)
  if #disks == 0 then fail("no filesystem components found") end

  clearContent()
  status("select a target filesystem", 0xffffff)
  status("all data on the selected filesystem will be permanently erased.", 0xff9f0a)
  for index, disk in ipairs(disks) do
    local flags = {}
    if disk.address == bootAddress then flags[#flags + 1] = "current boot" end
    if disk.address == currentRoot then flags[#flags + 1] = "current root" end
    if disk.address == temporaryAddress then flags[#flags + 1] = "temporary; not bootable" end
    if disk.readOnly then flags[#flags + 1] = "read-only" end
    status(string.format("[%d] %s", index, disk.address), disk.readOnly and 0xff6961 or 0xf2f2f7)
    status(string.format("    label=%q  used=%d  capacity=%d%s", disk.label, disk.used, disk.total,
      #flags > 0 and ("  [" .. table.concat(flags, ", ") .. "]") or ""), 0x8e8e93)
  end

  local selected
  while not selected do
    local selection = promptLine("select target disk number (no default), or type cancel")
    if selection == "cancel" then
      status("installation cancelled; no disk was changed.", 0x67d5ff)
      powerOff(false)
    end
    local candidate = disks[tonumber(selection) or 0]
    if not candidate then
      status("invalid selection; choose an explicit disk number.", 0xff6961)
    elseif candidate.address == temporaryAddress then
      status("the temporary filesystem cannot persist across reboot.", 0xff6961)
    elseif candidate.readOnly then
      status("selected filesystem is read-only or its writable state is unavailable.", 0xff6961)
    elseif candidate.total < requiredSpace then
      status(string.format("capacity %d is too small; at least %d bytes are required.", candidate.total, requiredSpace), 0xff6961)
    else
      selected = candidate
    end
  end

  clearContent()
  status("destructive confirmation", 0xff9f0a)
  status("target: " .. selected.address, 0xffffff)
  status("label: " .. string.format("%q", selected.label), 0x8e8e93)
  if selected.address == currentRoot then status("warning: this is the former openos root disk.", 0xff9f0a) end
  if selected.address == bootAddress then status("warning: this is the current firmware boot disk.", 0xff9f0a) end
  status("after erasure starts there is no rollback.", 0xff6961)
  local expected = "erase " .. selected.address
  local confirmation = promptLine("type exactly: " .. expected)
  if confirmation ~= expected then
    status("confirmation did not match; no disk was changed.", 0x67d5ff)
    powerOff(false)
  end

  local target = selected.proxy
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
  local function closeChecked(handle, path)
    local closed, reason = target.close(handle)
    if closed == false then fail("cannot close " .. path .. ": " .. tostring(reason)) end
  end
  local function writeExact(path, data)
    makeParent(path)
    local handle, reason = target.open(path, "w")
    if not handle then fail("cannot open " .. path .. ": " .. tostring(reason)) end
    local offset = 1
    while offset <= #data do
      local chunk = data:sub(offset, offset + 2047)
      local written, writeReason = target.write(handle, chunk)
      if not written then pcall(target.close, handle); fail("cannot write " .. path .. ": " .. tostring(writeReason)) end
      offset = offset + #chunk
    end
    closeChecked(handle, path)
    handle, reason = target.open(path, "r")
    if not handle then fail("cannot verify " .. path .. ": " .. tostring(reason)) end
    local parts = {}
    while true do
      local chunk, readReason = target.read(handle, 2048)
      if chunk == nil then
        if readReason then pcall(target.close, handle); fail("cannot verify " .. path .. ": " .. tostring(readReason)) end
        break
      end
      parts[#parts + 1] = chunk
    end
    closeChecked(handle, path)
    if table.concat(parts) ~= data then fail("verification mismatch for " .. path) end
  end

  clearContent()
  if target.isReadOnly() ~= false then fail("target became read-only before erasure") end
  status("erasing " .. selected.address .. " ...", 0xff9f0a)
  wiped = true
  wipeDirectory("/")
  for _, file in ipairs(image) do
    status("writing and verifying " .. file.target)
    writeExact(file.target, file.data)
  end
  if type(target.setLabel) == "function" then
    local labelOk, labelResult, labelReason = pcall(target.setLabel, "idk os")
    if not labelOk or not labelResult then
      fail("image verified, but setting disk label failed: " .. tostring(labelReason or labelResult))
    end
  end
  local setOk, setReason = pcall(setBootAddress, selected.address)
  if not setOk then fail("image verified, but setting boot address failed: " .. tostring(setReason)) end
  if getBootAddress() ~= selected.address then fail("firmware did not retain the selected boot address") end

  status("idk os image written and verified.", 0x30d158)
  status("boot address set to " .. selected.address, 0x30d158)
  status("rebooting into /init.lua ...", 0x67d5ff)
  powerOff(true)
end, traceback)

if not ramOk then fatal(ramReason) end
