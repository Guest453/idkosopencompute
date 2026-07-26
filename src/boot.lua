local function traceback(reason)
  if debug and debug.traceback then return debug.traceback(reason,2) end
  return tostring(reason)
end

local function valid(core)
  return type(core)=="table" and type(core.run)=="function" and type(core.restore)=="function"
end

local function readSource(path)
  local file,reason=io.open(path,"r")
  if not file then return nil,reason end
  local source=file:read("*a")
  file:close()
  return source
end

local function injectTheme(source)
  local replacement=[[
local ui = dofile("/idkos/system/ui_next.lua")
do
  local themeOk,theme=pcall(dofile,"/idkos/system/theme.lua")
  if themeOk and type(theme)=="table" and type(theme.apply)=="function" then
    ui=theme.apply(ui)
  end
end]]
  local changed=0
  source,changed=source:gsub('local ui = dofile%("/idkos/system/ui_next.lua"%)',replacement,1)
  if changed~=1 then return nil,"could not attach global theme renderer" end
  return source
end

local function loadPatchedCore(path)
  local source,reason=readSource(path)
  if not source then return nil,reason end

  local patchOk,patcher=pcall(dofile,"/idkos/system/shell_patch.lua")
  if patchOk and type(patcher)=="table" and type(patcher.apply)=="function" then
    local patched,patchReason=patcher.apply(source)
    if not patched then return nil,patchReason end
    source=patched
  end

  local themed,themeReason=injectTheme(source)
  if not themed then return nil,themeReason end
  source=themed

  local compiler=loadstring or load
  local chunk,compileReason=compiler(source,"@"..path)
  if not chunk then return nil,compileReason end
  local ok,result=pcall(chunk)
  if not ok then return nil,result end
  return result
end

local function loadCore(path)
  local result,reason
  if path=="/idkos/system/core_next.lua" then
    result,reason=loadPatchedCore(path)
  else
    local ok
    ok,result=pcall(dofile,path)
    if not ok then reason=result result=nil end
  end
  if not result then return nil,reason end
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
