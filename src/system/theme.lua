local theme = {}
local CONFIG = "/home/.idkos/theme.cfg"

local function clamp(value)
  return math.max(0, math.min(255, math.floor(tonumber(value) or 0)))
end

local function rgb(color)
  color = math.floor(tonumber(color) or 0)
  return math.floor(color / 0x10000) % 0x100, math.floor(color / 0x100) % 0x100, color % 0x100
end

local function color(r, g, b)
  return clamp(r) * 0x10000 + clamp(g) * 0x100 + clamp(b)
end

local function readMode()
  local file = io.open(CONFIG, "r")
  if not file then return "light" end
  local value = tostring(file:read("*l") or ""):lower()
  file:close()
  return value == "dark" and "dark" or "light"
end

local function saturation(r, g, b)
  return math.max(r, g, b) - math.min(r, g, b)
end

local function luminance(r, g, b)
  return r * 0.299 + g * 0.587 + b * 0.114
end

local function darkBackground(value)
  local r, g, b = rgb(value)
  local lum = luminance(r, g, b)
  local sat = saturation(r, g, b)

  if sat < 34 then
    if lum >= 175 then
      local target = 22 + (255 - lum) * 0.12
      return color(target * 0.82, target * 0.94, target * 1.08)
    elseif lum >= 90 then
      local scale = 0.34
      return color(r * scale, g * scale, b * scale)
    else
      local scale = 0.78
      return color(r * scale, g * scale, b * scale)
    end
  end

  local scale
  if lum >= 190 then scale = 0.54
  elseif lum >= 110 then scale = 0.70
  else scale = 0.88 end
  return color(r * scale, g * scale, b * scale)
end

local function darkForeground(value)
  local r, g, b = rgb(value)
  local lum = luminance(r, g, b)
  local sat = saturation(r, g, b)

  if sat < 34 and lum < 170 then
    local target = 202 + lum * 0.18
    return color(target * 0.94, target, math.min(255, target * 1.06))
  end

  if lum < 85 then
    local boost = 1.75
    return color(math.max(104, r * boost), math.max(122, g * boost), math.max(138, b * boost))
  end

  return value
end

function theme.current()
  return readMode()
end

function theme.apply(ui)
  if type(ui) ~= "table" or type(ui.renderer) ~= "function" then return ui end

  local sourceRenderer = ui.renderer
  local sourceImage = ui.image

  function ui.renderer(gpu, width, height, mirrors, mirrorFailed)
    local renderer = sourceRenderer(gpu, width, height, mirrors, mirrorFailed)
    local sourceBeginFrame = renderer.beginFrame
    local sourceSetForeground = renderer.setForeground
    local sourceSetBackground = renderer.setBackground
    local sourceCell = renderer.cell
    local sourceSemi = renderer.semi
    local mode = readMode()
    local raw = false

    local function fg(value)
      if raw or mode ~= "dark" then return value end
      return darkForeground(value)
    end

    local function bg(value)
      if raw or mode ~= "dark" then return value end
      return darkBackground(value)
    end

    function renderer.beginFrame()
      mode = readMode()
      return sourceBeginFrame()
    end

    function renderer.setForeground(value)
      return sourceSetForeground(fg(value))
    end

    function renderer.setBackground(value)
      return sourceSetBackground(bg(value))
    end

    function renderer.cell(x, y, character, foreground, background)
      return sourceCell(x, y, character, foreground and fg(foreground), background and bg(background))
    end

    function renderer.semi(x, y, upper, lower)
      return sourceSemi(x, y, bg(upper), bg(lower))
    end

    function renderer.withRawColors(callback)
      local previous = raw
      raw = true
      local result = {pcall(callback)}
      raw = previous
      if not result[1] then error(result[2], 0) end
      return table.unpack(result, 2)
    end

    renderer.themeMode = function() return mode end
    return renderer
  end

  if type(sourceImage) == "function" then
    function ui.image(gpu, ...)
      if type(gpu) == "table" and type(gpu.withRawColors) == "function" then
        local arguments = {...}
        return gpu.withRawColors(function()
          return sourceImage(gpu, table.unpack(arguments))
        end)
      end
      return sourceImage(gpu, ...)
    end
  end

  return ui
end

return theme
