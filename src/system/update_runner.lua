local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")

local BASE = "https://raw.githubusercontent.com/Guest453/idkosopencompute/main/"
local UPDATE_DIR = "/idkos/update"
local STAGE = UPDATE_DIR .. "/stage"
local BACKUP = UPDATE_DIR .. "/backup"
local PENDING = UPDATE_DIR .. "/pending.os"
local NEXT_BOOT = UPDATE_DIR .. "/next_boot"
local RUNNING = UPDATE_DIR .. "/running"
local STATE = UPDATE_DIR .. "/state.log"
local MAX_FILE = 512 * 1024
local MAX_TOTAL = 8 * 1024 * 1024

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
      if type(listed) == "function" then local nextOk nextOk, address = pcall(listed) if not nextOk then address = nil end
      elseif type(listed) == "string" then address = listed
      elseif type(listed) == "table" then
        for key, value in pairs(listed) do
          if type(key) == "string" and (value == kind or value == true) then address = key break end
          if type(value) == "string" then address = value break end
          if type(value) == "table" or type(value) == "userdata" then proxy = value pcall(function() address = value.address end) break end
        end
      end
      if not proxy and address then local proxyOk proxyOk, proxy = pcall(component.proxy, address) if not proxyOk then proxy = nil end end
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

local gpu, gpuAddress = primary("gpu")
local screen = primary("screen")
local width, height = 80, 25
local cursorY = 1

local function gpuCall(method, ...)
  return invoke(gpu, gpuAddress, method, ...)
end

if gpu then
  local bound = gpuCall("getScreen")
  local screenAddress
  pcall(function() screenAddress = screen and screen.address end)
  if screen and not bound then gpuCall("bind", screenAddress or screen) end
  local w, h = gpuCall("getResolution")
  if type(w) == "number" and type(h) == "number" then width, height = w, h end
  gpuCall("setBackground", 0xffffff)
  gpuCall("setForeground", 0x000000)
  gpuCall("fill", 1, 1, width, height, " ")
end

local lineNumber = 0
local function log(message)
  message = tostring(message or "")
  lineNumber = lineNumber + 1
  local prefix = string.format("[%04d] ", lineNumber)
  for raw in (message .. "\n"):gmatch("(.-)\n") do
    local line = prefix .. raw
    prefix = "       "
    local position = 1
    repeat
      if gpu then
        if cursorY > height then
          gpuCall("copy", 1, 2, width, height - 1, 0, -1)
          gpuCall("fill", 1, height, width, 1, " ")
          cursorY = height
        end
        gpuCall("setBackground", 0xffffff)
        gpuCall("setForeground", 0x000000)
        gpuCall("set", 1, cursorY, line:sub(position, position + width - 1))
      end
      position = position + width
      cursorY = cursorY + 1
    until position > #line
  end
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

local function readFile(path)
  local file, reason = filesystem.open(path, "r")
  if not file then return nil, reason end
  local data, readReason = file:read("*a")
  file:close()
  return data, readReason
end

local function writeFile(path, data)
  local made, makeReason = mkdirp(filesystem.path(path))
  if not made then return nil, makeReason end
  local file, reason = filesystem.open(path, "w")
  if not file then return nil, reason end
  local ok, writeReason = file:write(data)
  file:close()
  return ok, writeReason
end

local function writeAtomic(path, data)
  local temp = path .. ".update-new"
  if filesystem.exists(temp) then filesystem.remove(temp) end
  local ok, reason = writeFile(temp, data)
  if not ok then return nil, reason end
  if filesystem.exists(path) then
    local removed, removeReason = filesystem.remove(path)
    if not removed and filesystem.exists(path) then filesystem.remove(temp) return nil, removeReason end
  end
  local renamed, renameReason = filesystem.rename(temp, path)
  if not renamed then filesystem.remove(temp) return nil, renameReason end
  return true
end

