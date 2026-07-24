local rawComponent, rawComputer = component, computer

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
  if type(address) == "string" then
    local ok, a, b, c = pcall(function()
      return rawComponent.invoke(address, method, table.unpack(args, 1, args.n))
    end)
    if ok then return true, a, b, c end
  end

  local methodOk, fn = pcall(function() return proxy and proxy[method] end)
  if methodOk and fn ~= nil then
    local ok, a, b, c = pcall(function()
      return fn(table.unpack(args, 1, args.n))
    end)
    if ok then return true, a, b, c end

    local selfOk, sa, sb, sc = pcall(function()
      return fn(proxy, table.unpack(args, 1, args.n))
    end)
    if selfOk then return true, sa, sb, sc end
  end

  return false
end

local display, displayAddress = primary("gpu")
local _, screenAddress = primary("screen")
local screenWidth, screenHeight

local function gpuCall(method, ...)
  return invokeComponent(display, displayAddress, method, ...)
end

local function setupDisplay()
  if not display and not displayAddress then return false end

  local screenOk, boundScreen = gpuCall("getScreen")
  if screenAddress and (not screenOk or not boundScreen) then
    gpuCall("bind", screenAddress)
  end

  local resolutionOk, width, height = gpuCall("getResolution")
  if not resolutionOk or type(width) ~= "number" or type(height) ~= "number" then
    return false
  end

  screenWidth, screenHeight = width, height
  return true
end

setupDisplay()

local splash = {}
local rainbow = {
  0xff4f70, 0xff8a3d, 0xffd84d, 0x58df78,
  0x45c7ff, 0x7d72ff, 0xd85cff
}
local ascii = {
  "  ___ ____  _  __   ___  ____  ",
  " |_ _|  _ \\| |/ /  / _ \\/ ___| ",
  "  | || | | | ' /  | | | \\___ \\ ",
  "  | || |_| | . \\  | |_| |___) |",
  " |___|____/|_|\\_\\  \\___/|____/ "
}
local compactAscii = {
  "  ___ ___  _  __ ",
  " |_ _|   \\| |/ / ",
  "  | || |\\ | ' /  ",
  " |___|_| \\|_|\\_\\ "
}

