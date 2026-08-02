local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")

local BASE = "https://raw.githubusercontent.com/Guest453/idkosopencompute/main/"
local UPDATE_DIR = "/idkos/update"
local PENDING = UPDATE_DIR .. "/pending.os"
local NEXT_BOOT = UPDATE_DIR .. "/next_boot"
local RUNNING = UPDATE_DIR .. "/running"
local LATEST_URL = BASE .. "updates/latest.lua"
local CHECK_TIMEOUT = 5

local function primary(kind)
  local ok, direct = pcall(function() return component[kind] end)
  if ok and direct then
    local address
    pcall(function() address = direct.address end)
    return direct, address
  end

  for _, exact in ipairs({false, true}) do
    local listedOk, listed
    if exact then listedOk, listed = pcall(component.list, kind, true)
    else listedOk, listed = pcall(component.list, kind) end
    if listedOk then
      local address, proxy
      if type(listed) == "function" then
        local nextOk
        nextOk, address = pcall(listed)
        if not nextOk then address = nil end
      elseif type(listed) == "string" then
        address = listed
      elseif type(listed) == "table" then
        for key, value in pairs(listed) do
          if type(key) == "string" and (value == kind or value == true) then address = key break end
          if type(value) == "string" then address = value break end
          if type(value) == "table" or type(value) == "userdata" then proxy = value pcall(function() address = value.address end) break end
        end
      end
      if not proxy and address then
        local proxyOk
        proxyOk, proxy = pcall(component.proxy, address)
        if not proxyOk then proxy = nil end
      end
      if proxy or address then return proxy, address end
    end
  end
end

local function invoke(proxy, address, method, ...)
  local args = table.pack(...)
  if type(address) == "string" and type(component.invoke) == "function" then
    local result = {pcall(component.invoke, address, method, table.unpack(args, 1, args.n))}
    if result[1] then return table.unpack(result, 2) end
  end
  if proxy then
    local ok, fn = pcall(function() return proxy[method] end)
    if ok and type(fn) == "function" then
      local result = {pcall(fn, table.unpack(args, 1, args.n))}
      if result[1] then return table.unpack(result, 2) end
      result = {pcall(fn, proxy, table.unpack(args, 1, args.n))}
      if result[1] then return table.unpack(result, 2) end
    end
  end
  return nil, "component method unavailable: " .. tostring(method)
end

local function requestCall(request, method, ...)
  local ok, fn = pcall(function() return request and request[method] end)
  if ok and type(fn) == "function" then
    local result = {pcall(fn, ...)}
    if result[1] then return table.unpack(result, 2) end
    result = {pcall(fn, request, ...)}
    if result[1] then return table.unpack(result, 2) end
  end
  if method == "read" then
    local result = {pcall(function() return request() end)}
    if result[1] then return table.unpack(result, 2) end
  end
  return nil, "request method unavailable"
end

