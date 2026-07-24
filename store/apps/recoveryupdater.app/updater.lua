local boot = ...
local rawComponent, rawComputer = component, computer
local BASE = "https://raw.githubusercontent.com/Guest453/idkosopencompute/main/"
local RECOVERY = "/idkos/recovery"
local STAGE = RECOVERY .. "/stage"
local BACKUP = RECOVERY .. "/backup"
local MAX_FILE = 512 * 1024
local MAX_TOTAL = 8 * 1024 * 1024

if type(boot) ~= "table" and type(boot) ~= "userdata" then
  error("boot filesystem proxy was not supplied", 0)
end

local function pack(...)
  return {n=select("#", ...), ...}
end

local function proxyComponent(value)
  if type(value) == "string" then
    local ok, proxy = pcall(function() return rawComponent.proxy(value) end)
    return ok and proxy or nil, value
  elseif type(value) == "table" or type(value) == "userdata" then
    local address
    pcall(function() address = value.address end)
    return value, address
  end
  return nil
end

local function listedComponent(kind, exact)
  local ok, result
  if exact == nil then
    ok, result = pcall(function() return rawComponent.list(kind) end)
  else
    ok, result = pcall(function() return rawComponent.list(kind, exact) end)
  end
  if not ok then return nil end

  if type(result) == "function" then
    local nextOk, address = pcall(result)
    if nextOk then return address end
  elseif type(result) == "string" then
    return result
  elseif type(result) == "table" then
    for key, value in pairs(result) do
      if type(key) == "string" and value == kind then return key end
      if type(key) == "number" and type(value) == "string" then return value end
      if type(value) == "table" or type(value) == "userdata" then
        local address
        pcall(function() address = value.address end)
        if address then return value end
      end
    end
  end
  return nil
end

local function primary(kind)
  local listed = listedComponent(kind, nil) or listedComponent(kind, true)
  if listed then
    local proxy, address = proxyComponent(listed)
    if proxy or address then return proxy, address end
  end

  local directOk, direct = pcall(function() return rawComponent[kind] end)
  if directOk and direct then
    local proxy, address = proxyComponent(direct)
    if proxy or address then return proxy, address end
  end
  return nil
end

