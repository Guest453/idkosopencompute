local function traceback(reason)
  if debug and debug.traceback then return debug.traceback(reason,2) end
  return tostring(reason)
end

local function valid(core)
  return type(core)=="table" and type(core.run)=="function" and type(core.restore)=="function"
end

local function loadCore(path)
  local ok,result=pcall(dofile,path)
  if not ok then return nil,result end
  if not valid(result) then return nil,"core returned an invalid interface" end
  return result
end

local function writeFallbackLog(message)
  pcall(function()
    local filesystem=require("filesystem")
    local file=filesystem.open("/idkos/next-core.log","w")
    if file then file:write(tostring(message):sub(1,16384)) file:close() end
  end)
end

local core,nextReason=loadCore("/idkos/system/core_next.lua")
local usingNext=core~=nil
if not core then
  writeFallbackLog("next shell load failed:\n"..tostring(nextReason))
  local oldReason
  core,oldReason=loadCore("/idkos/system/core.lua")
  if not core then error("both idk os shells failed: "..tostring(nextReason).."; "..tostring(oldReason),0) end
end

local success,reason=xpcall(core.run,traceback)
core.restore()

if not success and usingNext then
  writeFallbackLog("next shell runtime failed:\n"..tostring(reason))
  local fallback,fallbackReason=loadCore("/idkos/system/core.lua")
  if fallback then
    success,reason=xpcall(fallback.run,traceback)
    fallback.restore()
  else
    success=false
    reason=tostring(reason).."\nold shell load failed: "..tostring(fallbackReason)
  end
end

if not success then error(reason,0) end