local function removeTree(path)
  if not filesystem.exists(path) then return true end
  if filesystem.isDirectory(path) then
    local iterator, reason = filesystem.list(path)
    if not iterator then return nil, reason end
    local names = {}
    for raw in iterator do names[#names + 1] = tostring(raw):gsub("/$", "") end
    for _, name in ipairs(names) do
      local ok, childReason = removeTree(filesystem.concat(path, name))
      if not ok then return nil, childReason end
    end
  end
  local ok, reason = filesystem.remove(path)
  if not ok and filesystem.exists(path) then return nil, reason end
  return true
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

local function fetch(url, limit)
  local internet, address = primary("internet")
  if not internet and not address then return nil, "internet card unavailable" end
  local request, reason = invoke(internet, address, "request", url)
  if not request then return nil, reason or "request failed" end
  local parts, size = {}, 0
  local lastData = computer.uptime()
  while true do
    local chunk, readReason = requestCall(request, "read")
    if chunk == nil then
      requestCall(request, "close")
      if readReason then return nil, readReason end
      break
    elseif chunk == "" then
      if computer.uptime() - lastData > 30 then requestCall(request, "close") return nil, "network timeout" end
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

local function safeSource(path)
  return type(path) == "string" and #path <= 180 and path:match("^[%w%._/-]+$") and
    not path:find("..", 1, true) and not path:find("//", 1, true) and path:sub(1, 1) ~= "/"
end

local function safeTarget(path)
  if type(path) ~= "string" or #path > 180 or not path:match("^/[%w%._/-]+$") or
    path:find("..", 1, true) or path:find("//", 1, true) then return false end
  return path == "/init.lua" or path:sub(1, 7) == "/idkos/"
end

local function writeState(existed, applied)
  local lines = {"idk-update-state-1"}
  for target, wasPresent in pairs(existed or {}) do
    lines[#lines + 1] = "E|" .. (wasPresent and "1" or "0") .. "|" .. target
  end
  for _, target in ipairs(applied or {}) do lines[#lines + 1] = "A|" .. target end
  return writeFile(STATE, table.concat(lines, "\n") .. "\n")
end

local function readState()
  local data = readFile(STATE)
  if not data then return nil end
  local first = true
  local existed, applied = {}, {}
  for line in data:gmatch("[^\n]+") do
    if first then
      if line ~= "idk-update-state-1" then return nil end
      first = false
    else
      local present, target = line:match("^E|([01])|(.+)$")
      if present and safeTarget(target) then existed[target] = present == "1" end
      local appliedTarget = line:match("^A|(.+)$")
      if appliedTarget and safeTarget(appliedTarget) then applied[#applied + 1] = appliedTarget end
    end
  end
  return existed, applied
end

local function parsePackage(source)
  local chunk, reason = load(source, "=pending.os", "t", {})
  if not chunk then return nil, reason end
  local ok, package = pcall(chunk)
  if not ok then return nil, package end
  if type(package) ~= "table" or package.format ~= "idk-os-update-1" then return nil, "invalid .os package format" end
  if type(package.files) ~= "table" or #package.files < 1 or #package.files > 128 then return nil, "invalid package file count" end
  local version = tonumber(package.version)
  if not version or version % 1 ~= 0 or version < 1 then return nil, "invalid package version" end
  local entries, seen = {}, {}
  for _, item in ipairs(package.files) do
    if type(item) ~= "table" or not safeSource(item.source) or not safeTarget(item.target) or seen[item.target] then
      return nil, "unsafe package entry"
    end
    seen[item.target] = true
    entries[#entries + 1] = {source=item.source, target=item.target}
  end
  table.sort(entries, function(a, b)
    local function rank(target)
      if target == "/idkos/version.lua" then return 3 end
      if target == "/init.lua" then return 2 end
      return 1
    end
    local ar, br = rank(a.target), rank(b.target)
    if ar ~= br then return ar < br end
    return a.target < b.target
  end)
  package.version = version
  package.entries = entries
  return package
end

local function rollback(applied, existed)
  log("rollback started")
  local success = true
  for index = #applied, 1, -1 do
    local target = applied[index]
    if existed[target] then
      local backup, reason = readFile(BACKUP .. target)
      if backup then
        local ok, restoreReason = writeAtomic(target, backup)
        if not ok then success = false log("rollback failed for " .. target .. ": " .. tostring(restoreReason)) end
      else
        success = false
        log("backup missing for " .. target .. ": " .. tostring(reason))
      end
    else
      local ok, reason = filesystem.remove(target)
      if not ok and filesystem.exists(target) then success = false log("cannot remove new file " .. target .. ": " .. tostring(reason)) end
    end
  end
  log(success and "rollback completed" or "rollback completed with errors")
  return success
end

return function(packageSource)
  local applied, existed = {}, {}
  local function execute()
    log("IDK OS UPDATE ENVIRONMENT")
    log("white background / black text diagnostic mode")
    log("loading pending .os package into ram")

    local package, packageReason = parsePackage(packageSource)
    if not package then error(packageReason, 0) end
    log("package: " .. tostring(package.name or "unnamed.os"))
    log("target version: " .. tostring(package.version))
    log("manifest entries: " .. tostring(#package.entries))

    if filesystem.exists(STATE) then
      local oldExisted, oldApplied = readState()
      if oldExisted and oldApplied then
        log("interrupted update journal detected")
        rollback(oldApplied, oldExisted)
      end
      filesystem.remove(STATE)
    end

    removeTree(STAGE)
    removeTree(BACKUP)
    assert(mkdirp(STAGE))
    assert(mkdirp(BACKUP))

    local total = 0
    for index, item in ipairs(package.entries) do
      log(string.format("download %d/%d  %s", index, #package.entries, item.source))
      local data, reason = fetch(BASE .. item.source, MAX_FILE)
      if not data then error(item.source .. ": " .. tostring(reason), 0) end
      total = total + #data
      if total > MAX_TOTAL then error("package exceeds total size limit", 0) end
      if item.source:sub(-4) == ".lua" then
        local chunk, syntax = load(data, "=" .. item.source, "t", {})
        if not chunk then error(item.source .. ": " .. tostring(syntax), 0) end
      end
      local ok, writeReason = writeFile(STAGE .. item.target, data)
      if not ok then error("stage " .. item.target .. ": " .. tostring(writeReason), 0) end
    end

    log("all files staged and syntax checked")
    for _, item in ipairs(package.entries) do
      existed[item.target] = filesystem.exists(item.target)
      if existed[item.target] then
        local old, reason = readFile(item.target)
        if not old then error("backup read " .. item.target .. ": " .. tostring(reason), 0) end
        local ok, backupReason = writeFile(BACKUP .. item.target, old)
        if not ok then error("backup write " .. item.target .. ": " .. tostring(backupReason), 0) end
      end
    end
    log("backup completed")
    local stateOk, stateReason = writeState(existed, applied)
    if not stateOk then error("cannot write update journal: " .. tostring(stateReason), 0) end

    for index, item in ipairs(package.entries) do
      local data, reason = readFile(STAGE .. item.target)
      if not data then error("stage read " .. item.target .. ": " .. tostring(reason), 0) end
      log(string.format("apply %d/%d  %s", index, #package.entries, item.target))
      applied[#applied + 1] = item.target
      local stateWriteOk, stateWriteReason = writeState(existed, applied)
      if not stateWriteOk then error("cannot update journal: " .. tostring(stateWriteReason), 0) end
      local ok, applyReason = writeAtomic(item.target, data)
      if not ok then error("apply " .. item.target .. ": " .. tostring(applyReason), 0) end
    end

    filesystem.remove(STATE)
    filesystem.remove(NEXT_BOOT)
    filesystem.remove(RUNNING)
    filesystem.remove(PENDING)
    removeTree(STAGE)
    removeTree(BACKUP)
    log("update completed successfully")
    log("rebooting into idk os version " .. tostring(package.version))
    computer.pullSignal(2)
    computer.shutdown(true)
  end

  local ok, reason = xpcall(execute, function(value)
    if debug and debug.traceback then return debug.traceback(value, 2) end
    return tostring(value)
  end)

  if not ok then
    log("")
    log("UPDATE FAILURE")
    log(tostring(reason))
    if #applied > 0 then rollback(applied, existed) end
    filesystem.remove(STATE)
    filesystem.remove(NEXT_BOOT)
    filesystem.remove(RUNNING)
    log("pending .os package was kept at " .. PENDING)
    log("press r to retry, any other key to continue normal boot")
    while true do
      local signal = table.pack(computer.pullSignal())
      if signal[1] == "touch" then break end
      if signal[1] == "key_down" then
        local char = tonumber(signal[3])
        if char == string.byte("r") or char == string.byte("R") then
          local marker = filesystem.open(NEXT_BOOT, "w")
          if marker then marker:write("retry\n") marker:close() end
          computer.shutdown(true)
        end
        break
      end
    end
  end
end
