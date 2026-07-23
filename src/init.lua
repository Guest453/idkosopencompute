local bootAddress = computer.getBootAddress()
local boot = assert(component.proxy(bootAddress), "boot filesystem is unavailable")

local function readFile(path)
  local handle, reason = boot.open(path, "r")
  if not handle then return nil, reason end
  local parts = {}
  while true do
    local chunk, readReason = boot.read(handle, 2048)
    if chunk == nil then
      boot.close(handle)
      if readReason then return nil, readReason end
      return table.concat(parts)
    end
    parts[#parts + 1] = chunk
  end
end

local source, reason = readFile("/idkos/system/runtime.lua")
assert(source, "cannot read standalone runtime: " .. tostring(reason))
local chunk, syntaxError = load(source, "=/idkos/system/runtime.lua", "t", _G)
assert(chunk, syntaxError)
local runtime = chunk()
runtime.install(boot)

local ok, bootError = xpcall(function()
  dofile("/idkos/boot.lua")
end, debug.traceback)
if not ok then
  runtime.fatal("idk os crashed:\n" .. tostring(bootError))
else
  runtime.fatal("idk os stopped. shutting down.")
end