local function fetch(url, limit, timeout)
  local internet, address = primary("internet")
  if not internet and not address then return nil, "internet card unavailable" end
  local request, reason = invoke(internet, address, "request", url)
  if not request then return nil, reason or "request failed" end

  local parts, size = {}, 0
  local started, lastData = computer.uptime(), computer.uptime()
  while true do
    local chunk, readReason = requestCall(request, "read")
    if chunk == nil then
      requestCall(request, "close")
      if readReason then return nil, readReason end
      break
    elseif chunk == "" then
      if computer.uptime() - started > timeout or computer.uptime() - lastData > timeout then
        requestCall(request, "close")
        return nil, "network timeout"
      end
      computer.pullSignal(0.05)
    else
      lastData = computer.uptime()
      size = size + #chunk
      if size > limit then requestCall(request, "close") return nil, "download too large" end
      parts[#parts + 1] = chunk
    end
  end
  local data = table.concat(parts)
  if #data == 0 then return nil, "empty response" end
  return data
end

local function readFile(path)
  local file, reason = filesystem.open(path, "r")
  if not file then return nil, reason end
  local data, readReason = file:read("*a")
  file:close()
  return data, readReason
end

local function mkdirp(path)
  local current = ""
  for part in tostring(path):gmatch("[^/]+") do
    current = current .. "/" .. part
    if not filesystem.exists(current) then
      local ok, reason = filesystem.makeDirectory(current)
      if not ok and not filesystem.isDirectory(current) then return nil, reason end
    end
  end
  return true
end

local function writeFile(path, data)
  mkdirp(filesystem.path(path))
  local temp = path .. ".new"
  if filesystem.exists(temp) then filesystem.remove(temp) end
  local file, reason = filesystem.open(temp, "w")
  if not file then return nil, reason end
  local ok, writeReason = file:write(data)
  file:close()
  if not ok then filesystem.remove(temp) return nil, writeReason end
  if filesystem.exists(path) then filesystem.remove(path) end
  return filesystem.rename(temp, path)
end

local function loadTable(source, name)
  local chunk, reason = load(source, "=" .. name, "t", {})
  if not chunk then return nil, reason end
  local ok, result = pcall(chunk)
  if not ok then return nil, result end
  if type(result) ~= "table" then return nil, name .. " did not return a table" end
  return result
end

local function currentVersion()
  local source = readFile("/idkos/version.lua")
  if not source then return 7 end
  local value = loadTable(source, "version.lua")
  if type(value) == "table" then value = value.version end
  value = tonumber(value)
  return value and math.floor(value) or 7
end

local function gpuConsole()
  local gpu, gpuAddress = primary("gpu")
  local screen, screenAddress = primary("screen")
  if not gpu and not gpuAddress then return nil end
  local bound = invoke(gpu, gpuAddress, "getScreen")
  if screenAddress and not bound then invoke(gpu, gpuAddress, "bind", screenAddress)
  elseif screen and not bound then invoke(gpu, gpuAddress, "bind", screen) end
  local width, height = invoke(gpu, gpuAddress, "getResolution")
  if type(width) ~= "number" or type(height) ~= "number" then return nil end
  return gpu, gpuAddress, width, height
end

local function showMessage(lines, foreground, background)
  local gpu, gpuAddress, width, height = gpuConsole()
  if not gpu and not gpuAddress then return end
  invoke(gpu, gpuAddress, "setBackground", background or 0x000000)
  invoke(gpu, gpuAddress, "setForeground", foreground or 0xffffff)
  invoke(gpu, gpuAddress, "fill", 1, 1, width, height, " ")
  local y = 2
  for _, raw in ipairs(lines) do
    local position = 1
    repeat
      invoke(gpu, gpuAddress, "set", 2, y, tostring(raw):sub(position, position + width - 3))
      position = position + width - 2
      y = y + 1
    until position > #tostring(raw) or y > height
    if y > height then break end
  end
end

local function runPending()
  local packageSource, packageReason = readFile(PENDING)
  local runnerSource, runnerReason = readFile("/idkos/system/update_runner.lua")
  if not packageSource or not runnerSource then
    showMessage({
      "IDK OS UPDATE BOOT FAILURE",
      "",
      "package: " .. tostring(packageReason),
      "runner: " .. tostring(runnerReason),
      "",
      "press a key to continue normal boot"
    }, 0x000000, 0xffffff)
    computer.pullSignal()
    filesystem.remove(NEXT_BOOT)
    filesystem.remove(RUNNING)
    return
  end

  local chunk, reason = load(runnerSource, "=/idkos/system/update_runner.lua", "t", _G)
  if not chunk then error("update runner syntax: " .. tostring(reason), 0) end
  local runner = chunk()
  if type(runner) ~= "function" then error("update runner returned an invalid interface", 0) end

  filesystem.remove(NEXT_BOOT)
  mkdirp(UPDATE_DIR)
  local marker = filesystem.open(RUNNING, "w")
  if marker then marker:write("running\n") marker:close() end
  return runner(packageSource)
end

if filesystem.exists(NEXT_BOOT) or filesystem.exists(RUNNING) then
  return runPending()
end

local latestSource = fetch(LATEST_URL, 32 * 1024, CHECK_TIMEOUT)
if not latestSource then return end
local latest = loadTable(latestSource, "latest.lua")
if not latest then return end

local remoteVersion = tonumber(latest.version)
local filename = tostring(latest.file or "")
local packagePath = tostring(latest.path or "")
if not remoteVersion or remoteVersion % 1 ~= 0 or remoteVersion < 1 or remoteVersion > 999999 then return end
if not filename:match("^update%d+%.os$") then return end
if packagePath ~= "updates/" .. filename then return end

local installed = currentVersion()
if installed >= remoteVersion then return end

local warning = "Warning: There is a update avaliable, file is " .. filename
showMessage({
  warning,
  "",
  "installed version: " .. tostring(installed),
  "available version: " .. tostring(remoteVersion),
  "",
  "press u or enter to download and reboot into update",
  "press any other key to continue normal boot",
  "",
  "this prompt will continue automatically in 15 seconds"
}, 0xffd166, 0x000000)

local install = false
local deadline = computer.uptime() + 15
while computer.uptime() < deadline do
  local signal = table.pack(computer.pullSignal(math.min(0.25, deadline - computer.uptime())))
  if signal[1] == "touch" then install = true break end
  if signal[1] == "key_down" then
    local char = tonumber(signal[3])
    install = char == 13 or char == string.byte("u") or char == string.byte("U")
    break
  end
end
if not install then return end

showMessage({"downloading " .. filename, "", "please wait..."}, 0xffffff, 0x000000)
local packageSource, packageReason = fetch(BASE .. packagePath, 256 * 1024, 20)
if not packageSource then
  showMessage({"update download failed", "", tostring(packageReason), "", "continuing normal boot in 4 seconds"}, 0xff6b6b, 0x000000)
  computer.pullSignal(4)
  return
end

local package, packageError = loadTable(packageSource, filename)
if not package or package.format ~= "idk-os-update-1" or tonumber(package.version) ~= remoteVersion or package.name ~= filename then
  showMessage({"update package rejected", "", tostring(packageError or "package metadata mismatch"), "", "continuing normal boot in 4 seconds"}, 0xff6b6b, 0x000000)
  computer.pullSignal(4)
  return
end

mkdirp(UPDATE_DIR)
local saved, saveReason = writeFile(PENDING, packageSource)
if not saved then
  showMessage({"cannot save update package", "", tostring(saveReason), "", "continuing normal boot in 4 seconds"}, 0xff6b6b, 0x000000)
  computer.pullSignal(4)
  return
end
local marker, markerReason = filesystem.open(NEXT_BOOT, "w")
if not marker then
  showMessage({"cannot schedule update", "", tostring(markerReason), "", "continuing normal boot in 4 seconds"}, 0xff6b6b, 0x000000)
  computer.pullSignal(4)
  return
end
marker:write(filename .. "\n")
marker:close()
computer.shutdown(true)
