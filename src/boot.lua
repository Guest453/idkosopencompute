local core = dofile("/idkos/system/core.lua")
if type(core) ~= "table" or type(core.run) ~= "function" or type(core.restore) ~= "function" then
  error("idk os core returned an invalid interface", 0)
end

local function traceback(reason)
  if debug and debug.traceback then return debug.traceback(reason, 2) end
  return tostring(reason)
end

local success, reason = xpcall(core.run, traceback)
core.restore()
if not success then error(reason, 0) end
