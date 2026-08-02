local component = require("component")
local computer = require("computer")
local filesystem = require("filesystem")

local function primary(kind)
  local ok, direct = pcall(function() return component[kind] end)
  if ok and direct then return direct end

  for _, exact in ipairs({false, true}) do
    local listedOk, listed
    if exact then listedOk, listed = pcall(component.list, kind, true)
    else listedOk, listed = pcall(component.list, kind) end
    if listedOk then
      local address
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
        end
      end
      if address then
        local proxyOk, proxy = pcall(component.proxy, address)
        if proxyOk and proxy then return proxy end
      end
    end
  end
end

local function call(proxy, method, ...)
  if not proxy then return nil end
  local ok, fn = pcall(function() return proxy[method] end)
  if not ok or type(fn) ~= "function" then return nil end
  local result = {pcall(fn, ...)}
  if result[1] then return table.unpack(result, 2) end
  result = {pcall(fn, proxy, ...)}
  if result[1] then return table.unpack(result, 2) end
end

local function wrap(text, width)
  local lines = {}
  for raw in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    if raw == "" then
      lines[#lines + 1] = ""
    else
      local position = 1
      while position <= #raw do
        lines[#lines + 1] = raw:sub(position, position + width - 1)
        position = position + width
      end
    end
  end
  return lines
end

local function panicCode(message)
  local value = math.floor((computer.uptime() or 0) * 1000) % 0xffffff
  for index = 1, #message do value = (value * 33 + message:byte(index)) % 0xffffff end
  return string.format("%06X", value)
end

return function(message, context)
  message = tostring(message or "unknown kernel fault")
  context = type(context) == "table" and context or {}

  pcall(function()
    filesystem.makeDirectory("/idkos")
    local file = filesystem.open("/idkos/crash.log", "w")
    if file then
      file:write("idk os kernel panic\n")
      file:write("panic code: " .. panicCode(message) .. "\n")
      file:write("uptime: " .. tostring(computer.uptime()) .. "\n")
      file:write("phase: " .. tostring(context.phase or "kernel") .. "\n\n")
      file:write(message:sub(1, 32768))
      file:close()
    end
  end)

  local gpu = primary("gpu")
  local screen = primary("screen")
  local width, height = 80, 25
  if gpu then
    local bound = call(gpu, "getScreen")
    if screen and not bound then call(gpu, "bind", screen.address or screen) end
    local w, h = call(gpu, "getResolution")
    if type(w) == "number" and type(h) == "number" then width, height = w, h end
    call(gpu, "setBackground", 0x000000)
    call(gpu, "setForeground", 0xffffff)
    call(gpu, "fill", 1, 1, width, height, " ")

    local free = select(2, pcall(computer.freeMemory))
    local total = select(2, pcall(computer.totalMemory))
    local header = {
      "IDK OS KERNEL PANIC",
      "the graphical shell has been terminated.",
      "panic code: " .. panicCode(message),
      "phase: " .. tostring(context.phase or "kernel"),
      "uptime: " .. string.format("%.2f seconds", tonumber(computer.uptime()) or 0),
      "memory: " .. tostring(free or "?") .. " free / " .. tostring(total or "?") .. " total",
      "crash log: /idkos/crash.log",
      "",
      "reason:"
    }

    local y = 1
    call(gpu, "setForeground", 0xff6b6b)
    call(gpu, "set", 1, y, header[1]:sub(1, width)); y = y + 2
    call(gpu, "setForeground", 0xffffff)
    for index = 2, #header do
      if y > height - 3 then break end
      call(gpu, "set", 1, y, header[index]:sub(1, width))
      y = y + 1
    end

    for _, line in ipairs(wrap(message, width)) do
      if y > height - 3 then break end
      call(gpu, "set", 1, y, line)
      y = y + 1
    end

    call(gpu, "setForeground", 0xb8c7d1)
    call(gpu, "set", 1, math.max(1, height - 1), ("press r or touch to reboot; press h to halt"):sub(1, width))
  end

  local reboot = true
  while true do
    local signal = table.pack(computer.pullSignal())
    if signal[1] == "touch" then break end
    if signal[1] == "key_down" then
      local char = tonumber(signal[3])
      if char == string.byte("h") or char == string.byte("H") then reboot = false end
      break
    end
  end
  computer.shutdown(reboot)
end
