-- Real OpenComputers filesystem discovery with deliberately read-only passthrough.
-- Never mount the host boot volume, and never expose raw proxy/host methods.
local drives = {}

local function call(component,address,method,...)
  if type(address)~="string" or not component then return nil,"no component" end
  local ok,a,b,c=pcall(component.invoke,address,method,...)
  if ok then return a,b,c end
  -- Support host runtime that requires component.proxy.
  local ok2,proxy=pcall(component.proxy,address)
  if ok2 and proxy and type(proxy[method])=="function" then
    local success,x,y,z=pcall(proxy[method],...)
    if success then return x,y,z end
    success,x,y,z=pcall(proxy[method],proxy,...)
    if success then return x,y,z end
  end
  return nil,tostring(a)
end

function drives.discover(component,bootAddress)
  local found={}
  local ok,iterator=pcall(component.list,"filesystem")
  if not ok then return found end
  local addresses={}
  if type(iterator)=="function" then
    for address in iterator do
      if type(address)=="string" then addresses[#addresses+1]=address end
      if #addresses>=32 then break end
    end
  elseif type(iterator)=="table" then
    for a,kind in pairs(iterator) do
      if type(a)=="string" and (kind=="filesystem" or kind==true) then
        addresses[#addresses+1]=a
      end
    end
  end
  table.sort(addresses)
  for _,address in ipairs(addresses) do
    local locked=call(component,address,"isReadOnly")
    local label=call(component,address,"getLabel")
    local space=call(component,address,"spaceTotal")
    local bootable=false
    if locked and address~=bootAddress then
      local handle=call(component,address,"open","/init.lua","r")
      if handle then
        bootable=true
        call(component,address,"close",handle)
      end
    end
    found[#found+1]={
      address=address, label=type(label)=="string" and label or "filesystem",
      size=tonumber(space) or 0, readonly=locked==true,
      host=address==bootAddress, bootable=bootable
    }
  end
  return found
end

function drives.mount(component,info)
  if type(info)~="table" or type(info.address)~="string" or
      info.host or not info.readonly then return nil,"only read-only non-host filesystems can be attached" end
  local address=info.address
  if call(component,address,"isReadOnly")~=true then
    return nil,"selected media is no longer read-only"
  end
  local handles,nextHandle={},1
  local fs={address=address,readonly=true}
  local function invoke(method,...)
    return call(component,address,method,...)
  end
  function fs.isReadOnly() return true end
  function fs.exists(path) return invoke("exists",path) end
  function fs.isDirectory(path) return invoke("isDirectory",path) end
  function fs.size(path) return invoke("size",path) end
  function fs.spaceTotal() return invoke("spaceTotal") end
  function fs.spaceUsed() return invoke("spaceUsed") end
  function fs.getLabel() return info.label end
  function fs.list(path)
    local items,reason=invoke("list",path)
    if not items then return nil,reason end
    local result={}
    if type(items)=="table" then
      for _,name in ipairs(items) do
        result[#result+1]=name
        if #result>=1024 then break end
      end
    elseif type(items)=="function" then
      for name in items do
        result[#result+1]=name
        if #result>=1024 then break end
      end
    end
    return result
  end
  function fs.open(path,mode)
    if mode and mode~="r" and mode~="rb" then return nil,"physical media is read-only" end
    if type(path)~="string" or #path>256 or path:find("%z") then return nil,"invalid guest path" end
    if nextHandle>1024 then return nil,"too many guest file handles" end
    local raw,reason=invoke("open",path,"r")
    if not raw then return nil,reason end
    local id=nextHandle
    nextHandle=id+1
    handles[id]=raw
    return id
  end
  function fs.read(id,length)
    local handle=handles[id]
    if not handle then return nil,"invalid handle" end
    length=math.min(8192,math.max(1,tonumber(length) or 2048))
    return invoke("read",handle,length)
  end
  function fs.close(id)
    local handle=handles[id]
    if not handle then return nil,"invalid handle" end
    handles[id]=nil
    return invoke("close",handle)
  end
  function fs.write() return nil,"physical media is read-only" end
  function fs.remove() return nil,"physical media is read-only" end
  function fs.rename() return nil,"physical media is read-only" end
  function fs.makeDirectory() return nil,"physical media is read-only" end
  function fs.setLabel() return nil,"physical media is read-only" end
  function fs.closeAll()
    for id in pairs(handles) do fs.close(id) end
  end
  return fs
end
return drives
