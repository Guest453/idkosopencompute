-- idk recovery bridge v1
local rawComponent, rawComputer = component, computer

local function proxyComponent(value)
  if type(value) == "string" then
    local ok, proxy = pcall(rawComponent.proxy, value)
    if ok and proxy then return proxy, value end
  elseif type(value) == "table" or type(value) == "userdata" then
    local address
    pcall(function() address = value.address end)
    return value, address
  end
  return nil
end

local function listedComponent(kind, exact)
  local ok, result
  if exact == nil then ok, result = pcall(rawComponent.list, kind)
  else ok, result = pcall(rawComponent.list, kind, exact) end
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
        if address then return address end
      end
    end
  end
  return nil
end

local function primary(kind)
  local directOk, direct = pcall(function() return rawComponent[kind] end)
  if directOk and direct then
    local proxy, address = proxyComponent(direct)
    if proxy then return proxy, address end
  end
  return proxyComponent(listedComponent(kind, nil) or listedComponent(kind, true))
end

local function bootFilesystem()
  local ok, address = pcall(rawComputer.getBootAddress)
  if ok and address then
    local proxyOk, proxy = pcall(rawComponent.proxy, address)
    if proxyOk and proxy then return proxy end
  end
  local listedOk, result = pcall(rawComponent.list, "filesystem")
  if not listedOk then result = nil end
  if type(result) == "function" then
    while true do
      local nextOk, candidate = pcall(result)
      if not nextOk or not candidate then break end
      local proxyOk, proxy = pcall(rawComponent.proxy, candidate)
      if proxyOk and proxy then
        local existsOk, exists = pcall(proxy.exists, "/idkos/recovery/original_init.lua")
        if existsOk and exists then return proxy end
      end
    end
  elseif type(result) == "string" then
    local proxyOk, proxy = pcall(rawComponent.proxy, result)
    if proxyOk and proxy then
      local existsOk, exists = pcall(proxy.exists, "/idkos/recovery/original_init.lua")
      if existsOk and exists then return proxy end
    end
  elseif type(result) == "table" then
    for key, value in pairs(result) do
      local candidate = type(key) == "string" and key or value
      if type(candidate) == "string" then
        local proxyOk, proxy = pcall(rawComponent.proxy, candidate)
        if proxyOk and proxy then
          local existsOk, exists = pcall(proxy.exists, "/idkos/recovery/original_init.lua")
          if existsOk and exists then return proxy end
        end
      end
    end
  end
  return nil
end

local function readFile(fs, path)
  local handle, reason = fs.open(path, "r")
  if not handle then return nil, reason end
  local parts = {}
  while true do
    local data, readReason = fs.read(handle, 2048)
    if data == nil then
      fs.close(handle)
      if readReason then return nil, readReason end
      return table.concat(parts)
    end
    parts[#parts + 1] = data
  end
end

local function showFailure(message)
  local gpu = primary("gpu")
  local screen = primary("screen")
  if gpu then
    local screenOk, current = pcall(gpu.getScreen)
    if screen and (not screenOk or not current) then pcall(gpu.bind, screen) end
    local ok, width, height = pcall(gpu.getResolution)
    if ok and type(width) == "number" and type(height) == "number" then
      pcall(gpu.setBackground, 0x000000)
      pcall(gpu.setForeground, 0xffffff)
      pcall(gpu.fill, 1, 1, width, height, " ")
      local text = "idk recovery failed:\n" .. tostring(message) .. "\n\npress a key or touch to reboot"
      local y = 1
      for line in text:gmatch("[^\n]+") do
        local offset = 1
        repeat
          pcall(gpu.set, 1, y, line:sub(offset, offset + width - 1))
          offset, y = offset + width, y + 1
        until offset > #line or y > height
        if y > height then break end
      end
    end
  end
  while true do
    local name = rawComputer.pullSignal()
    if name == "key_down" or name == "touch" then break end
  end
  rawComputer.shutdown(true)
end

local boot = bootFilesystem()
if not boot then return showFailure("boot filesystem is unavailable") end

local marker = "/idkos/recovery/next_boot"
local markerOk, recoveryRequested = pcall(boot.exists, marker)
if markerOk and recoveryRequested then
  pcall(boot.remove, marker)
  local source, reason = readFile(boot, "/idkos/recovery/updater.lua")
  if not source then return showFailure("cannot read updater: " .. tostring(reason)) end
  local chunk, syntaxError = load(source, "=/idkos/recovery/updater.lua", "t", _G)
  if not chunk then return showFailure(syntaxError) end
  local ok, result = xpcall(function() return chunk(boot) end, function(errorValue)
    if debug and debug.traceback then return debug.traceback(errorValue, 2) end
    return tostring(errorValue)
  end)
  if not ok then return showFailure(result) end
  return result
end

local source, reason = readFile(boot, "/idkos/recovery/original_init.lua")
if not source then return showFailure("cannot read original init: " .. tostring(reason)) end
local chunk, syntaxError = load(source, "=/init.lua", "t", _G)
if not chunk then return showFailure(syntaxError) end
return chunk()
