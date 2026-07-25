local ui = dofile("/idkos/system/ui.lua")
local unicode = require("unicode")

local sourceIcon = ui.icon
local sourceImage = ui.image
local sourceRenderer = ui.renderer
local cache = {}

local sprites = {}
pcall(function()
  local loaded = dofile("/idkos/system/sprites.lua")
  if type(loaded) == "table" then sprites = loaded end
end)

local function paletteIndex(character)
  if character == "." or character == nil or character == "" then return nil end
  local number = tonumber(character)
  if number then return number end
  local byte = character:byte()
  if byte and byte >= 65 and byte <= 90 then return byte - 55 end
  return nil
end

local function sourceColor(sprite, x, y)
  if x < 1 or y < 1 or x > sprite.width or y > sprite.height then return nil end
  local row = sprite.rows[y]
  if type(row) ~= "string" then return nil end
  local index = paletteIndex(row:sub(x, x))
  return index and sprite.palette[index] or nil
end

local function sampleNearest(sprite, outputX, outputY, outputWidth, outputHeight)
  local sourceX = math.min(sprite.width, math.max(1, math.floor((outputX - 0.5) * sprite.width / outputWidth) + 1))
  local sourceY = math.min(sprite.height, math.max(1, math.floor((outputY - 0.5) * sprite.height / outputHeight) + 1))
  return sourceColor(sprite, sourceX, sourceY)
end

local function sampleCoverage(sprite, outputX, outputY, outputWidth, outputHeight)
  local x1 = math.floor((outputX - 1) * sprite.width / outputWidth) + 1
  local x2 = math.max(x1, math.ceil(outputX * sprite.width / outputWidth))
  local y1 = math.floor((outputY - 1) * sprite.height / outputHeight) + 1
  local y2 = math.max(y1, math.ceil(outputY * sprite.height / outputHeight))
  local counts, winner, winnerCount = {}, nil, 0
  for sourceY = y1, math.min(sprite.height, y2) do
    for sourceX = x1, math.min(sprite.width, x2) do
      local color = sourceColor(sprite, sourceX, sourceY)
      if color then
        counts[color] = (counts[color] or 0) + 1
        if counts[color] > winnerCount then
          winner, winnerCount = color, counts[color]
        end
      end
    end
  end
  return winner
end

local function iconWidth(size)
  if size == "small" or size == "mini" or tonumber(size) == 3 then return 4 end
  if size == "dock" then return 6 end
  if size == "large" then return 8 end
  return 6
end

local function packPixels(width, height, sampler)
  local image = {
    width = width,
    height = math.ceil(height / 2),
    cells = {},
    pixelSprite = true
  }
  for pixelY = 1, height, 2 do
    local cellY = math.floor((pixelY + 1) / 2)
    for pixelX = 1, width do
      local upper = sampler(pixelX, pixelY)
      local lower = pixelY + 1 <= height and sampler(pixelX, pixelY + 1) or nil
      if upper or lower then
        image.cells[(cellY - 1) * width + pixelX] = {upper = upper, lower = lower}
      end
    end
  end
  return image
end

local function renderSprite(sprite, size)
  local width = iconWidth(size)
  local height = width
  local sampler = sprite.mode == "coverage" and sampleCoverage or sampleNearest
  return packPixels(width, height, function(x, y)
    return sampler(sprite, x, y, width, height)
  end)
end

local function legacyColor(image, outputX, outputY, outputWidth)
  if type(image) ~= "table" or type(image.cells) ~= "table" then return nil end
  local sourceWidth = math.max(1, tonumber(image.width) or 1)
  local sourceHeight = math.max(1, tonumber(image.height) or 1)
  local sourceX = math.min(sourceWidth, math.max(1, math.floor((outputX - 0.5) * sourceWidth / outputWidth) + 1))
  local sourceY = math.min(sourceHeight, math.max(1, math.floor((outputY - 0.5) * sourceHeight / outputWidth) + 1))
  local cell = image.cells[(sourceY - 1) * sourceWidth + sourceX]
  if type(cell) ~= "table" then return nil end
  return tonumber(cell.bg) or tonumber(cell.fg)
