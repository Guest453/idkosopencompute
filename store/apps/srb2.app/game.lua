-- game.lua — SRB2-style gameplay for srb2.app
-- physics follow real SRB2 constants (TICRATE 35, gravity 0.5, jump 9.75,
-- maxspeed 36, friction 0.90625); level data from wad.lua, art from sprites.lua.

local game = {}

local TIC = 1 / 35
local GRAV = 0.5
local MAXSPD = 36
local FRICT = 0.90625
local JUMPZ = 9.75
local RADIUS = 14
local HEIGHT = 26
local CAMDIST = 160     -- srb2 cam_dist
local CAMHEIGHT = 40    -- srb2 cam_height
local VIEWDIST = 2600

local SPRITES = {
  ring = { w = 14, h = 14, kind = "ring" },
  springY = { w = 26, h = 18, kind = "springY" },
  springR = { w = 26, h = 18, kind = "springR" },
  springDY = { w = 24, h = 20, kind = "springDY" },
  springDR = { w = 24, h = 20, kind = "springDR" },
  springHY = { w = 26, h = 18, kind = "springHY" },
  springHR = { w = 26, h = 18, kind = "springHR" },
  monitor = { w = 20, h = 24, kind = "monitor" },
  monInv = { w = 20, h = 24, kind = "monInv" },
  monLife = { w = 20, h = 24, kind = "monLife" },
  monSneak = { w = 20, h = 24, kind = "monSneak" },
  crawla = { w = 16, h = 18, kind = "crawla" },
  fish = { w = 14, h = 12, kind = "fish" },
  spike = { w = 14, h = 10, kind = "spike" },
  star = { w = 12, h = 44, kind = "star" },
  goal = { w = 22, h = 46, kind = "goal" },
  bubble = { w = 8, h = 8, kind = "bubble" },
  flower = { w = 12, h = 12, kind = "flower" },
  bush = { w = 18, h = 16, kind = "bush" },
  tree = { w = 24, h = 36, kind = "tree" },
  sonic = { w = 18, h = 26, kind = "sonic" },
  ball = { w = 12, h = 12, kind = "ball" },
}

local MON_ICON = {
  [407] = "monSneak", [408] = "monInv", [409] = "monLife",
}
local MON_SHIELD = { [402] = true, [403] = true, [404] = true, [405] = true, [406] = true }

