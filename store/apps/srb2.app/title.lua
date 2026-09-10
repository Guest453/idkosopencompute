-- title.lua - srb2's alacroix title screen, composed at run time.
--
-- srb2.pk3's SOC_TITL selects "TitlePicsMode = Alacroix", and f_finale.c drives
-- that screen off finalecount: the ribbon unfurls while the SONIC text animates,
-- ROBO BLAST 2 fades in from tic 10, the TWO drops from tic 16, the screen
-- flashes white at tic 30, and the characters take over from tic 41.  the same
-- timeline is reproduced here against TITLE.wad, which holds the real frames.
--
-- frames are decoded straight out of the wad string one at a time, so the whole
-- screen costs a few kilobytes of working memory rather than every frame at once.

local title = {}

local floor = math.floor
local byte = string.byte

local data, lumps, pal
local BLACK = 0

-- timings from f_finale.c
local FLASH_AT = 30
local FLASH_END = 34
local FADE_END = 44
local CHARSTART = 41
local SONICSTART, TAILSSTART, KNUXSTART = CHARSTART, CHARSTART + 27, CHARSTART + 44
title.LENGTH = CHARSTART + 40   -- the point the intro has fully settled

function title.open(path)
  local f = io.open(path, "rb")
  if not f then return nil, "cannot open " .. tostring(path) end
  data = f:read("*a")
  f:close()
  if type(data) ~= "string" or #data < 12 or data:sub(1, 4) ~= "PWAD" then
    data = nil
    return nil, "TITLE.wad is not a wad"
  end
  local function u32(o)
    local a, b, c, d = byte(data, o + 1, o + 4)
    return a + b * 256 + c * 65536 + d * 16777216
  end
  local n, dir = u32(4), u32(8)
  if dir + n * 16 > #data then data = nil return nil, "bad wad directory" end
  lumps = {}
  for i = 0, n - 1 do
    local p = dir + i * 16
    local nm = (data:sub(p + 9, p + 16):gsub("%z.*", ""))
    lumps[nm] = { pos = u32(p), size = u32(p + 4) }
  end
  local pl = lumps.PALETTE
  if not pl or pl.size < 768 then data = nil return nil, "TITLE.wad has no palette" end
  pal = {}
  for i = 0, 255 do
    local r, g, b = byte(data, pl.pos + i * 3 + 1, pl.pos + i * 3 + 3)
    pal[i] = r * 65536 + g * 256 + b
  end
  BLACK = pal[31]                       -- the fill f_finale uses before the flash
  return true
end

function title.close()
  data, lumps, pal = nil, nil, nil
end

-- blit one lump over the picture; byte 0 is transparent, as in the source art
local ox, oy = 0, 0
local function blit(px, W, H, name)
  local l = lumps[name]
  if not l then return end
  local o = l.pos
  local w = byte(data, o + 1) + byte(data, o + 2) * 256
  local h = byte(data, o + 3) + byte(data, o + 4) * 256
  local x0 = byte(data, o + 5) + byte(data, o + 6) * 256
  local y0 = byte(data, o + 7) + byte(data, o + 8) * 256
  if x0 >= 32768 then x0 = x0 - 65536 end
  if y0 >= 32768 then y0 = y0 - 65536 end
  x0, y0 = x0 + ox, y0 + oy
  local base = o + 8
  for y = 1, h do
    local ty = y0 + y
    if ty >= 1 and ty <= H then
      local rowbase = (ty - 1) * W
      local src = base + (y - 1) * w
      for x = 1, w do
        local tx = x0 + x
        if tx >= 1 and tx <= W then
          local v = byte(data, src + x)
          if v and v > 0 then px[rowbase + tx] = pal[v] end
        end
      end
    end
  end
end

local function frameName(prefix, i, count)
  if i < 1 then i = 1 elseif i > count then i = count end
  return string.format("%s%02d", prefix, i)
end

-- mix every pixel toward white, for the tic-30 flash and its fade
local function whiten(px, W, H, amount)
  if amount <= 0 then return end
  if amount > 1 then amount = 1 end
  local keep = 1 - amount
  local add = 255 * amount
  for i = 1, W * H do
    local c = px[i]
    local r = floor(c / 65536) % 256 * keep + add
    local g = floor(c / 256) % 256 * keep + add
    local b = c % 256 * keep + add
    px[i] = floor(r) * 65536 + floor(g) * 256 + floor(b)
  end
end

--- compose one tic of the title screen into a flat W*H pixel buffer.
-- the artwork is authored for a 112x70 picture, so on a roomier screen it is
-- centred rather than pinned to the corner.
title.ARTW, title.ARTH = 112, 70
function title.draw(px, W, H, tic)
  ox = math.max(0, math.floor((W - title.ARTW) / 2))
  oy = math.max(0, math.floor((H - title.ARTH) / 2))
  for i = 1, W * H do px[i] = BLACK end

  blit(px, W, H, "EMBL")

  if tic <= 29 then
    -- the ribbon unfurls over 24 tics with the SONIC text baked into it
    blit(px, W, H, frameName("RIBB", tic + 1, 25))
    blit(px, W, H, frameName("SONT", math.min(tic, 28) + 1, 29))
    if tic > 9 then
      blit(px, W, H, "ROBO")
      if tic > 15 then
        blit(px, W, H, frameName("TWOT", math.min(tic - 16, 15) + 1, 16))
      end
    end
  else
    blit(px, W, H, frameName("RIBB", 25, 25))
    blit(px, W, H, frameName("SONT", 29, 29))
    blit(px, W, H, "ROBO")
    blit(px, W, H, frameName("TWOT", 16, 16))
  end

  -- the cast arrives from tic 41 and then idles
  if tic >= SONICSTART then
    blit(px, W, H, frameName("SOIB", floor((tic - SONICSTART) / 3) % 17 + 1, 17))
  end
  if tic >= TAILSSTART then
    blit(px, W, H, frameName("TAIB", floor((tic - TAILSSTART) / 3) % 17 + 1, 17))
  end
  if tic >= KNUXSTART then
    blit(px, W, H, frameName("KNIB", floor((tic - KNUXSTART) / 3) % 20 + 1, 20))
  end

  -- flash at tic 30, held to 34, faded out by tic 44
  if tic >= FLASH_AT and tic <= FLASH_END then
    whiten(px, W, H, 1)
  elseif tic > FLASH_END and tic < FADE_END then
    whiten(px, W, H, (FADE_END - tic) / (FADE_END - FLASH_END))
  end
end

return title
