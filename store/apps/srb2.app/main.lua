-- main.lua - SRB2: Greenflower Zone Act 1, running as an idk os app.
--
-- the app owns one window and drives three modules: title.lua composes srb2's
-- real alacroix title screen, wad.lua loads the real MAP01 out of GFZ1.wad, and
-- render.lua draws it with a doom-style bsp renderer while game.lua runs srb2's
-- physics.  two logical pixels share a character cell through the upper-half
-- block glyph, which is why the picture is twice as tall as the row count.

return function(app)
  local manifest = app.apps and app.apps().srb2
  local base = manifest and manifest.path

  -- size the picture from the screen first, then ask for a window that fits it
  -- exactly, so a big screen does not leave the game in a corner of a black box.
  local screenW, screenH = app.screen()
  local PIXEL_BUDGET = 20000
  local wantW = math.max(40, math.min(screenW - 2, 160))
  local wantRows = math.max(8, math.min(screenH - 5, math.floor(PIXEL_BUDGET / (2 * wantW))))
  local win = app.window{ title = "SRB2: Greenflower Zone Act 1",
                          width = wantW, height = wantRows + 3, bg = 0x000000 }

  local function fatal(msg)
    while true do
      win:reset()
      win:text(2, 2, "srb2 could not start", 0xff6a63, 0x000000)
      win:text(2, 4, tostring(msg), 0xf2d2cf, 0x000000)
      win:text(2, 6, "reinstall the package from the app store", 0x9ba4b3, 0x000000)
      app.pull()
    end
  end

  if not base then fatal("installed package path is unavailable") end

  local function part(name)
    local ok, mod = pcall(dofile, app.fs.concat(base, name))
    if not ok or type(mod) ~= "table" then fatal(name .. ": " .. tostring(mod)) end
    return mod
  end

  ------------------------------------------------------------------ geometry
  -- one canvas submission is capped at 4096 cells, so the picture is sized to
  -- the largest 2:1-ish view that fits both the window and that budget.
  -- the picture is bounded by lua, not by the gpu: every logical pixel costs a
  -- bsp lookup, so past roughly twenty thousand of them the renderer, not the
  -- call budget, is what sets the frame rate.
  local ww, wh = win:size()
  local VIEWW = math.min(ww, 160)
  local ROWS = math.min(wh - 2, math.floor(PIXEL_BUDGET / (2 * VIEWW)))
  if ROWS < 8 then fatal("this screen is too small; try a larger display mode") end

  local fgp, bgp, glyphs = {}, {}, {}
  local BLOCK = "\u{2580}"
  local canvas = { backgrounds = bgp, foregrounds = fgp, glyphs = glyphs }

  -- older builds of idk os cap a single canvas submission, so settle on the
  -- largest picture this one actually accepts rather than assuming a number.
  local function fits(rows)
    for i = 1, VIEWW * rows do
      if not glyphs[i] then fgp[i], bgp[i], glyphs[i] = 0, 0, BLOCK end
    end
    win:reset()
    local ok = win:canvas(1, 1, VIEWW, rows, canvas)
    win:reset()
    return ok ~= nil
  end
  while ROWS >= 8 and not fits(ROWS) do ROWS = math.floor(ROWS / 2) end
  if ROWS < 8 then fatal("this screen cannot show the game") end

  local VIEWH = ROWS * 2
  local HUDY = ROWS + 1
  local px = {}
  for i = 1, VIEWW * VIEWH do px[i] = 0 end

  local function present()
    win:reset()
    win:canvas(1, 1, VIEWW, ROWS, canvas)
  end

  -- pack the pixel buffer into cells: top sample is the glyph colour, bottom
  -- sample is the cell background.
  local function packPixels()
    for y = 1, ROWS do
      local top = (2 * y - 2) * VIEWW
      local out = (y - 1) * VIEWW
      for x = 1, VIEWW do
        fgp[out + x] = px[top + x]
        bgp[out + x] = px[top + VIEWW + x]
      end
    end
  end

  --------------------------------------------------------------------- title
  local title = part("title.lua")
  local ok, err = title.open(app.fs.concat(base, "TITLE.wad"))
  if not ok then fatal(err) end

  local TICRATE = 35
  local tic = 0
  local start = app.computer.uptime()
  local skip = false
  present()
  while not skip do
    title.draw(px, VIEWW, VIEWH, tic)
    packPixels()
    present()
    win:text(1, HUDY, "  press any key to start                    esc: quit ", 0xf8e040, 0x000000)
    local elapsed = app.computer.uptime() - start
    local want = math.floor(elapsed * TICRATE)
    if want <= tic then want = tic + 1 end
    tic = want
    local name, _, char, code = app.pull(0.02)
    if name == "key_down" then skip = true
    elseif name == "closed" then title.close() return end
    if tic > title.LENGTH + 200 then tic = title.LENGTH end
  end
  title.close()
  title = nil

  ---------------------------------------------------------------- level load
  win:reset()
  win:text(2, math.floor(ROWS / 2), "GREENFLOWER ZONE  ACT 1", 0xf8e040, 0x000000)
  win:text(2, math.floor(ROWS / 2) + 2, "loading MAP01 ...", 0x9ba4b3, 0x000000)
  app.yield()

  local wad = part("wad.lua")
  local render = part("render.lua")
  local S = part("sprites.lua")
  local game = part("game.lua")

  local level, lerr = wad.load(app.fs.concat(base, "GFZ1.wad"))
  if not level then fatal(lerr or "cannot load GFZ1.wad") end
  render.init(VIEWW, VIEWH, 90)
  render.prepare(level, S.pal)
  game.init(level, S)
  wad = nil

  ---------------------------------------------------------------- main loop
  -- opencomputers keycodes: w/a/s/d, space, left shift, arrows, r, escape
  local K_W, K_A, K_S, K_D = 17, 30, 31, 32
  local K_SPACE, K_LSHIFT, K_RSHIFT, K_R, K_ESC = 57, 42, 54, 19, 1
  local K_LEFT, K_RIGHT = 203, 205

  local input = { fwd = false, back = false, left = false, right = false,
                  turnL = false, turnR = false, jump = false, spin = false }

  local function setKey(code, down)
    if code == K_W then input.fwd = down
    elseif code == K_S then input.back = down
    elseif code == K_A then input.left = down
    elseif code == K_D then input.right = down
    elseif code == K_LEFT then input.turnL = down
    elseif code == K_RIGHT then input.turnR = down
    elseif code == K_SPACE then input.jump = down
    elseif code == K_LSHIFT or code == K_RSHIFT then input.spin = down
    end
  end

  local last = app.computer.uptime()
  local acc = 0
  local running = true
  while running do
    local now = app.computer.uptime()
    local dt = now - last
    if dt > 0.25 then dt = 0.25 end
    last = now
    acc = acc + dt
    local steps = 0
    while acc >= 1 / TICRATE and steps < 4 do
      game.tick(input)
      game.time = game.time + 1 / TICRATE
      acc = acc - 1 / TICRATE
      steps = steps + 1
    end
    if steps == 0 then acc = 0 end

    local sprites = game.frame()
    local fg, bg = render.frame(level, game.cam, sprites, game.cam.i)
    for i = 1, VIEWW * ROWS do fgp[i], bgp[i] = fg[i], bg[i] end
    present()

    local hud = game.hud()
    win:text(1, HUDY, string.format("RINGS %-4d  TIME %-6s  LIVES %-3d %s",
      hud.rings, hud.time, hud.lives, hud.msgT > 0 and hud.msg or ""), 0xf8e040, 0x102040)
    win:text(1, HUDY + 1, "wasd move   arrows turn   space jump   shift spindash   r reset   esc quit",
      0x9ba4b3, 0x102040)

    local name, _, char, code = app.pull(0.01)
    if name == "key_down" then
      if code == K_ESC then running = false
      elseif code == K_R then game.resetLevel()
      else setKey(code, true) end
    elseif name == "key_up" then
      setKey(code, false)
    elseif name == "closed" then
      running = false
    end
  end
end
