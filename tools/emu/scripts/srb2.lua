local emu = ...
local core = emu.core

emu.idle(3)
local pid, err = core.launch("srb2")
if not pid then
  io.stderr:write("launch failed: " .. tostring(err) .. "\n")
  emu.shot("00-launch-failed")
  emu.quit()
  return
end

emu.idle(6)  emu.shot("01-title-open")
emu.idle(12) emu.shot("02-title-ribbon")
emu.idle(16) emu.shot("03-title-flash")
emu.idle(34) emu.shot("04-title-cast")

emu.key(0, 28)          -- any key starts the level
emu.idle(40)
emu.shot("05-level-start")

emu.down(119, 17)       -- hold forward out of the starting alcove
emu.idle(50) emu.shot("06-running")
emu.idle(50) emu.shot("07-onward")
emu.up(119, 17)

emu.down(0, 205)        -- turn right
emu.idle(25)
emu.up(0, 205)
emu.idle(4) emu.shot("08-turned")

emu.down(119, 17)
emu.idle(60) emu.shot("09-more")
emu.up(119, 17)
emu.key(0, 57)          -- jump
emu.idle(8) emu.shot("10-jump")
emu.quit()
