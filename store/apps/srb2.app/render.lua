-- render.lua - doom-style software renderer for srb2.app
--
-- one ray per screen column walks the level's real bsp exactly like
-- R_RenderBSPNode does, collecting the ordered list of sector crossings along
-- that ray.  each row then resolves the nearest visible floor/ceiling plane or
-- wall against that list, which is the same job R_MapPlane and the seg loop do
-- in the original engine.  srb2's floor-over-floor slabs fall out of this for
-- free because their control sectors' heights are ordinary crossings.
--
-- output is packed two logical pixels to a character cell with the upper-half
-- block glyph, so a 160x50 opencomputers screen shows a 90x84 picture.

local render = {}

local floor, sqrt, cos, sin = math.floor, math.sqrt, math.cos, math.sin

local VIEWW, VIEWH, CY, FOCAL
local VOID = 1e7
local EYE = 41              -- srb2 camera height above the player's feet

-- module state, all preallocated: opencomputers cannot afford per-frame garbage
local px, depth
local ct, csec, csolid, cwr, cwg, cwb, ccount
local fgp, bgp, gly
local skyRow, noise
local wallCacheR, wallCacheG, wallCacheB

local FOGR, FOGG, FOGB = 150, 180, 255
local MAXFOG = 3000

local function mix(r, g, b, d)
  local f = d / MAXFOG
  if f > 1 then f = 1 elseif f < 0 then f = 0 end
  local mf = 1 - f
  return r * mf + FOGR * f, g * mf + FOGG * f, b * mf + FOGB * f
end

local function pack(r, g, b)
  r = r < 0 and 0 or (r > 255 and 255 or r)
  g = g < 0 and 0 or (g > 255 and 255 or g)
  b = b < 0 and 0 or (b > 255 and 255 or b)
  return floor(r) * 65536 + floor(g) * 256 + floor(b)
end

-- point location in the bsp: returns a 1-based sector index
local function locateSector(lv, x, y)
  local npx, npy, ndx, ndy, nc1, nc2 = lv.npx, lv.npy, lv.ndx, lv.ndy, lv.nc1, lv.nc2
  local n = lv.nnodes
  while n >= 1 do
    local s = (x - npx[n]) * ndy[n] - (y - npy[n]) * ndx[n]
    local c = s > 0 and nc1[n] or nc2[n]
    if c >= 0x8000 then return lv.us[c - 0x7FFF] or 1 end
    n = c
  end
  return 1
end
render.locateSector = locateSector

