local runtime = {}
local rawComponent, rawComputer, rawUnicode = component, computer, unicode
local boot, gpu, cursorY, screenWidth, screenHeight

local function primary(kind)
  local listed, iterator = pcall(rawComponent.list, kind, true)
  if not listed or type(iterator) ~= "function" then return nil end
  local addressOk, address = pcall(iterator)
  if not addressOk or not address then return nil end
  local proxyOk, proxy = pcall(rawComponent.proxy, address)
  if proxyOk and proxy then return proxy,address end
  return nil
end

local function setupConsole()
  gpu = primary("gpu")
  if not gpu then return end
  local _, screen = primary("screen")
  local boundOk, bound = pcall(gpu.getScreen)
  if screen and (not boundOk or not bound) then pcall(gpu.bind, screen) end
  local ok, width, height = pcall(gpu.getResolution)
  if not ok or type(width) ~= "number" or type(height) ~= "number" then gpu = nil return end
  screenWidth, screenHeight, cursorY = width, height, 1
end

local function consoleWrite(value)
  if not gpu then return true end
  value = tostring(value)
  local function writeLine(line)
    if line == "" then cursorY = cursorY + 1 return end
    local offset = 1
    while offset <= #line do
      if cursorY > screenHeight then pcall(gpu.copy, 1, 2, screenWidth, screenHeight - 1, 0, -1); cursorY = screenHeight end
      pcall(gpu.fill, 1, cursorY, screenWidth, 1, " ")
      pcall(gpu.set, 1, cursorY, line:sub(offset, offset + screenWidth - 1))
      offset, cursorY = offset + screenWidth, cursorY + 1
    end
  end
  local start = 1
  while true do
    local newline = value:find("\n", start, true)
    if not newline then
      if start <= #value then writeLine(value:sub(start)) end
      break
    end
    writeLine(value:sub(start, newline - 1))
    start = newline + 1
  end
  return true
end