function game.init(level, S, art)
  game.level = level
  game.S = S
  game.art = art or {}
  -- the renderer's yaw runs opposite to a doom mapthing angle, so negate it
  game.cam = { x = level.startx, y = level.starty, z = 0,
               yaw = -math.rad(level.startangle or 0), i = 0 }
  game.player = {
    x = level.startx, y = level.starty, z = 0,
    vx = 0, vy = 0, momz = 0,
    rings = 0, lives = 3, shield = false, invuln = 0, speedup = 0,
    onGround = true, water = false, air = 10, rolling = false,
    spin = 0, anim = 1, face = 1, dead = false, state = "play",
  }
  game.time = 0
  game.msg = ""
  game.msgT = 0
  game.check = { x = level.startx, y = level.starty, z = 0, set = false }
  game.levelTime = 0
  game.entities = {}
  game.deco = {}
  game.ringTotal = 0
  -- spawn from the map's own THINGS list; ids are srb2's object numbers
  local tx, ty, ta, tt = level.tx, level.ty, level.ta, level.tt
  local ents, deco = game.entities, game.deco
  for i = 1, level.nthings do
    local t = tt[i]
    local sx, sy, ang = tx[i], ty[i], ta[i]
    local z = game.floorAt(sx, sy)
    if t == 300 or t == 600 or t == 601 or t == 602 then
      ents[#ents + 1] = { k = "ring", x = sx, y = sy, z = z + 24, f = 1, dead = false, respawn = -1 }
      game.ringTotal = game.ringTotal + 1
    elseif t == 550 or t == 551 then
      ents[#ents + 1] = { k = t == 550 and "springY" or "springR", x = sx, y = sy, z = z, ang = ang, f = 1, dead = false }
    elseif t == 555 or t == 556 then
      ents[#ents + 1] = { k = "springDY", x = sx, y = sy, z = z, ang = ang, f = 1, dead = false }
    elseif t == 558 or t == 559 then
      ents[#ents + 1] = { k = t == 558 and "springHY" or "springHR", x = sx, y = sy, z = z + 12, ang = ang, f = 1, dead = false }
    elseif t >= 400 and t <= 410 then
      ents[#ents + 1] = { k = "monitor", x = sx, y = sy, z = z, icon = MON_ICON[t], shield = MON_SHIELD[t], mtype = t, f = 1, dead = false, pop = 0 }
    elseif t == 100 or t == 101 then
      ents[#ents + 1] = { k = "crawla", x = sx, y = sy, z = z, red = t == 101, vx = ang == 0 and 1.2 or -1.2, vy = 0, dir = 1, f = 1, t = 0, dead = false }
    elseif t == 102 then
      ents[#ents + 1] = { k = "fish", x = sx, y = sy, z = z, vx = 1, vy = 0.6, f = 1, t = 0, dead = false }
    elseif t == 523 then
      ents[#ents + 1] = { k = "spike", x = sx, y = sy, z = z, f = 1, dead = false }
    elseif t == 502 then
      ents[#ents + 1] = { k = "star", x = sx, y = sy, z = z, f = 1, flash = 0, dead = false }
    elseif t == 501 then
      ents[#ents + 1] = { k = "goal", x = sx, y = sy, z = z, f = 1, dead = false }
    elseif t == 500 then
      ents[#ents + 1] = { k = "bubble", x = sx, y = sy, z = z + 16, f = 1, dead = false }
    elseif t == 312 then
      ents[#ents + 1] = { k = "token", x = sx, y = sy, z = z + 24, f = 1, dead = false }
    elseif t == 322 then
      ents[#ents + 1] = { k = "emblem", x = sx, y = sy, z = z + 24, f = 1, dead = false }
    elseif t == 800 or t == 801 or t == 802 then
      deco[#deco + 1] = { k = "flower", x = sx, y = sy, z = z, v = t - 799 }
    elseif t == 804 or t == 805 then
      deco[#deco + 1] = { k = "bush", x = sx, y = sy, z = z, v = t - 803 }
    elseif t == 806 or t == 807 then
      deco[#deco + 1] = { k = "tree", x = sx, y = sy, z = z, v = t - 805 }
    end
  end
  -- the THINGS list has been turned into entities; release it
  level.tx, level.ty, level.ta, level.tt = nil, nil, nil, nil
end

function game.sectorAt(x, y)
  local lv = game.level
  local npx, npy, ndx, ndy, nc1, nc2 = lv.npx, lv.npy, lv.ndx, lv.ndy, lv.nc1, lv.nc2
  local n = lv.nnodes
  while n >= 1 do
    local d = (x - npx[n]) * ndy[n] - (y - npy[n]) * ndx[n]
    local c = d > 0 and nc1[n] or nc2[n]
    if c >= 0x8000 then return lv.us[c - 0x7FFF] or 1 end
    n = c
  end
  return 1
end

-- floor height including any solid floor-over-floor slab standing over it
function game.floorAt(x, y)
  local lv = game.level
  local fh = lv.sfh[game.sectorAt(x, y)] or 0
  local fofs = lv.fofs
  for i = 1, #fofs do
    local f = fofs[i]
    if f.solid and f.top > fh and x >= f.minx - 2 and x <= f.maxx + 2
       and y >= f.miny - 2 and y <= f.maxy + 2 then
      local dx, dy = x - f.cx, y - f.cy
      if dx * dx + dy * dy <= f.rad * f.rad then fh = f.top end
    end
  end
  return fh
end

local function collide(px, py, r)
  local lv = game.level
  local CS = lv.cellSize
  local bax, bay, bbx, bby = lv.bax, lv.bay, lv.bbx, lv.bby
  local cells = lv.cells
  local cx, cy = math.floor(px / CS), math.floor(py / CS)
  local p = game.player
  local hit = false
  for dx = -1, 1 do
    local col = cells[cx + dx]
    if col then
      for dy = -1, 1 do
        local cell = col[cy + dy]
        if cell then
          for i = 1, #cell do
            local li = cell[i]
            local ax, ay = bax[li], bay[li]
            local ex, ey = bbx[li] - ax, bby[li] - ay
            local len2 = ex * ex + ey * ey
            if len2 > 0 then
              local t = ((px - ax) * ex + (py - ay) * ey) / len2
              if t < 0 then t = 0 elseif t > 1 then t = 1 end
              local qx, qy = ax + ex * t, ay + ey * t
              local ddx, ddy = px - qx, py - qy
              local d2 = ddx * ddx + ddy * ddy
              if d2 < r * r and d2 > 0.0001 then
                local d = math.sqrt(d2)
                local nx, ny = ddx / d, ddy / d
                px, py = qx + nx * r, qy + ny * r
                local dot = p.vx * nx + p.vy * ny
                if dot < 0 then
                  p.vx = p.vx - nx * dot
                  p.vy = p.vy - ny * dot
                end
                hit = true
              end
            end
          end
        end
      end
    end
  end
  p.x, p.y = px, py
  return hit
end

function game.damage(from)
  local p = game.player
  if p.invuln > 0 then return end
  if p.shield then
    p.shield = false
    p.invuln = 1.5
    game.msg, game.msgT = "SHIELD LOST!", 1.5
    return
  end
  if p.rings > 0 then
    local n = math.min(8, math.max(4, math.floor(p.rings / 4)))
    local drop = math.floor(p.rings / 2)
    p.rings = p.rings - drop
    local ang0 = math.random() * 6.283
    for i = 1, n do
      local a = ang0 + (i - 1) * 6.283 / n
      local spd = 6 + math.random() * 5
      game.entities[#game.entities + 1] = {
        k = "fring", x = p.x, y = p.y, z = p.z + 12,
        vx = math.cos(a) * spd, vy = math.sin(a) * spd, momz = 6 + math.random() * 4,
        t = 0, dead = false, f = 1,
      }
    end
    p.invuln = 2
    game.msg, game.msgT = "OUCH!", 1
  else
    game.death()
  end
end

function game.death()
  local p = game.player
  p.dead = true
  p.state = "die"
  p.deadT = 2.5
  p.momz = 6
  p.vx, p.vy = 0, 0
end

function game.respawn()
  local p = game.player
  p.x, p.y = game.check.x, game.check.y
  p.z = game.floorAt(p.x, p.y)
  p.vx, p.vy, p.momz = 0, 0, 0
  p.dead = false
  p.state = "play"
  p.invuln = 2
  p.shield = false
  p.air = 10
end

function game.resetLevel()
  local lv = game.level
  game.check = { x = lv.startx, y = lv.starty, z = 0, set = false }
  game.time = 0
  game.player.rings = 0
  game.respawn()
  for i = 1, #game.entities do
    local e = game.entities[i]
    if e.k == "ring" or e.k == "fring" then
      e.dead = true
    elseif e.k == "monitor" then
      e.dead = false
      e.pop = 0
    end
  end
  game.msg, game.msgT = "", 0
end

local function touch(p, e)
  local dx, dy = p.x - e.x, p.y - e.y
  local rr = e.radius or 22
  if dx * dx + dy * dy > rr * rr then return false end
  return math.abs(p.z + HEIGHT / 2 - e.z - (e.hz or 12)) < (e.hz or 12) + HEIGHT / 2 + 10
end

function game.tick(input)
  local p = game.player
  local lv = game.level
  game.cam.i = game.cam.i + 1
  if p.state == "die" then
    p.deadT = p.deadT - TIC
    p.momz = p.momz - GRAV
    p.z = p.z + p.momz
    local fh = game.floorAt(p.x, p.y)
    if p.z < fh then p.z = fh end
    if p.deadT <= 0 then
      p.lives = p.lives - 1
      if p.lives < 0 then
        p.lives = 3
        game.resetLevel()
      else
        game.respawn()
      end
    end
    return
  end

  if p.state == "goal" then
    p.goalT = p.goalT - TIC
    if p.goalT <= 0 then
      p.state = "play"
      game.resetLevel()
      game.msg, game.msgT = "", 0
    end
    return
  end

  -- camera turn
  if input.turnL then game.cam.yaw = game.cam.yaw - 0.045 end
  if input.turnR then game.cam.yaw = game.cam.yaw + 0.045 end

  -- desired velocity relative to camera
  local fx, fy = math.cos(game.cam.yaw), -math.sin(game.cam.yaw)
  local sx, sy = -fy, fx
  local fwd = (input.fwd and 1 or 0) - (input.back and 1 or 0)
  local strafe = (input.right and 1 or 0) - (input.left and 1 or 0)
  local maxspd = MAXSPD
  if p.speedup > 0 then maxspd = maxspd * 1.5 end
  local dx = fx * fwd + sx * strafe
  local dy = fy * fwd + sy * strafe
  local dl = math.sqrt(dx * dx + dy * dy)
  if dl > 0 then
    dx, dy = dx / dl, dy / dl
    local ctrl = 0.5
    if not p.onGround then ctrl = 0.16 end
    if p.water then ctrl = 0.3 end
    p.vx = p.vx + dx * ctrl * maxspd
    p.vy = p.vy + dy * ctrl * maxspd
  end
  local spd = math.sqrt(p.vx * p.vx + p.vy * p.vy)
  if spd > maxspd then
    p.vx = p.vx * maxspd / spd
    p.vy = p.vy * maxspd / spd
  end

  -- friction
  if p.onGround and not input.spin and p.spin == 0 then
    p.vx = p.vx * FRICT
    p.vy = p.vy * FRICT
    if math.abs(p.vx) < 0.06 and math.abs(p.vy) < 0.06 then p.vx, p.vy = 0, 0 end
  end

  -- gravity / water
  local sec = game.sectorAt(p.x, p.y)
  local waterTop = lv.swtop[sec]
  p.water = waterTop ~= nil and p.z + 8 < waterTop
  if p.water then
    p.momz = p.momz - 0.12
    if p.momz < -3 then p.momz = -3 end
    p.air = p.air - TIC
    if input.jump then p.momz = 5.5 end
    if p.air <= 0 then
      p.air = 5
      game.damage()
    end
    p.rolling = false
  else
    p.momz = p.momz - GRAV
    if p.momz < -32 then p.momz = -32 end
    if p.air < 10 then p.air = math.min(10, p.air + TIC * 2) end
  end

  -- jump
  if input.jump and p.onGround and not p.water and p.spin == 0 then
    p.momz = JUMPZ
    p.onGround = false
  end

  -- spindash
  if input.spin and p.onGround and p.spin >= 0 then
    p.spin = p.spin + 1
    if p.spin > 40 then p.spin = 40 end
  end
  if not input.spin and p.spin > 0 then
    local ang = math.atan2(p.vy, p.vx)
    if math.abs(p.vx) < 0.5 and math.abs(p.vy) < 0.5 then
      ang = math.atan2(-fy, fx)
    end
    local dash = 8 + p.spin * 1.8
    p.vx = math.cos(ang) * dash
    p.vy = math.sin(ang) * dash
    p.momz = 2.5
    p.onGround = false
    p.rolling = true
    p.spin = 0
  end

  -- move.  srb2 speeds reach 36 units a tic, well past the player radius, so
  -- the step is swept in small pieces or the player tunnels through walls.
  local speed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
  local steps = math.ceil(speed / 8)
  if steps < 1 then steps = 1 elseif steps > 8 then steps = 8 end
  for _ = 1, steps do
    collide(p.x + p.vx / steps, p.y + p.vy / steps, RADIUS)
  end

  -- vertical
  local fh = game.floorAt(p.x, p.y)
  local ch = lv.sch[sec]
  local onFof = false
  for i = 1, #lv.fofs do
    local f = lv.fofs[i]
    if f.solid and f.top >= fh then
      local m = (p.x - f.cx) * (p.x - f.cx) + (p.y - f.cy) * (p.y - f.cy)
      if m <= f.rad * f.rad and p.x >= f.minx - 2 and p.x <= f.maxx + 2 and p.y >= f.miny - 2 and p.y <= f.maxy + 2 then
        local prev = p.z
        if prev >= f.top - 0.5 and p.z + p.momz <= f.top then
          fh = f.top
          onFof = true
        end
        if f.btm > ch then ch = f.btm end
      end
    end
  end
  p.z = p.z + p.momz
  if p.z < fh then
    p.z = fh
    if p.momz < -8 then p.rolling = true end
    p.momz = 0
    p.onGround = true
  end
  if p.z + HEIGHT > ch then
    p.z = ch - HEIGHT
    if p.momz > 0 then p.momz = 0 end
  end
  if p.z > fh + 0.5 then p.onGround = false end

  -- timers
  if p.invuln > 0 then p.invuln = p.invuln - TIC end
  if p.speedup > 0 then p.speedup = p.speedup - TIC end
  if game.msgT > 0 then game.msgT = game.msgT - TIC end

  -- entities
  for i = 1, #game.entities do
    local e = game.entities[i]
    if e.dead then
      if e.k == "ring" and e.respawn > 0 then
        e.respawn = e.respawn - TIC
        if e.respawn <= 0 then e.dead = false end
      end
    elseif e.k == "ring" then
      e.f = e.f + 1
      if e.f > 12 then e.f = 1 end
      if touch(p, e) then
        e.dead = true
        e.respawn = 60
        p.rings = p.rings + 1
        game.msg, game.msgT = tostring(p.rings) .. " RINGS", 0.6
      end
    elseif e.k == "fring" then
      e.t = e.t + TIC
      if e.t > 9 then e.dead = true end
      e.momz = e.momz - GRAV
      e.x = e.x + e.vx
      e.y = e.y + e.vy
      e.z = e.z + e.momz
      local efh = game.floorAt(e.x, e.y)
      if e.z < efh then
        e.z = efh
        e.momz = math.abs(e.momz) * 0.5
        e.vx = e.vx * 0.8
        e.vy = e.vy * 0.8
      end
      if touch(p, e) then
        e.dead = true
        p.rings = p.rings + 1
      end
    elseif e.k == "springY" or e.k == "springR" then
      if touch(p, e) then
        p.momz = e.k == "springY" and 23 or 31
        p.onGround = false
        p.rolling = false
      end
    elseif e.k == "springDY" or e.k == "springDR" then
      if touch(p, e) then
        local a = e.ang * 6.283 / 65536
        local sp = e.k == "springDY" and 16 or 22
        p.vx = math.cos(a) * sp
        p.vy = math.sin(a) * sp
        p.momz = 17
        p.onGround = false
      end
    elseif e.k == "springHY" or e.k == "springHR" then
      if touch(p, e) then
        local a = e.ang * 6.283 / 65536
        local sp = e.k == "springHY" and 30 or 38
        p.vx = math.cos(a) * sp
        p.vy = math.sin(a) * sp
        p.rolling = true
      end
    elseif e.k == "monitor" then
      if touch(p, e) then
        e.dead = true
        e.pop = 1
        local m = e.mtype
        if m == 400 then
          p.rings = p.rings + 10
          game.msg, game.msgT = "10 RINGS!", 1
        elseif e.shield then
          p.shield = true
          game.msg, game.msgT = "SHIELD!", 1
        elseif m == 407 then
          p.speedup = 20
          game.msg, game.msgT = "SPEED UP!", 1.5
        elseif m == 408 then
          p.invuln = 15
          game.msg, game.msgT = "INVINCIBLE!", 1.5
        elseif m == 409 then
          p.lives = p.lives + 1
          game.msg, game.msgT = "1-UP!", 1.5
        end
      end
    elseif e.k == "crawla" then
      e.t = e.t + TIC
      if e.t > 0.3 then e.t = 0 e.f = e.f == 1 and 2 or 1 end
      local nx2 = e.x + e.vx
      local ny2 = e.y + e.vy
      local okx = game.floorAt(nx2, e.y)
      if math.abs(okx - game.floorAt(e.x, e.y)) > 1 then e.vx = -e.vx else e.x = nx2 end
      local oky = game.floorAt(e.x, ny2)
      if math.abs(oky - game.floorAt(e.x, e.y)) > 1 then e.vy = -e.vy else e.y = ny2 end
      if touch(p, e) and p.invuln <= 0 then
        local stomp = (p.momz < -4 or p.rolling) and p.z + HEIGHT < e.z + 14
        if stomp then
          e.dead = true
          p.momz = 8
          p.rolling = true
          p.rings = p.rings + 1
          game.msg, game.msgT = "STOMPED!", 0.8
        else
          game.damage()
        end
      end
    elseif e.k == "fish" then
      e.t = e.t + TIC
      if e.t > 0.5 then
        e.t = 0
        e.vx = e.vx + (math.random() - 0.5) * 2
        e.vy = e.vy + (math.random() - 0.5) * 2
        local es = math.sqrt(e.vx * e.vx + e.vy * e.vy)
        if es > 3 then e.vx, e.vy = e.vx * 3 / es, e.vy * 3 / es end
      end
      e.x = e.x + e.vx * 0.3
      e.y = e.y + e.vy * 0.3
      e.f = e.f == 1 and 2 or 1
    elseif e.k == "spike" then
      if touch(p, e) then
        if p.rolling or p.momz < -8 then
          e.dead = true
          p.momz = 6
          p.rolling = true
        else
          game.damage()
        end
      end
    elseif e.k == "star" then
      if touch(p, e) then
        if not e.flash then e.flash = 30 end
        game.check.x, game.check.y = e.x, e.y
        game.check.set = true
        game.msg, game.msgT = "CHECKPOINT!", 1.5
      end
      if e.flash then
        e.flash = e.flash - TIC
        e.f = e.f + 1
        if e.f > 8 then e.f = 1 end
      end
    elseif e.k == "goal" then
      if touch(p, e) then
        p.state = "goal"
        p.goalT = 4
        local bonus = math.max(0, 600 - math.floor(game.time))
        game.msg, game.msgT = "CLEAR! " .. bonus .. " POINTS", 4
      end
    elseif e.k == "bubble" then
      e.z = e.z + 0.4
      local wt = lv.swtop[game.sectorAt(e.x, e.y)]
      if wt and e.z > wt then e.z = wt - 1 end
      if touch(p, e) then
        p.air = 10
        e.dead = true
      end
    end
  end

  game.time = game.time + TIC

  -- camera follow
  -- srb2's chase camera: behind the player along the view angle, eased in
  local cam = game.cam
  local wantx = p.x - math.cos(cam.yaw) * CAMDIST
  local wanty = p.y + math.sin(cam.yaw) * CAMDIST
  local fh = game.floorAt(wantx, wanty)
  cam.x = cam.x + (wantx - cam.x) * 0.3
  cam.y = cam.y + (wanty - cam.y) * 0.3
  local wantz = math.max(p.z, fh) + CAMHEIGHT
  cam.z = cam.z + (wantz - cam.z) * 0.3
end

-- monitor art by srb2 object number
local MON_ART = {
  [400] = "monRing", [402] = "monAttr", [403] = "monForce", [404] = "monArma",
  [405] = "monWhirl", [406] = "monElem", [407] = "monSneak", [408] = "monInv",
  [409] = "monLife", [410] = "monEgg",
}
local DECO_ART = {
  flower = { "flower1", "flower2", "flower3" },
  bush = { "bush1", "bush2" },
  tree = { "tree1", "tree2" },
}

-- sprites are handed to the renderer through a reusable pool: opencomputers
-- cannot afford a fresh table per visible object per frame.
local pool = {}
local function push(out, art, x, y, z)
  local n = #out + 1
  local sp = pool[n]
  if not sp then sp = {} pool[n] = sp end
  sp.x, sp.y, sp.z = x, y, z
  sp.w, sp.h, sp.art = art.w, art.h, art
  out[n] = sp
end

function game.frame()
  local S = game.S
  local out = {}
  local cam = game.cam
  local fx, fy = math.cos(cam.yaw), -math.sin(cam.yaw)
  local far = VIEWDIST * VIEWDIST
  -- only objects in front of the camera and inside the draw distance matter
  local function visible(x, y)
    local dx, dy = x - cam.x, y - cam.y
    if dx * dx + dy * dy > far then return false end
    return dx * fx + dy * fy > -64
  end

  local tick = game.cam.i
  for i = 1, #game.entities do
    local e = game.entities[i]
    if not e.dead and visible(e.x, e.y) then
      local k = e.k
      if k == "ring" or k == "fring" then
        push(out, S["ring" .. (math.floor(tick / 3) % 4 + 1)], e.x, e.y, e.z)
      elseif k == "springY" then push(out, S[e.f > 1 and "springY2" or "springY1"], e.x, e.y, e.z)
      elseif k == "springR" then push(out, S[e.f > 1 and "springR2" or "springR1"], e.x, e.y, e.z)
      elseif k == "springDY" then push(out, S.springD, e.x, e.y, e.z)
      elseif k == "springDR" then push(out, S.springDR, e.x, e.y, e.z)
      elseif k == "springHY" then push(out, S.springH, e.x, e.y, e.z)
      elseif k == "springHR" then push(out, S.springHR, e.x, e.y, e.z)
      elseif k == "monitor" then push(out, S[MON_ART[e.mtype] or "monRing"], e.x, e.y, e.z)
      elseif k == "crawla" then
        local f = math.floor(tick / 5) % 4 + 1
        push(out, e.red and S["crawlaR" .. (f > 2 and 2 or f)] or S["crawla" .. f], e.x, e.y, e.z)
      elseif k == "fish" then push(out, S[math.floor(tick / 6) % 2 == 0 and "fish1" or "fish2"], e.x, e.y, e.z)
      elseif k == "spike" then push(out, S.spike, e.x, e.y, e.z)
      elseif k == "star" then push(out, S[e.flash > 0 and "star2" or "star1"], e.x, e.y, e.z)
      elseif k == "goal" then push(out, S.goal, e.x, e.y, e.z)
      elseif k == "bubble" then push(out, S.bubble, e.x, e.y, e.z)
      elseif k == "token" then push(out, S.token, e.x, e.y, e.z)
      elseif k == "emblem" then push(out, S.emblem, e.x, e.y, e.z)
      end
    end
  end
  for i = 1, #game.deco do
    local e = game.deco[i]
    if visible(e.x, e.y) then
      local set = DECO_ART[e.k]
      push(out, S[set[e.v] or set[1]], e.x, e.y, e.z)
    end
  end

  -- the player, seen from behind by the chase camera
  local p = game.player
  local art
  if p.state == "die" then art = S.fall1
  elseif p.rolling or p.spin > 0 then art = S["roll" .. (math.floor(tick / 2) % 4 + 1)]
  elseif not p.onGround then art = S[p.momz > 0 and "spring" or "fall1"]
  else
    local spd = math.sqrt(p.vx * p.vx + p.vy * p.vy)
    if spd > 1 then
      art = S["walk" .. (math.floor(tick * math.min(spd, 20) / 24) % 8 + 1)]
    else
      art = S["sonic" .. (math.floor(tick / 8) % 4 + 1)]
    end
  end
  push(out, art, p.x, p.y, p.z)
  return out
end

function game.hud()
  local p = game.player
  local mins = math.floor(game.time / 60)
  local secs = math.floor(game.time % 60)
  return {
    rings = p.rings,
    lives = p.lives,
    time = string.format("%02d:%02d", mins, secs),
    msg = game.msg,
    msgT = game.msgT,
    check = game.check.set,
    state = p.state,
  }
end

return game