local function centerX(text)
  return math.max(1, math.floor((screenWidth - #text) / 2) + 1)
end

local function splashFrame(frame, status)
  if not screenWidth or not screenHeight then return end

  local art = (screenWidth >= 35 and screenHeight >= 12) and ascii or compactAscii
  local baseY = math.max(2, math.floor((screenHeight - #art) / 2) - 1)
  local floatX = math.floor(math.sin(frame / 7) * 2)
  local floatY = math.floor(math.sin(frame / 11))
  local background = 0x08131f

  gpuCall("setBackground", background)
  gpuCall("setForeground", 0xffffff)
  gpuCall("fill", 1, 1, screenWidth, screenHeight, " ")

  local stars = math.min(18, math.max(4, math.floor(screenWidth / 4)))
  for index = 1, stars do
    local x = 1 + ((index * 17 + frame) % math.max(1, screenWidth))
    local y = 1 + ((index * 11 + math.floor(frame / 3)) % math.max(1, screenHeight))
    gpuCall("setForeground", rainbow[((index + frame) % #rainbow) + 1])
    gpuCall("set", x, y, (index + frame) % 3 == 0 and "+" or ".")
  end

  for lineIndex, line in ipairs(art) do
    local x = math.max(1, math.min(screenWidth - #line + 1, centerX(line) + floatX))
    local y = baseY + lineIndex - 1 + floatY
    if y >= 1 and y <= screenHeight then
      gpuCall("setForeground", rainbow[((frame + lineIndex - 2) % #rainbow) + 1])
      gpuCall("set", x, y, line:sub(1, math.max(1, screenWidth - x + 1)))
    end
  end

  local statusText = tostring(status or "starting idk os")
  statusText = statusText:sub(1, math.max(1, screenWidth - 4))
  local statusY = math.max(1, screenHeight - 3)
  gpuCall("setForeground", 0xd8e8f5)
  gpuCall("set", centerX(statusText), statusY, statusText)

  local barWidth = math.max(7, math.min(screenWidth - 8, 42))
  local barX = math.max(1, math.floor((screenWidth - barWidth) / 2) + 1)
  local barY = math.max(1, screenHeight - 1)
  local head = (frame % barWidth) + 1

  for part = 1, #rainbow do
    local start = math.floor((part - 1) * barWidth / #rainbow) + 1
    local finish = math.floor(part * barWidth / #rainbow)
    local chars = {}
    for offset = start, finish do
      local distance = (offset - head) % barWidth
      chars[#chars + 1] = distance < math.max(2, math.floor(barWidth / 5)) and "=" or "-"
    end
    gpuCall("setForeground", rainbow[((part + math.floor(frame / 2) - 2) % #rainbow) + 1])
    gpuCall("set", barX + start - 1, barY, table.concat(chars))
  end
end

function splash.animate(status, seconds)
  if not screenWidth or not screenHeight then return end
  local fps = 60
  local frames = math.max(1, math.floor((tonumber(seconds) or 0.8) * fps))
  local started = rawComputer.uptime()

  for frame = 0, frames - 1 do
    splashFrame(frame, status)
    local target = started + (frame + 1) / fps
    while rawComputer.uptime() < target do
      local remaining = target - rawComputer.uptime()
      pcall(function() rawComputer.pullSignal(remaining) end)
    end
  end
end

function splash.status(status)
  splashFrame(math.floor(rawComputer.uptime() * 60), status)
end

local function emergency(message, filesystem)
  message = tostring(message)
  if filesystem then
    pcall(function()
      local handle = filesystem.open("/idkos/crash.log", "w")
      if handle then
        filesystem.write(handle, message:sub(1, 16384))
        filesystem.close(handle)
      end
    end)
  end

  if setupDisplay() then
    gpuCall("setBackground", 0x000000)
    gpuCall("setForeground", 0xffffff)
    gpuCall("fill", 1, 1, screenWidth, screenHeight, " ")

    local y = 1
    local text = message .. "\n\npress a key or touch the screen to reboot."
    for line in text:gmatch("[^\n]+") do
      local offset = 1
      repeat
        gpuCall("set", 1, y, line:sub(offset, offset + screenWidth - 1))
        offset = offset + screenWidth
        y = y + 1
      until offset > #line or y > screenHeight
      if y > screenHeight then break end
    end
  end

  while true do
    local signalOk, name = pcall(function() return rawComputer.pullSignal() end)
    if not signalOk or name == "key_down" or name == "touch" then break end
  end
  pcall(function() rawComputer.shutdown(true) end)
end

local function traceback(reason)
  if debug and debug.traceback then return debug.traceback(reason, 2) end
  return tostring(reason)
end

splash.animate("probing hardware", 0.85)
splash.status("locating boot disk")

local addressOk, bootAddress = pcall(function()
  return rawComputer.getBootAddress()
end)
if not addressOk or not bootAddress then
  return emergency("idk os cannot find its boot filesystem: " .. tostring(bootAddress))
end

local proxyOk, boot = pcall(function()
  return rawComponent.proxy(bootAddress)
end)
if not proxyOk or not boot then
  return emergency("idk os cannot open its boot filesystem: " .. tostring(boot))
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

splash.status("loading standalone runtime")
local source, reason = readFile("/idkos/system/runtime.lua")
if not source then
  return emergency("cannot read standalone runtime: " .. tostring(reason), boot)
end

local chunk, syntaxError = load(source, "=/idkos/system/runtime.lua", "t", _G)
if not chunk then
  return emergency("cannot load standalone runtime: " .. tostring(syntaxError), boot)
end

local loaded, runtime = xpcall(chunk, traceback)
if not loaded or type(runtime) ~= "table" or
  type(runtime.install) ~= "function" or type(runtime.fatal) ~= "function" then
  return emergency("invalid standalone runtime: " .. tostring(runtime), boot)
end

splash.status("launching desktop")
local ok, bootError = xpcall(function()
  runtime.install(boot)
  dofile("/idkos/boot.lua")
end, traceback)

if not ok then
  local fatalOk = pcall(runtime.fatal, "idk os crashed:\n" .. tostring(bootError))
  if not fatalOk then emergency("idk os crashed:\n" .. tostring(bootError), boot) end
else
  pcall(function() rawComputer.shutdown(false) end)
end