local function canonical(path)
  local absolute = tostring(path):sub(1, 1) == "/"
  local parts = {}
  for part in tostring(path):gmatch("[^/]+") do
    if part == ".." then table.remove(parts)
    elseif part ~= "." and part ~= "" then parts[#parts + 1] = part end
  end
  local result = table.concat(parts, "/")
  return absolute and ("/" .. result) or result
end

local fs = {}
function fs.canonical(path) return canonical(path) end
function fs.concat(...) return canonical(table.concat({...}, "/")) end
function fs.path(path)
  path = canonical(path)
  if path == "/" then return "/" end
  return path:match("^(.*)/[^/]*$") or ""
end
function fs.name(path) return canonical(path):match("([^/]+)$") end
function fs.exists(path) return boot.exists(canonical(path)) end
function fs.isDirectory(path) return boot.isDirectory(canonical(path)) end
function fs.size(path) return boot.size(canonical(path)) end
function fs.spaceTotal() return boot.spaceTotal() end
function fs.spaceUsed() return boot.spaceUsed() end
function fs.isReadOnly() return boot.isReadOnly() end
function fs.get(path) return boot, "/" end
function fs.mounts()
  local returned = false
  return function()
    if returned then return nil end
    returned = true
    return boot, "/"
  end
end
function fs.makeDirectory(path) return boot.makeDirectory(canonical(path)) end
function fs.rename(from, to) return boot.rename(canonical(from), canonical(to)) end
function fs.list(path)
  local entries, reason = boot.list(canonical(path))
  if not entries then return nil, reason end
  local index = 0
  return function() index = index + 1; return entries[index] end
end
local function removeTree(path)
  if boot.isDirectory(path) then
    local entries, reason = boot.list(path)
    if not entries then return nil, reason end
    for _, name in ipairs(entries) do
      name = name:gsub("/$", "")
      local child = path == "/" and ("/" .. name) or (path .. "/" .. name)
      local ok, childReason = removeTree(child)
      if not ok then return nil, childReason end
    end
  end
  return boot.remove(path)
end
function fs.remove(path) return removeTree(canonical(path)) end
function fs.open(path, mode)
  local handle, reason = boot.open(canonical(path), mode or "r")
  if not handle then return nil, reason end
  local stream = {}
  function stream:close()
    if not handle then return nil, "file is closed" end
    local current = handle
    handle = nil
    return boot.close(current)
  end
  function stream:read(format)
    if not handle then return nil, "file is closed" end
    if type(format) == "number" then return boot.read(handle, format) end
    if format == nil or format == "*l" then
      local chars = {}
      while true do
        local char, readReason = boot.read(handle, 1)
        if not char then return #chars > 0 and table.concat(chars) or nil, readReason end
        if char == "\n" then return table.concat(chars) end
        chars[#chars + 1] = char
      end
    end
    if format == "*a" then
      local parts = {}
      while true do
        local data, readReason = boot.read(handle, 2048)
        if data == nil then
          if readReason then return nil, readReason end
          return table.concat(parts)
        end
        parts[#parts + 1] = data
      end
    end
    return nil, "unsupported read format"
  end
  function stream:write(...)
    if not handle then return nil, "file is closed" end
    for index = 1, select("#", ...) do
      local value = tostring(select(index, ...))
      local offset = 1
      while offset <= #value do
        local chunk = value:sub(offset, offset + 2047)
        local ok, writeReason = boot.write(handle, chunk)
        if not ok then return nil, writeReason end
        offset = offset + #chunk
      end
    end
    return self
  end
  function stream:lines()
    return function() return self:read("*l") end
  end
  return stream
end

local keyboard = {pressedCodes = {}, pressedChars = {}, keys = {q = 0x10, lcontrol = 0x1d, rcontrol = 0x9d}}
function keyboard.isControlDown() return keyboard.pressedCodes[keyboard.keys.lcontrol] or keyboard.pressedCodes[keyboard.keys.rcontrol] or false end
function keyboard.isKeyDown(value)
  return type(value) == "number" and keyboard.pressedCodes[value] or keyboard.pressedChars[value]
end
local event = {}
function event.pull(timeout)
  local signal = table.pack(rawComputer.pullSignal(timeout))
  if signal[1] == "key_down" then keyboard.pressedChars[signal[3]], keyboard.pressedCodes[signal[4]] = true, true
  elseif signal[1] == "key_up" then keyboard.pressedChars[signal[3]], keyboard.pressedCodes[signal[4]] = nil, nil end
  return table.unpack(signal, 1, signal.n)
end
event.push = rawComputer.pushSignal

local componentApi = {
  list = rawComponent.list, proxy = rawComponent.proxy, invoke = rawComponent.invoke,
  type = rawComponent.type, methods = rawComponent.methods, doc = rawComponent.doc,
  fields = rawComponent.fields, slot = rawComponent.slot
}
function componentApi.isAvailable(kind) return primary(kind) ~= nil end
setmetatable(componentApi, {__index = function(tableValue, kind)
  local value = primary(kind)
  rawset(tableValue, kind, value)
  return value
end})

local internet = {}
function internet.request(url, data, headers, method)
  local inet = primary("internet")
  if not inet then error("no internet card available", 2) end
  local request, reason = inet.request(url, data, headers, method)
  if not request then error(reason or "request failed", 2) end
  local wrapper = {close = request.close}
  return setmetatable(wrapper, {
    __index = request,
    __call = function()
      while true do
        local chunk, readReason = request.read()
        if chunk == nil then request.close(); if readReason then error(readReason, 2) end; return nil end
        if #chunk > 0 then return chunk end
        rawComputer.pullSignal(0.05)
      end
    end
  })
end

local modules = {component = componentApi, computer = rawComputer, unicode = rawUnicode,
  filesystem = fs, event = event, keyboard = keyboard, internet = internet}
local packageApi = {loaded = modules, preload = {}, path = "/idkos/system/?.lua;/idkos/?.lua"}
local function requireModule(name)
  if modules[name] ~= nil then return modules[name] end
  local path = name:gsub("%.", "/")
  for pattern in packageApi.path:gmatch("[^;]+") do
    local candidate = pattern:gsub("%?", path)
    if fs.exists(candidate) then
      local result = dofile(candidate)
      if result == nil then result = true end
      modules[name] = result
      return result
    end
  end
  error("module '" .. tostring(name) .. "' not found", 2)
end

function runtime.install(bootProxy)
  boot = bootProxy
  if not boot.exists("/home") then pcall(boot.makeDirectory, "/home") end
  setupConsole()
  _G.component, _G.computer, _G.unicode = componentApi, rawComputer, rawUnicode
  _G.package, _G.require = packageApi, requireModule
  _G.loadfile = function(path, mode, environment)
    local file, reason = fs.open(path, "r")
    if not file then return nil, reason end
    local source, readReason = file:read("*a")
    file:close()
    if not source then return nil, readReason end
    return load(source, "=" .. path, mode or "t", environment or _G)
  end
  _G.dofile = function(path)
    local chunk, reason = _G.loadfile(path, "t", _G)
    if not chunk then error(reason, 2) end
    return chunk()
  end
  local output = {write = function(_, ...) for i = 1, select("#", ...) do consoleWrite(select(i, ...)) end return true end}
  _G.io = {stdout = output, stderr = output, write = function(...) return output:write(...) end, open = function(...) return fs.open(...) end}
  _G.os = _G.os or {}
  _G.os.sleep = function(seconds) rawComputer.pullSignal(seconds or 0) end
  _G.os.exit = function() rawComputer.shutdown(false) end
end

function runtime.fatal(message)
  message = tostring(message)
  if boot then
    pcall(function()
      local handle = boot.open("/idkos/crash.log", "w")
      if handle then
        boot.write(handle, message:sub(1, 16384))
        boot.close(handle)
      end
    end)
  end
  setupConsole()
  if gpu then
    pcall(gpu.setBackground, 0x000000); pcall(gpu.setForeground, 0xffffff)
    pcall(gpu.fill, 1, 1, screenWidth, screenHeight, " "); cursorY = 1
  end
  consoleWrite(message .. "\n\npress a key or touch to reboot; press h to halt.\n")
  local reboot = true
  while true do
    local signal = table.pack(rawComputer.pullSignal())
    if signal[1] == "touch" then break end
    if signal[1] == "key_down" then
      reboot = signal[3] ~= string.byte("h") and signal[3] ~= string.byte("H")
      break
    end
  end
  rawComputer.shutdown(reboot)
end

return runtime
