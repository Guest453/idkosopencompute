local emu = ...
local core = emu.core
local gpu = emu.gpu

emu.idle(3)
local pid, err = core.launch("srb2")
if not pid then
  io.stderr:write("launch failed: " .. tostring(err) .. "\n")
  emu.quit()
  return
end

emu.idle(8)
emu.key(0, 28)      -- skip the title into the level
emu.idle(60)

-- measure a steady stretch of gameplay
gpu.__resetBudget()
emu.down(119, 17)
local SAMPLE = 200
emu.idle(SAMPLE)
emu.up(119, 17)
local spent, perTick = gpu.__budget()

emu.shot("bench")
io.stderr:write(string.format(
  "BENCH buffered=%s vrampages=%d budget=%.1f over %d pulls (%.3f per pull, budget/tick=%.1f)\n",
  tostring(gpu.allocateBuffer ~= nil), gpu.__buffers and gpu.__buffers() or 0,
  spent, SAMPLE, spent / SAMPLE, perTick))
emu.quit()
