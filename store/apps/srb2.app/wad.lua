-- wad.lua - loader for the trimmed greenflower zone act 1 wad.
--
-- the geometry lumps are srb2's own MAP01 data, byte for byte.  the sidedef and
-- flat colour lumps are produced by tools/srb2/make_level.py, which averages the
-- real textures and flats the map references; that is why no texture names or
-- colour tables appear here.
--
-- opencomputers gives a lua vm a couple of megabytes, so nothing below keeps a
-- table per vertex, seg, node or subsector: everything lands in flat number
-- arrays, several fields to a slot, and the wad image is released after parsing.

local wad = {}

local FOF_SPECIALS = { [100] = true, [101] = true, [105] = true, [121] = true, [123] = true }

-- opencomputers gives a lua vm about two megabytes, so nothing here keeps a
-- table per vertex/seg/node/subsector. everything lands in flat number arrays,
-- several fields to a slot, and the wad image itself is released after parsing.
local MAXV = 8192       -- vertex index packing base
local MAXSEG = 8192     -- seg index packing base
local MAXSEC = 512      -- sector index packing base
local STEPHEIGHT = 24   -- srb2 MAXSTEPMOVE
local HEADROOM = 32     -- player height plus a little slack

function wad.load(path)
  local f = io.open(path, "rb")
  if not f then return nil, "cannot open " .. tostring(path) end
  local data = f:read("*a")
  f:close()
  if type(data) ~= "string" or #data < 12 then return nil, "file too small" end

  local byte = string.byte
  local function u16(o) local a, b = byte(data, o + 1, o + 2) return a + b * 256 end
  local function s16(o) local v = u16(o) if v >= 0x8000 then v = v - 65536 end return v end
  local function u32(o)
    local a, b, c, d = byte(data, o + 1, o + 4)
    return a + b * 256 + c * 65536 + d * 16777216
  end
  local function lname(o) return (data:sub(o + 1, o + 8):gsub("%z.*", "")) end

  local magic = data:sub(1, 4)
  if magic ~= "PWAD" and magic ~= "IWAD" then return nil, "not a wad file" end
  local nLumps, dirOff = u32(4), u32(8)
  if nLumps < 1 or nLumps > 4096 or dirOff + nLumps * 16 > #data then return nil, "bad wad directory" end
  local lumps = {}
  local order = {}
  for i = 0, nLumps - 1 do
    local p = dirOff + i * 16
    local nm = lname(p + 8)
    lumps[nm] = { pos = u32(p), size = u32(p + 4) }
    order[#order + 1] = nm
  end

  local map
  for _, nm in ipairs(order) do
    if nm:match("^MAP%d%d$") then map = nm break end
  end
  if not map then return nil, "no map lump found" end
  for _, need in ipairs({ "VERTEXES", "LINEDEFS", "SECTORS", "SEGS", "SSECTORS", "NODES", "THINGS", "SIDECOL", "WALLPAL", "SECTCOL" }) do
    if not lumps[need] then return nil, "missing " .. need .. " lump" end
  end

  ----------------------------------------------------------------- vertices
  local L = lumps.VERTEXES
  local nverts = math.floor(L.size / 4)
  if nverts >= MAXV then return nil, "too many vertices" end
  local vx, vy = {}, {}
  for i = 1, nverts do
    local o = L.pos + (i - 1) * 4
    vx[i], vy[i] = s16(o), s16(o + 2)
  end

  ------------------------------------------------------------------ sectors
  -- SECTORS is srb2's own lump; SECTCOL carries the average colour of the flats
  -- it names, resolved at build time.
  L = lumps.SECTORS
  local nsectors = math.floor(L.size / 26)
  if nsectors >= MAXSEC then return nil, "too many sectors" end
  local CL = lumps.SECTCOL
  if math.floor(CL.size / 7) < nsectors then return nil, "SECTCOL is short" end
  local sectors = {}
  for i = 1, nsectors do
    local o = L.pos + (i - 1) * 26
    local c = CL.pos + (i - 1) * 7
    local fr, fg, fb, cr, cg, cb, flags = byte(data, c + 1, c + 7)
    local light = u16(o + 20)
    local ch, fh = s16(o + 2), s16(o)
    sectors[i] = {
      fh = fh, ch = ch,
      fcol = fr * 65536 + fg * 256 + fb,
      ccol = cr * 65536 + cg * 256 + cb,
      sky = flags % 2 == 1,
      light = math.max(0.42, math.min(1, light / 255)),
      special = u16(o + 22), tag = s16(o + 24),
      waterTop = (math.floor(flags / 2) % 2 == 1) and ch or nil,
      waterBtm = (math.floor(flags / 4) % 2 == 1) and fh or nil,
    }
  end

  ---------------------------------------------------------------- side data
  -- SIDECOL replaces SIDEDEFS: sector index plus a slot into WALLPAL.
  L = lumps.SIDECOL
  local nsides = math.floor(L.size / 3)
  local sideSec, sideSlot = {}, {}
  for i = 1, nsides do
    local o = L.pos + (i - 1) * 3
    sideSec[i] = s16(o)
    sideSlot[i] = byte(data, o + 3) + 1
  end

  local WP = lumps.WALLPAL
  local wallpal = {}
  for i = 1, math.floor(WP.size / 3) do
    local r, g, b = byte(data, WP.pos + (i - 1) * 3 + 1, WP.pos + (i - 1) * 3 + 3)
    wallpal[i] = r * 65536 + g * 256 + b
  end
  local ROCKSLOT = 1

  ----------------------------------------------------------------- linedefs
  -- packed per line: v1 + v2*MAXV, and fsec + bsec*MAXSEC + solid*MAXSEC^2 +
  -- wallslot*MAXSEC^2*2.  sector 0 means "none".
  L = lumps.LINEDEFS
  local nlines = math.floor(L.size / 14)
  local lv, lf, lb = {}, {}, {}
  local solidCount = 0
  for i = 1, nlines do
    local o = L.pos + (i - 1) * 14
    local v1, v2 = u16(o) + 1, u16(o + 2) + 1
    local special = u16(o + 6)
    -- sidenum[] is 0-based, 0xffff means "no side"
    local sf, sb = u16(o + 10), u16(o + 12)
    local fi = (sf < nsides) and sf + 1 or nil
    local bi = (sb < nsides) and sb + 1 or nil
    local fsec = (fi and sideSec[fi] >= 0) and sideSec[fi] + 1 or 0
    if fsec > nsectors then fsec = 0 end
    local bsec = (bi and sideSec[bi] >= 0) and sideSec[bi] + 1 or 0
    if bsec > nsectors then bsec = 0 end
    local solid = (bsec == 0 and not FOF_SPECIALS[special]) and 1 or 0
    local slot = (fi and sideSlot[fi]) or ROCKSLOT
    lv[i] = v1 + v2 * MAXV
    lf[i] = fsec + bsec * MAXSEC + solid * (MAXSEC * MAXSEC) + slot * (MAXSEC * MAXSEC * 2)
    if solid == 1 then solidCount = solidCount + 1 end
    -- physics also has to stop at two-sided lines the player cannot fit through
    -- or step over: srb2's step height is 24 and the player is 26 tall.
    local block = solid
    if block == 0 and fsec > 0 and bsec > 0 then
      local a, b = sectors[fsec], sectors[bsec]
      local gap = math.min(a.ch, b.ch) - math.max(a.fh, b.fh)
      local step = math.abs(a.fh - b.fh)
      if gap < HEADROOM or step > STEPHEIGHT then block = 1 end
    end
    if u16(o + 4) % 2 == 1 then block = 1 end   -- ML_IMPASSIBLE
    lb[i] = block
  end
  sideSec, sideSlot = nil, nil

  local lineSpecial = {}
  for i = 1, nlines do lineSpecial[i] = u16(L.pos + (i - 1) * 14 + 6) end

  --------------------------------------------------------------------- segs
  -- packed per seg: v1 + v2*MAXV, and the owning line's fsec/bsec/solid/colour.
  L = lumps.SEGS
  local nsegs = math.floor(L.size / 12)
  local sv, sf = {}, {}
  for i = 1, nsegs do
    local o = L.pos + (i - 1) * 12
    sv[i] = (u16(o) + 1) + (u16(o + 2) + 1) * MAXV
    local ln = u16(o + 6)
    if ln >= 0 and ln < nlines then
      local packed = lf[ln + 1]
      -- a seg on the back side of a two-sided line swaps front/back sectors
      local side = u16(o + 8)
      if side == 1 then
        local fsec = packed % MAXSEC
        local bsec = math.floor(packed / MAXSEC) % MAXSEC
        packed = packed - fsec - bsec * MAXSEC + bsec + fsec * MAXSEC
      end
      sf[i] = packed
    else
      sf[i] = ROCKSLOT * (MAXSEC * MAXSEC * 2)
    end
  end

  --------------------------------------------------------------- subsectors
  -- srb2 keeps the compressed 4-byte form: numsegs u16, firstseg u16.
  L = lumps.SSECTORS
  local nsubs = math.floor(L.size / 4)
  local uf, us = {}, {}
  for i = 1, nsubs do
    local o = L.pos + (i - 1) * 4
    local count, first = u16(o), u16(o + 2) + 1
    uf[i] = first + count * MAXSEG
    local sec = 0
    for j = first, math.min(first + count - 1, nsegs) do
      local packed = sf[j]
      local fsec = packed % MAXSEC
      if fsec > 0 then sec = fsec break end
    end
    us[i] = sec > 0 and sec or 1
  end

  -------------------------------------------------------------------- nodes
  L = lumps.NODES
  local nnodes = math.floor(L.size / 28)
  local npx, npy, ndx, ndy, nc1, nc2 = {}, {}, {}, {}, {}, {}
  for i = 1, nnodes do
    local o = L.pos + (i - 1) * 28
    npx[i], npy[i] = s16(o), s16(o + 2)
    ndx[i], ndy[i] = s16(o + 4), s16(o + 6)
    local c1, c2 = u16(o + 24), u16(o + 26)
    nc1[i] = (c1 >= 0x8000) and c1 or (c1 + 1)
    nc2[i] = (c2 >= 0x8000) and c2 or (c2 + 1)
  end

  ------------------------------------------------------------------- things
  L = lumps.THINGS
  local nthings = math.floor(L.size / 10)
  local tx, ty, ta, tt = {}, {}, {}, {}
  local count = 0
  local startx, starty, startangle = 0, 0, 0
  for i = 1, nthings do
    local o = L.pos + (i - 1) * 10
    local t = u16(o + 6)
    if t == 1 then
      startx, starty, startangle = s16(o), s16(o + 2), s16(o + 4)
    end
    if t ~= 750 and t ~= 780 and not (t >= 1 and t <= 32) then
      count = count + 1
      tx[count], ty[count], ta[count], tt[count] = s16(o), s16(o + 2), s16(o + 4), t
    end
  end
  nthings = count

  ---------------------------------------------------------------------- fofs
  -- srb2 floor-over-floor slabs: control sectors tagged by a group of lines.
  -- each group becomes one convex-ish blob with its control sector's heights.
  local fofs = {}
  do
    local groups = {}
    for i = 1, nlines do
      local special = lineSpecial[i]
      if FOF_SPECIALS[special] then
        local fsec = lf[i] % MAXSEC
        if fsec > 0 then
          local key = special * MAXSEC + fsec
          local g = groups[key]
          if not g then g = { special = special, sec = fsec, n = 0, minx = 1e9, miny = 1e9, maxx = -1e9, maxy = -1e9, sx = 0, sy = 0 } groups[key] = g end
          local packed = lv[i]
          for _, vi in ipairs({ packed % MAXV, math.floor(packed / MAXV) }) do
            local x, y = vx[vi], vy[vi]
            if x then
              if x < g.minx then g.minx = x end
              if x > g.maxx then g.maxx = x end
              if y < g.miny then g.miny = y end
              if y > g.maxy then g.maxy = y end
              g.sx, g.sy, g.n = g.sx + x, g.sy + y, g.n + 1
            end
          end
        end
      end
    end
    for _, g in pairs(groups) do
      local sec = sectors[g.sec]
      if sec and g.n > 0 then
        local water = g.special == 121
        fofs[#fofs + 1] = {
          btm = sec.fh, top = sec.ch,
          topcol = water and 0x1E3E82 or sec.fcol,
          botcol = water and 0x14325E or sec.ccol,
          water = water, solid = not water,
          minx = g.minx, miny = g.miny, maxx = g.maxx, maxy = g.maxy,
          cx = g.sx / g.n, cy = g.sy / g.n,
          rad = math.max(g.maxx - g.minx, g.maxy - g.miny) / 2 + 24,
        }
      end
    end
  end

  ----------------------------------------------------------------- blockmap
  -- physics only ever collides against genuinely solid lines, so the blockmap
  -- stores those as four flat coordinate arrays plus per-cell index lists.
  local CS = 256
  local cells = {}
  local bax, bay, bbx, bby = {}, {}, {}, {}
  local nsolid = 0
  for i = 1, nlines do
    if lb[i] == 1 then
      local pv = lv[i]
      local v1, v2 = pv % MAXV, math.floor(pv / MAXV)
      local ax, ay, bx, by = vx[v1], vy[v1], vx[v2], vy[v2]
      if ax and bx then
        nsolid = nsolid + 1
        bax[nsolid], bay[nsolid], bbx[nsolid], bby[nsolid] = ax, ay, bx, by
        local c0x, c1x = math.floor(math.min(ax, bx) / CS), math.floor(math.max(ax, bx) / CS)
        local c0y, c1y = math.floor(math.min(ay, by) / CS), math.floor(math.max(ay, by) / CS)
        for cx = c0x, c1x do
          local col = cells[cx]
          if not col then col = {} cells[cx] = col end
          for cy = c0y, c1y do
            local cell = col[cy]
            if not cell then cell = {} col[cy] = cell end
            cell[#cell + 1] = nsolid
          end
        end
      end
    end
  end

  lv, lf, lb, lineSpecial = nil, nil, nil, nil
  data = nil

  return {
    name = map,
    MAXV = MAXV, MAXSEG = MAXSEG, MAXSEC = MAXSEC,
    nverts = nverts, vx = vx, vy = vy,
    nsectors = nsectors, sectors = sectors,
    nsegs = nsegs, sv = sv, sf = sf,
    nsubs = nsubs, uf = uf, us = us,
    nnodes = nnodes, npx = npx, npy = npy, ndx = ndx, ndy = ndy, nc1 = nc1, nc2 = nc2,
    nthings = nthings, tx = tx, ty = ty, ta = ta, tt = tt,
    wallpal = wallpal,
    fofs = fofs,
    cells = cells, cellSize = CS,
    nsolid = nsolid, bax = bax, bay = bay, bbx = bbx, bby = bby,
    startx = startx, starty = starty, startangle = startangle,
    maxd = 5200,
  }
end

return wad
