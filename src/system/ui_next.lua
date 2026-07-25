local ui = dofile("/idkos/system/ui.lua")
local unicode = require("unicode")
local sourceIcon = ui.icon
local sourceImage = ui.image
local cache = {}

local sprites = {}
pcall(function()
  local loaded = dofile("/idkos/system/sprites.lua")
  if type(loaded) == "table" then sprites = loaded end
end)

local custom = {
  recoveryupdater = {{0x397fca,0xffffff,0x55d98b,0x173957},{".111.","12221","12321","12221",".111."},{{3,2,"^",2},{3,3,"|",2},{3,4,"v",3}}},
  blockmerge = {{0x394a62,0xf4c95d,0x68d391,0xffffff},{"11111","12231","12321","13221","11111"},{{2,2,"2",4},{4,2,"4",4},{2,4,"8",4},{4,4,"+",4}}},
  lightsout = {{0x17284a,0xffd84d,0x617487,0xffffff},{"11111","12121","11211","12121","11111"},{{3,3,"*",4}}},
  store = {{0x31a46d,0xffffff,0x8ce2bd,0x174d39},{".222.","21112","11111","13331",".111."},{{3,3,"+",2}}},
  terminal = {{0x172331,0x5ee0a4,0xeaf4ff},{"11111","12221","12221","12221","11111"},{{2,3,">",2},{4,3,"_",3}}},
  settings = {{0x60738a,0xaac1d4,0x45a8e8,0xffffff},{"1.1.1","11211","12321","11211","1.1.1"},{{3,3,"o",4}}},
  game = {{0x394a62,0x68d391,0xf36f76,0xffffff},{".111.","12221","12321","12421",".111."},{{2,3,"+",4},{4,3,"o",4}}}
}

local function makeImage(def, small, color)
  local palette = {table.unpack(def[1])}
  if type(color) == "number" and color >= 0 and color <= 0xffffff then palette[1] = color end
  local rows, glyphs = def[2], def[3] or {}
  local width, height = small and 3 or 5, small and 3 or 5
  local xs = small and {1,3,5} or {1,2,3,4,5}
  local ys = small and {1,3,5} or {1,2,3,4,5}
  local image = {width = width, height = height, cells = {}}
  for y = 1, height do
    for x = 1, width do
      local key = rows[ys[y]]:sub(xs[x], xs[x])
      local paletteIndex = tonumber(key)
      if paletteIndex and palette[paletteIndex] then
        image.cells[(y - 1) * width + x] = {char = " ", fg = palette[paletteIndex], bg = palette[paletteIndex]}
      end
    end
  end
  if small then
    local glyph = glyphs[1]
    if glyph then
      local cell = image.cells[5] or {bg = palette[1]}
      image.cells[5] = {
        char = unicode.sub(tostring(glyph[3]), 1, 1),
        fg = palette[glyph[4]] or 0xffffff,
        bg = cell.bg or palette[1]
      }
    end
  else
    for _, glyph in ipairs(glyphs) do
      local x, y = glyph[1], glyph[2]
      if x >= 1 and x <= 5 and y >= 1 and y <= 5 then
        local index = (y - 1) * 5 + x
        local cell = image.cells[index] or {bg = palette[1]}
        image.cells[index] = {
          char = unicode.sub(tostring(glyph[3]), 1, 1),
          fg = palette[glyph[4]] or 0xffffff,
          bg = cell.bg or palette[1]
        }
      end
    end
  end
  return image
end

local function crop(image, small)
  if type(image) ~= "table" or type(image.cells) ~= "table" then return image end
  local xs, ys
  if small then
    xs = {1, math.max(1, math.ceil((image.width or 1) / 2)), image.width or 1}
    ys = {1, math.max(1, math.ceil((image.height or 1) / 2)), image.height or 1}
  else
    xs = {1, 2, math.max(1, math.ceil((image.width or 1) / 2)), math.max(1, (image.width or 1) - 1), image.width or 1}
    ys = {1, 2, math.max(1, math.ceil((image.height or 1) / 2)), math.max(1, (image.height or 1) - 1), image.height or 1}
  end
  local out = {width = #xs, height = #ys, cells = {}}
  for y, sourceY in ipairs(ys) do
    for x, sourceX in ipairs(xs) do
      out.cells[(y - 1) * out.width + x] = image.cells[(sourceY - 1) * (image.width or 1) + sourceX]
    end
  end
  return out
end

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

local function spriteWidth(size)
  if size == "small" or size == "mini" or tonumber(size) == 3 then return 4 end
  if size == "dock" then return 5 end
  if size == "large" then return 8 end
  return 5
end

local function renderSprite(sprite, size)
  local outputWidth = spriteWidth(size)
  local outputHeight = math.max(1, math.floor(outputWidth * sprite.height / sprite.width + 0.5))
  local image = {
    width = outputWidth,
    height = math.ceil(outputHeight / 2),
    cells = {},
    pixelSprite = true
  }
  local sampler = sprite.mode == "coverage" and sampleCoverage or sampleNearest
  for outputY = 1, outputHeight, 2 do
    local cellY = math.floor((outputY + 1) / 2)
    for outputX = 1, outputWidth do
      local upper = sampler(sprite, outputX, outputY, outputWidth, outputHeight)
      local lower = outputY + 1 <= outputHeight and sampler(sprite, outputX, outputY + 1, outputWidth, outputHeight) or nil
      if upper or lower then
        image.cells[(cellY - 1) * outputWidth + outputX] = {upper = upper, lower = lower}
      end
    end
  end
  return image
end

function ui.icon(name, color, size)
  name = tostring(name or "app"):lower()
  if name == "files" then name = "finder" end
  local spriteName = name
  if name == "launchpad" or name == "idkstart" or name == "startbutton" then spriteName = "start" end
  local small = size == "small" or size == "mini" or size == "dock" or tonumber(size) == 3
  local key = name .. ":" .. tostring(color or "") .. ":" .. tostring(size or "full")
  if cache[key] then return cache[key] end
  local image
  if sprites[spriteName] then
    image = renderSprite(sprites[spriteName], size)
  elseif custom[name] then
    image = makeImage(custom[name], small, color)
  else
    image = crop(sourceIcon(name, color, small and "small" or nil), small)
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
          local upper, lower = cell.upper or base, cell.lower or base
          if gpu.semiPixels and type(gpu.semi) == "function" then
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

function ui.button(gpu, x, y, width, label, active, activeBg, inactiveBg)
  if width < 1 then return end
  label = unicode.sub(tostring(label or ""), 1, math.max(0, width - 2))
  local background = active and (activeBg or 0x3188c9) or (inactiveBg or 0xdce6ed)
  local foreground = active and 0xffffff or 0x21384a
  ui.fill(gpu, x, y, width, 1, background, " ")
  if width >= 3 then
    gpu.cell(x, y, " ", foreground, background)
    gpu.cell(x + width - 1, y, " ", foreground, background)
  end
  ui.center(gpu, x, y, width, label, foreground, background)
end

function ui.rule(gpu, x, y, width, color, background)
  if width < 1 then return end
  ui.text(gpu, x, y, string.rep("-", width), color or 0x91a5b5, background)
end

return ui
