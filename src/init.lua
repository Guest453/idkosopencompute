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

  pcall(function()
    local gpuAddress = component.list("gpu", true)()
    local screenAddress = component.list("screen", true)()
    local display = gpuAddress and component.proxy(gpuAddress)
    if not display then return end
    local screenOk, boundScreen = pcall(display.getScreen)
    if screenAddress and (not screenOk or not boundScreen) then pcall(display.bind, screenAddress) end
    local resolutionOk, width, height = pcall(display.getResolution)
    if not resolutionOk or type(width) ~= "number" or type(height) ~= "number" then return end
    pcall(display.setBackground, 0x000000)
    pcall(display.setForeground, 0xffffff)
    pcall(display.fill, 1, 1, width, height, " ")
    local y = 1
    for line in (message .. "\n\npress a key or touch the screen to reboot."):gmatch("[^\n]+") do
      local offset = 1
      repeat
        pcall(display.set, 1, y, line:sub(offset, offset + width - 1))
        offset, y = offset + width, y + 1
      until offset > #line or y > height
      if y > height then break end
    end
  end)

  while true do
    local signalOk, name = pcall(computer.pullSignal)
    if not signalOk or name == "key_down" or name == "touch" then break end
  end
  pcall(computer.shutdown, true)
end

local function traceback(reason)
  if debug and debug.traceback then return debug.traceback(reason, 2) end
  return tostring(reason)
end

local addressOk, bootAddress = pcall(computer.getBootAddress)
if not addressOk or not bootAddress then
  return emergency("idk os cannot find its boot filesystem: " .. tostring(bootAddress))
end
local proxyOk, boot = pcall(component.proxy, bootAddress)
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

local source, reason = readFile("/idkos/system/runtime.lua")
if not source then return emergency("cannot read standalone runtime: " .. tostring(reason), boot) end
local chunk, syntaxError = load(source, "=/idkos/system/runtime.lua", "t", _G)
if not chunk then return emergency("cannot load standalone runtime: " .. tostring(syntaxError), boot) end
local loaded, runtime = xpcall(chunk, traceback)
if not loaded or type(runtime) ~= "table" or type(runtime.install) ~= "function" or type(runtime.fatal) ~= "function" then
  return emergency("invalid standalone runtime: " .. tostring(runtime), boot)
end

local ok, bootError = xpcall(function()
  runtime.install(boot)
  dofile("/idkos/boot.lua")
end, traceback)
if not ok then
  local fatalOk = pcall(runtime.fatal, "idk os crashed:\n" .. tostring(bootError))
  if not fatalOk then emergency("idk os crashed:\n" .. tostring(bootError), boot) end
else
  pcall(computer.shutdown, false)
end