-- Walk the bsp front to back along one ray.  classic doom nodes carry no
-- minisegs, so subsectors are not closed by segs and the crossing order has to
-- come from the node partitions themselves: every leaf is popped together with
-- the ray parameter at which the traversal entered it.  inside a leaf the segs
-- are only consulted to find the wall the ray actually hits.
local function bspWalk(lv, cam, rx, ry)
  local vx, vy, sv, sf = lv.vx, lv.vy, lv.sv, lv.sf
  local uf, us = lv.uf, lv.us
  local npx, npy, ndx, ndy, nc1, nc2 = lv.npx, lv.npy, lv.ndx, lv.ndy, lv.nc1, lv.nc2
  local MAXV, MAXSEG, MAXSEC = lv.MAXV, lv.MAXSEG, lv.MAXSEC
  local SOLIDBIT, SLOTDIV = MAXSEC * MAXSEC, MAXSEC * MAXSEC * 2
  local light, wallpal = lv.slight, lv.wallpal
  local maxd = lv.maxd
  local cx, cy = cam.x, cam.y

  local count = 0
  local lastR, lastG, lastB = 137, 76, 28

  -- nearest seg of one leaf that the ray crosses between two ray parameters
  local function scanSegs(leaf, t0, t1)
    local packed = uf[leaf]
    local first = packed % MAXSEG
    local n = floor(packed / MAXSEG)
    local bestT, bestPF = nil, nil
    for i = first, first + n - 1 do
      local pv = sv[i]
      if pv then
        local a = pv % MAXV
        local b = floor(pv / MAXV)
        local ax, ay = vx[a], vy[a]
        local sdx, sdy = vx[b] - ax, vy[b] - ay
        local den = rx * sdy - ry * sdx
        if den ~= 0 then
          local t = ((ax - cx) * sdy - (ay - cy) * sdx) / den
          if t > t0 + 0.03 and t <= t1 + 0.03 and (not bestT or t < bestT) then
            local u = ((ax - cx) * ry - (ay - cy) * rx) / den
            if u >= 0 and u <= 1 then bestT, bestPF = t, sf[i] end
          end
        end
      end
    end
    return bestT, bestPF
  end

  local function wallColor(pf)
    local fsec = pf % MAXSEC
    local slot = floor(pf / SLOTDIV)
    local key = slot * MAXSEC + fsec
    local r = wallCacheR[key]
    if not r then
      local base = wallpal[slot] or 0x894C1C
      local lfv = light[fsec] or 1
      r = floor(base / 65536) % 256 * lfv
      wallCacheR[key] = r
      wallCacheG[key] = floor(base / 256) % 256 * lfv
      wallCacheB[key] = base % 256 * lfv
    end
    return r, wallCacheG[key], wallCacheB[key]
  end

  local function emit(t, sector, solid, r, g, b)
    count = count + 1
    ct[count] = t
    csec[count] = sector
    csolid[count] = solid
    cwr[count], cwg[count], cwb[count] = r, g, b
  end

  local stk = { lv.nnodes, 0 }
  local sp = 2
  local pending, pendingT = nil, 0
  local stopped = false
  while sp > 0 and not stopped do
    local t0 = stk[sp] sp = sp - 1
    local node = stk[sp] sp = sp - 1
    if node < 0x8000 then
      local side = (cx - npx[node]) * ndy[node] - (cy - npy[node]) * ndx[node]
      local den = rx * ndy[node] - ry * ndx[node]
      local c1, c2 = nc1[node], nc2[node]
      local near = (side > 0) and c1 or c2
      local far = (side > 0) and c2 or c1
      if den == 0 then
        sp = sp + 1 stk[sp] = near
        sp = sp + 1 stk[sp] = t0
      else
        local t = -side / den
        if t <= t0 + 0.01 or t >= maxd then
          sp = sp + 1 stk[sp] = near
          sp = sp + 1 stk[sp] = t0
        else
          sp = sp + 1 stk[sp] = far
          sp = sp + 1 stk[sp] = t
          sp = sp + 1 stk[sp] = near
          sp = sp + 1 stk[sp] = t0
        end
      end
    else
      local leaf = node - 0x7FFF
      if not pending then
        emit(0, us[leaf], false, lastR, lastG, lastB)
      else
        local hitT, hitPF = scanSegs(pending, pendingT, t0)
        if hitPF then
          local r, g, b = wallColor(hitPF)
          lastR, lastG, lastB = r, g, b
          if floor(hitPF / SOLIDBIT) % 2 == 1 then
            emit(hitT, csec[count], true, r, g, b)
            stopped = true
          else
            emit(hitT, us[leaf], false, r, g, b)
          end
        else
          emit(t0, us[leaf], false, lastR, lastG, lastB)
        end
      end
      if not stopped then pending, pendingT = leaf, t0 end
    end
  end
  if not stopped and pending then
    local hitT, hitPF = scanSegs(pending, pendingT, maxd)
    if hitPF then
      local r, g, b = wallColor(hitPF)
      emit(hitT, csec[count], true, r, g, b)
      stopped = true
    end
  end
  if count == 0 then emit(0, 1, false, lastR, lastG, lastB) end
  count = count + 1
  ct[count] = VOID
  csec[count] = csec[count - 1] or 1
  csolid[count] = false
  cwr[count], cwg[count], cwb[count] = lastR, lastG, lastB
  ccount = count
end

local function renderFrame(lv, cam, sprites, tick)
  local fh, ch, sky = lv.sfh, lv.sch, lv.ssky
  local fcr, fcg, fcb = lv.fcr, lv.fcg, lv.fcb
  local ccr, ccg, ccb = lv.ccr, lv.ccg, lv.ccb
  local fx = cos(cam.yaw)
  local fy = -sin(cam.yaw)
  local sx, sy = -fy, fx
  local eyeZ = cam.z + EYE
  local halfw = VIEWW / 2

  for col = 1, VIEWW do
    local tanv = (col - 0.5 - halfw) / FOCAL
    local rx = fx + sx * tanv
    local ry = fy + sy * tanv
    local len = sqrt(rx * rx + ry * ry)
    rx, ry = rx / len, ry / len
    bspWalk(lv, cam, rx, ry)

    local j = 1
    for y = 1, VIEWH do
      local tanh = (y - 0.5 - CY) / FOCAL
      local idx = (y - 1) * VIEWW + col
      while true do
        local s = csec[j]
        local dmin, kind = VOID, 0     -- 0 = ceiling, 1 = floor
        local dc = (eyeZ - ch[s]) / tanh
        if dc > 0 and dc < dmin then dmin = dc end
        local df = (eyeZ - fh[s]) / tanh
        if df > 0 and df < dmin then dmin = df kind = 1 end
        local nx = j + 1
        if nx > ccount or dmin < ct[nx] then
          if kind == 0 and sky[s] then
            local n = noise[(col * 3 + y * 7 + tick) % 64 + 1]
            px[idx] = n > 0.86 and 0x47BBFF or (n > 0.66 and 0x6EA8FF or skyRow[y])
            depth[idx] = VOID
          else
            local r, g, b
            if kind == 1 then r, g, b = mix(fcr[s], fcg[s], fcb[s], dmin)
            else r, g, b = mix(ccr[s], ccg[s], ccb[s], dmin) end
            px[idx] = pack(r, g, b)
            depth[idx] = dmin
          end
          break
        end
        local t = ct[nx]
        local blocked = csolid[nx]
        if not blocked then
          local bs = csec[nx]
          local h = eyeZ - tanh * t
          blocked = h < fh[bs] - 0.01 or h > ch[bs] + 0.01
        end
        if blocked then
          local r, g, b = mix(cwr[nx], cwg[nx], cwb[nx], t)
          px[idx] = pack(r, g, b)
          depth[idx] = t
          break
        end
        j = nx
      end
    end
  end

  -- sprites, far to near, tested against the per-pixel depth buffer
  local pal = render.pal
  for si = 1, #sprites do
    local spr = sprites[si]
    local ddx, ddy = spr.x - cam.x, spr.y - cam.y
    local fw = ddx * fx + ddy * fy
    if fw > 8 and fw < lv.maxd then
      local art = spr.art
      local sd = ddx * sx + ddy * sy
      local scale = FOCAL / fw
      local wpx = spr.w * scale
      local hpx = spr.h * scale
      if wpx >= 1 and hpx >= 1 then
        local x0 = halfw + sd * scale - wpx / 2
        local ytop = CY - (spr.z + spr.h - eyeZ) * scale
        local bw, bh, rows = art.bw, art.bh, art.rows
        local pxstep, pystep = wpx / bw, hpx / bh
        for py = 0, bh - 1 do
          local row = floor(ytop + (py + 0.5) * pystep) + 1
          if row >= 1 and row <= VIEWH then
            local rowbase = (row - 1) * VIEWW
            local line = rows[py + 1]
            for sxi = 0, bw - 1 do
              local c = floor(x0 + (sxi + 0.5) * pxstep) + 1
              if c >= 1 and c <= VIEWW then
                local v = line:byte(sxi + 1)
                if v and v > 0 then
                  local i = rowbase + c
                  if fw < depth[i] then px[i] = pal[v] depth[i] = fw end
                end
              end
            end
          end
        end
      end
    end
  end

  -- two logical pixel rows per character cell
  local rows = VIEWH / 2
  for cellY = 1, rows do
    local tb = (2 * cellY - 2) * VIEWW
    local ob = (cellY - 1) * VIEWW
    for c = 1, VIEWW do
      fgp[ob + c] = px[tb + c]
      bgp[ob + c] = px[tb + VIEWW + c]
    end
  end