local function invokeComponent(proxy, address, method, ...)
  local args = pack(...)
  local failures = {}

  if type(address) == "string" then
    local ok, a, b, c = pcall(function()
      return rawComponent.invoke(address, method, table.unpack(args, 1, args.n))
    end)
    if ok then return true, a, b, c end
    failures[#failures + 1] = tostring(a)
  end

  local methodOk, fn = pcall(function()
    return proxy and proxy[method]
  end)
  if methodOk and fn ~= nil then
    local ok, a, b, c = pcall(function()
      return fn(table.unpack(args, 1, args.n))
    end)
    if ok then return true, a, b, c end
    failures[#failures + 1] = tostring(a)

    local selfOk, sa, sb, sc = pcall(function()
      return fn(proxy, table.unpack(args, 1, args.n))
    end)
    if selfOk then return true, sa, sb, sc end
    failures[#failures + 1] = tostring(sa)
  end

  return false, nil, table.concat(failures, "; ")
end

local gpu, gpuAddress = primary("gpu")
local _, screenAddress = primary("screen")
local width, height = 50, 16

local function gpuCall(method, ...)
  return invokeComponent(gpu, gpuAddress, method, ...)
end

if gpu or gpuAddress then
  local screenOk, bound = gpuCall("getScreen")
  if screenAddress and (not screenOk or not bound) then gpuCall("bind", screenAddress) end
  local ok, w, h = gpuCall("getResolution")
  if ok and type(w) == "number" and type(h) == "number" then
    width, height = w, h
  end
end

local function paint(title, detail, progress)
  if not gpu and not gpuAddress then return end
  gpuCall("setBackground", 0x102a43)
  gpuCall("setForeground", 0xffffff)
  gpuCall("fill", 1, 1, width, height, " ")
  gpuCall("setBackground", 0x397fca)
  gpuCall("fill", 1, 1, width, 2, " ")
  gpuCall("setForeground", 0xffffff)
  gpuCall("set", 2, 1, "idk os recovery updater")
  gpuCall("setForeground", 0xbdd7ea)
  gpuCall("set", 2, 2, "running from ram - do not power off")
  gpuCall("setBackground", 0x102a43)
  gpuCall("setForeground", 0xffffff)
  gpuCall("set", 2, 5, tostring(title or "working"):sub(1, math.max(1, width - 3)))
  gpuCall("setForeground", 0x9fc4dd)
  gpuCall("set", 2, 7, tostring(detail or ""):sub(1, math.max(1, width - 3)))

  if type(progress) == "number" then
    local barWidth = math.max(10, width - 6)
    local filled = math.max(0, math.min(barWidth, math.floor(barWidth * progress)))
    gpuCall("setBackground", 0x173f5f)
    gpuCall("fill", 3, 10, barWidth, 1, " ")
    if filled > 0 then
      gpuCall("setBackground", 0x55d98b)
      gpuCall("fill", 3, 10, filled, 1, " ")
    end
    gpuCall("setBackground", 0x102a43)
  end
end

local function parent(path)
  return tostring(path):match("^(.*)/[^/]+$") or "/"
end

local function mkdirp(path)
  local current = ""
  for part in tostring(path):gmatch("[^/]+") do
    current = current .. "/" .. part
    if not boot.exists(current) then
      local ok, reason = boot.makeDirectory(current)
      if not ok and not boot.isDirectory(current) then return nil, reason end
    end
  end
  return true
end

local function readFile(path)
  local handle, reason = boot.open(path, "r")
  if not handle then return nil, reason end
  local parts = {}
  while true do
    local chunk, readReason = boot.read(handle, 2048)
    if chunk == nil then
      boot.close(handle)
      if readReason then return nil, readReason end
      return table.concat(parts)
    end
    parts[#parts + 1] = chunk
  end
end

local function writeFile(path, data)
  local made, makeReason = mkdirp(parent(path))
  if not made then return nil, makeReason end
  local handle, reason = boot.open(path, "w")
  if not handle then return nil, reason end
  local offset = 1
  while offset <= #data do
    local chunk = data:sub(offset, offset + 2047)
    local ok, writeReason = boot.write(handle, chunk)
    if not ok then boot.close(handle) return nil, writeReason end
    offset = offset + #chunk
  end
  boot.close(handle)
  return true
end

local function listEntries(path)
  local result, reason = boot.list(path)
  if not result then return nil, reason end
  local entries = {}
  if type(result) == "table" then
    for _, name in ipairs(result) do entries[#entries + 1] = name end
  elseif type(result) == "function" then
    for name in result do entries[#entries + 1] = name end
  else
    return nil, "unsupported directory listing"
  end
  return entries
end

local function removeTree(path)
  if not boot.exists(path) then return true end
  if boot.isDirectory(path) then
    local entries, reason = listEntries(path)
    if not entries then return nil, reason end
    for _, name in ipairs(entries) do
      name = tostring(name):gsub("/$", "")
      local ok, childReason = removeTree(path .. "/" .. name)
      if not ok then return nil, childReason end
    end
  end
  local ok, reason = boot.remove(path)
  if not ok and boot.exists(path) then return nil, reason end
  return true
end

local function writeAtomic(path, data)
  local temp = path .. ".update-new"
  if boot.exists(temp) then removeTree(temp) end
  local written, writeReason = writeFile(temp, data)
  if not written then return nil, writeReason end
  if boot.exists(path) then
    local removed, removeReason = boot.remove(path)
    if not removed and boot.exists(path) then
      removeTree(temp)
      return nil, removeReason
    end
  end
  local renamed, renameReason = boot.rename(temp, path)
  if not renamed then
    removeTree(temp)
    return nil, renameReason
  end
  return true
end

local internet, internetAddress = primary("internet")
if not internet and not internetAddress then error("internet card is unavailable", 0) end

local function requestMethod(request, method, ...)
  local args = pack(...)
  local methodOk, fn = pcall(function() return request and request[method] end)
  local failures = {}

  if methodOk and fn ~= nil then
    local ok, a, b, c = pcall(function()
      return fn(table.unpack(args, 1, args.n))
    end)
    if ok then return true, a, b, c end
    failures[#failures + 1] = tostring(a)

    local selfOk, sa, sb, sc = pcall(function()
      return fn(request, table.unpack(args, 1, args.n))
    end)
    if selfOk then return true, sa, sb, sc end
    failures[#failures + 1] = tostring(sa)
  end

  if method == "read" then
    local callableOk, a, b = pcall(function() return request() end)
    if callableOk then return true, a, b end
    failures[#failures + 1] = tostring(a)
  end

  return false, nil, table.concat(failures, "; ")
end

local function closeRequest(request)
  if request then requestMethod(request, "close") end
end

local function fetch(url, limit)
  local called, request, reason = invokeComponent(internet, internetAddress, "request", url)
  if not called then return nil, reason or "internet request method is unavailable" end
  if not request then return nil, reason or "request failed" end

  local parts, size = {}, 0
  local lastData = rawComputer.uptime()

  while true do
    local readOk, chunk, readReason = requestMethod(request, "read")
    if not readOk then
      closeRequest(request)
      return nil, readReason or "response read method is unavailable"
    end

    if chunk == nil then
      if readReason then
        closeRequest(request)
        return nil, readReason
      end
      break
    elseif chunk == "" then
      if rawComputer.uptime() - lastData > 30 then
        closeRequest(request)
        return nil, "network timeout"
      end
      rawComputer.pullSignal(0.05)
    else
      lastData = rawComputer.uptime()
      size = size + #chunk
      if size > limit then
        closeRequest(request)
        return nil, "download exceeds size limit"
      end
      parts[#parts + 1] = chunk
    end
  end

  local responseCode
  local responseOk, code = requestMethod(request, "response")
  if responseOk then responseCode = tonumber(code) end
  closeRequest(request)

  if responseCode and (responseCode < 200 or responseCode >= 300) then
    return nil, "http " .. tostring(responseCode)
  end

  local data = table.concat(parts)
  if #data == 0 then return nil, "empty response" end
  return data
end

local function safeSource(path)
  return type(path) == "string" and #path <= 160 and path:match("^[%w%._/-]+$") and
    not path:find("..", 1, true) and not path:find("//", 1, true) and
    path:sub(1,1) ~= "/" and path:sub(-1) ~= "/"
end

local function safeTarget(path)
  if type(path) ~= "string" or #path > 160 or not path:match("^/[%w%._/-]+$") or
    path:find("..", 1, true) or path:find("//", 1, true) or path:sub(-1) == "/" then
    return false
  end
  if path:sub(1, #RECOVERY + 1) == RECOVERY .. "/" then return false end
  return path == "/init.lua" or path:sub(1,7) == "/idkos/"
end

paint("loading update manifest", "connecting to github...")
local imageSource, imageReason = fetch(BASE .. "image.lua", 128 * 1024)
if not imageSource then error("manifest download failed: " .. tostring(imageReason), 0) end

local imageChunk, imageSyntax = load(imageSource, "=image.lua", "t", {})
if not imageChunk then error("manifest syntax: " .. tostring(imageSyntax), 0) end

local imageOk, image = pcall(imageChunk)
if not imageOk then error("manifest execution failed: " .. tostring(image), 0) end
if type(image) ~= "table" or type(image.files) ~= "table" then
  error("invalid update manifest", 0)
end
if #image.files < 1 or #image.files > 128 then
  error("invalid update file count", 0)
end

local entries, seenTargets = {}, {}
for _, item in ipairs(image.files) do
  if type(item) ~= "table" or not safeSource(item.source) or
    not safeTarget(item.target) or seenTargets[item.target] then
    error("unsafe update manifest entry", 0)
  end
  seenTargets[item.target] = true
  entries[#entries + 1] = {source=item.source,target=item.target}
end

table.sort(entries, function(a,b)
  if a.target == "/init.lua" then return false end
  if b.target == "/init.lua" then return true end
  return a.target < b.target
end)

local cleanedStage, cleanedStageReason = removeTree(STAGE)
if not cleanedStage then
  error("cannot clean staging directory: " .. tostring(cleanedStageReason), 0)
end
local cleanedBackup, cleanedBackupReason = removeTree(BACKUP)
if not cleanedBackup then
  error("cannot clean backup directory: " .. tostring(cleanedBackupReason), 0)
end
local stageMade, stageReason = mkdirp(STAGE)
if not stageMade then error("cannot create staging directory: " .. tostring(stageReason), 0) end

local total = 0
for index, item in ipairs(entries) do
  paint("downloading system files",
    string.format("%d/%d  %s", index, #entries, item.source),
    (index - 1) / #entries)

  local data, reason = fetch(BASE .. item.source, MAX_FILE)
  if not data then
    removeTree(STAGE)
    error(item.source .. ": " .. tostring(reason), 0)
  end

  total = total + #data
  if total > MAX_TOTAL then
    removeTree(STAGE)
    error("update exceeds total size limit", 0)
  end

  if item.source:sub(-4) == ".lua" then
    local chunk, syntaxError = load(data, "=" .. item.source, "t", {})
    if not chunk then
      removeTree(STAGE)
      error(item.source .. ": " .. tostring(syntaxError), 0)
    end
  end

  local written, writeReason = writeFile(STAGE .. item.target, data)
  if not written then
    removeTree(STAGE)
    error("staging " .. item.target .. ": " .. tostring(writeReason), 0)
  end
end

local existed = {}
for index, item in ipairs(entries) do
  paint("backing up installed system",
    string.format("%d/%d  %s", index, #entries, item.target),
    index / #entries)

  existed[item.target] = boot.exists(item.target)
  if existed[item.target] then
    local old, reason = readFile(item.target)
    if not old then
      removeTree(STAGE)
      removeTree(BACKUP)
      error("backup " .. item.target .. ": " .. tostring(reason), 0)
    end
    local saved, saveReason = writeFile(BACKUP .. item.target, old)
    if not saved then
      removeTree(STAGE)
      removeTree(BACKUP)
      error("backup " .. item.target .. ": " .. tostring(saveReason), 0)
    end
  end
end

local applied = {}
local applyError

for index, item in ipairs(entries) do
  paint("applying update",
    string.format("%d/%d  %s", index, #entries, item.target),
    index / #entries)

  applied[#applied + 1] = item.target
  local data, reason = readFile(STAGE .. item.target)
  if not data then
    applyError = "read staged " .. item.target .. ": " .. tostring(reason)
    break
  end

  local written, writeReason = writeAtomic(item.target, data)
  if not written then
    applyError = "write " .. item.target .. ": " .. tostring(writeReason)
    break
  end
end

if applyError then
  paint("update failed - rolling back", applyError)
  local rollbackErrors = {}

  for index = #applied, 1, -1 do
    local target = applied[index]
    if existed[target] then
      local old, reason = readFile(BACKUP .. target)
      if not old then
        rollbackErrors[#rollbackErrors + 1] = target .. ": " .. tostring(reason)
      else
        local restored, restoreReason = writeAtomic(target, old)
        if not restored then
          rollbackErrors[#rollbackErrors + 1] = target .. ": " .. tostring(restoreReason)
        end
      end
    else
      local removed, removeReason = removeTree(target)
      if not removed then
        rollbackErrors[#rollbackErrors + 1] = target .. ": " .. tostring(removeReason)
      end
    end
  end

  removeTree(STAGE)
  if #rollbackErrors == 0 then removeTree(BACKUP) end

  local suffix
  if #rollbackErrors > 0 then
    suffix = "; rollback errors: " .. table.concat(rollbackErrors, ", ") ..
      "; backup retained at " .. BACKUP
  else
    suffix = "; previous files restored"
  end

  error(applyError .. suffix, 0)
end

removeTree(STAGE)
removeTree(BACKUP)
writeFile(RECOVERY .. "/last-update.log",
  string.format("updated %d files, %d bytes\n", #entries, total))

paint("update complete", string.format("%d files updated - rebooting", #entries), 1)
rawComputer.pullSignal(1.5)
rawComputer.shutdown(true)