end

local function renderLegacy(name, color, size)
  local width = iconWidth(size)
  local sourceSize = (size == "small" or size == "mini" or tonumber(size) == 3) and "small" or nil
  local image = sourceIcon(name, color, sourceSize)
  return packPixels(width, width, function(x, y)
    return legacyColor(image, x, y, width)
  end)
end

function ui.icon(name, color, size)
  name = tostring(name or "app"):lower()
  if name == "files" then name = "finder" end

  local spriteName = name
  if name == "idkstart" or name == "startbutton" then spriteName = "start" end

  local key = name .. ":" .. tostring(color or "") .. ":" .. tostring(size or "full")
  if cache[key] then return cache[key] end

  local image
  if sprites[spriteName] then
    image = renderSprite(sprites[spriteName], size)
  else
    image = renderLegacy(name, color, size)
  end

  cache[key] = image
  return image
end

function ui.image(gpu, x, y, image, baseBackground)
  if type(image) == "table" and image.pixelSprite and type(image.cells) == "table" then
    local base = tonumber(baseBackground) or tonumber(gpu.bg) or 0x000000
    for cellY = 1, image.height do
      for cellX = 1, image.width do
        local cell = image.cells[(cellY - 1) * image.width + cellX]
        if cell then
          local upper = cell.upper or base
          local lower = cell.lower or base
          if type(gpu.semi) == "function" then
            gpu.semi(x + cellX - 1, y + cellY - 1, upper, lower)
          else
            local color = cell.upper or cell.lower or base
            gpu.cell(x + cellX - 1, y + cellY - 1, " ", color, color)
          end
        end
      end
    end
    return
  end
  return sourceImage(gpu, x, y, image)
end

function ui.renderer(gpu, width, height, mirrors, mirrorFailed)
  local renderer = sourceRenderer(gpu, width, height, mirrors, mirrorFailed)
  local sourceCell = renderer.cell
  local sourceFill = renderer.fill

  function renderer.cell(x, y, character, foreground, background)
    if (character == "+" or character == ".") and foreground == 0x4e8296 then
      character = " "
    elseif character == "~" and foreground == 0x2a6a80 then
      character = " "
    elseif (character == "/" or character == "\\") and foreground == 0xe9f2f8 then
      character = " "
    elseif character == "|" and foreground == 0x60798b and background == 0x8ca4b5 then
      character = " "
    elseif character == "." and foreground == 0xffffff and background == 0x3e5568 then
      character, background = " ", 0xffffff
    elseif character == "o" and (background == 0xe45b67 or background == 0xf1b94e or background == 0x51b77a) then
      character = " "
    end
    return sourceCell(x, y, character, foreground, background)
  end

  function renderer.fill(x, y, fillWidth, fillHeight, character)
    if y >= renderer.height - 2 and fillWidth > 8 then
      if renderer.bg == 0xd9e8f2 or renderer.bg == 0x8ca4b5 or renderer.bg == 0x3e5568 then
        x = x + 1
        fillWidth = math.max(1, fillWidth - 2)
      end
    elseif y == renderer.height - 3 and renderer.bg == 0x071822 and fillWidth > 8 then
      return
    end
    return sourceFill(x, y, fillWidth, fillHeight, character)
  end

  return renderer
end

function ui.button(gpu, x, y, width, label, active, activeBg, inactiveBg)
  if width < 1 then return end
  label = unicode.sub(tostring(label or ""), 1, math.max(0, width - 2))
  local background = active and (activeBg or 0x3188c9) or (inactiveBg or 0xdce6ed)
  local foreground = active and 0xffffff or 0x21384a
  ui.fill(gpu, x, y, width, 1, background, " ")
  ui.center(gpu, x, y, width, label, foreground, background)
end

function ui.rule(gpu, x, y, width, color, background)
  if width < 1 then return end
  ui.fill(gpu, x, y, width, 1, color or background or 0x91a5b5, " ")
end

return ui