end

function render.frame(lv, cam, sprites, tick)
  renderFrame(lv, cam, sprites, tick or 0)
  return fgp, bgp, gly
end

function render.size() return VIEWW, VIEWH end

function render.init(width, height, fovDegrees)
  VIEWW = width
  VIEWH = height - (height % 2)
  CY = floor(VIEWH / 2)
  FOCAL = (VIEWW / 2) / math.tan(((fovDegrees or 90) / 2) * math.pi / 180)
  px, depth = {}, {}
  ct, csec, csolid, cwr, cwg, cwb = {}, {}, {}, {}, {}, {}
  wallCacheR, wallCacheG, wallCacheB = {}, {}, {}
  fgp, bgp, gly = {}, {}, {}
  local cells = VIEWW * (VIEWH / 2)
  local block = "\u{2580}"
  for i = 1, cells do fgp[i], bgp[i], gly[i] = 0, 0, block end
  for i = 1, VIEWW * VIEWH do px[i], depth[i] = 0, VOID end
  skyRow = {}
  for y = 1, VIEWH do
    local t = (y - 1) / (CY - 1)
    if t > 1 then t = 1 end
    skyRow[y] = pack(0x6C + (0xAD - 0x6C) * t, 0xB1 + (0xAD - 0xB1) * t, 0xFF)
  end
  noise = {}
  for i = 1, 64 do
    local v = sin(i * 12.9898 + 78.233) * 43758.5453
    noise[i] = v - floor(v)
  end
end

-- flatten the sector tables the loader produced into the parallel arrays the
-- inner loops read, then drop the tables.
function render.prepare(lv, pal)
  render.pal = pal
  local sectors = lv.sectors
  local n = lv.nsectors
  local sfh, sch, ssky, slight = {}, {}, {}, {}
  local swtop, swbtm = {}, {}
  local fcr, fcg, fcb, ccr, ccg, ccb = {}, {}, {}, {}, {}, {}
  for i = 1, n do
    local s = sectors[i]
    local lf = s.light
    sfh[i], sch[i], ssky[i], slight[i] = s.fh, s.ch, s.sky, lf
    swtop[i], swbtm[i] = s.waterTop, s.waterBtm
    fcr[i] = floor(s.fcol / 65536) % 256 * lf
    fcg[i] = floor(s.fcol / 256) % 256 * lf
    fcb[i] = s.fcol % 256 * lf
    ccr[i] = floor(s.ccol / 65536) % 256 * lf
    ccg[i] = floor(s.ccol / 256) % 256 * lf
    ccb[i] = s.ccol % 256 * lf
  end
  lv.sfh, lv.sch, lv.ssky, lv.slight = sfh, sch, ssky, slight
  lv.swtop, lv.swbtm = swtop, swbtm
  lv.fcr, lv.fcg, lv.fcb = fcr, fcg, fcb
  lv.ccr, lv.ccg, lv.ccb = ccr, ccg, ccb
  -- the sector tables have been flattened; let them go
  lv.sectors = nil
end

return render
