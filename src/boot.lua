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

local function writeLog(path,message)
  pcall(function()
    local filesystem=require("filesystem")
    local file=filesystem.open(path,"w")
    if file then file:write(tostring(message):sub(1,32768)) file:close() end
  end)
end

local function writeFallbackLog(message)
  writeLog("/idkos/next-core.log",message)
end

local function runUpdateBootstrap()
  local exists=false
  pcall(function()
    local filesystem=require("filesystem")
    exists=filesystem.exists("/idkos/system/update_boot.lua")
  end)
  if not exists then return end

  local loaded,updater=pcall(dofile,"/idkos/system/update_boot.lua")
  if not loaded then
    writeLog("/idkos/update/check.log","update bootstrap load failed:\n"..tostring(updater))
    return
  end
  if type(updater)=="function" then
    local ok,reason=xpcall(updater,traceback)
    if not ok then writeLog("/idkos/update/check.log","update bootstrap failed:\n"..tostring(reason)) end
  end
end

local function kernelPanic(message,phase)
  local loaded,panic=pcall(dofile,"/idkos/system/panic.lua")
  if loaded and type(panic)=="function" then
    return panic(message,{phase=phase or "kernel"})
  end
  error(tostring(message),0)
end

runUpdateBootstrap()

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

local core,nextReason=loadCore("/idkos/system/core_next.lua")
local usingNext=core~=nil
if not core then
  writeFallbackLog("next shell load failed:\n"..tostring(nextReason))
  local oldReason
  core,oldReason=loadCore("/idkos/system/core.lua")
  if not core then kernelPanic("both idk os shells failed: "..tostring(nextReason).."; "..tostring(oldReason),"shell load") end
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

if not success then kernelPanic(reason,"shell runtime") end
