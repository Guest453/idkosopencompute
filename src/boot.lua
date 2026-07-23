local ok, core = pcall(dofile, "/idkos/system/core.lua")
if not ok then
  io.stderr:write("idk os failed to load: " .. tostring(core) .. "\n")
  return
end

local success, reason = xpcall(function()
  core.run()
end, debug.traceback)

if not success then
  core.restore()
  io.stderr:write("idk os crashed:\n" .. tostring(reason) .. "\n")
else
  core.restore()
end
