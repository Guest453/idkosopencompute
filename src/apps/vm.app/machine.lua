-- idk VM: a cooperative Lua virtual computer, not a hardware hypervisor.
-- Guests can only see explicitly emulated components and the mounted VHD.
local diskapi = dofile("/idkos/apps/vm.app/vdisk.lua")
local machine = {}
local unpack = table.unpack or unpack

local function componentAddress(which)
  return ({gpu="idkvm-gpu-0001",screen="idkvm-screen-0001",
    filesystem="idkvm-vhd-0001",eeprom="idkvm-eeprom-0001",
    keyboard="idkvm-keyboard-0001"})[which]
end

function machine.start(disk, options)
  options = options or {}
  local W = math.max(28, math.min(74, tonumber(options.width) or 56))
  local H = math.max(10, math.min(25, tonumber(options.height) or 14))
  local ram = math.max(128, math.min(1024, tonumber(options.ram) or 256)) * 1024
  local vm = {disk=disk,width=W,height=H,ram=ram,status="running",
    queue={},dirty=true,started=options.uptime and options.uptime() or 0,
    uptime=options.uptime or function() return 0 end,
    fg=0xdddddd,bg=0x111827, cursorX=1,cursorY=1,
    cells={},foregrounds={},backgrounds={},handles={},nextHandle=1,
    wantSave=false,halted=false}
  local function idx(x,y) return (y-1)*vm.width+x end
  local function within(x,y)
    return type(x)=="number" and type(y)=="number" and x>=1 and y>=1 and x<=vm.width and y<=vm.height
  end
  local function resetScreen()
    for i=1,vm.width*vm.height do
      vm.cells[i]=" "
      vm.foregrounds[i]=vm.fg
      vm.backgrounds[i]=vm.bg
    end
    vm.dirty=true
  end
  resetScreen()
  local function writeCell(x,y,ch)
    if within(x,y) then
      local i=idx(x,y)
      vm.cells[i]=ch
      vm.foregrounds[i]=vm.fg
      vm.backgrounds[i]=vm.bg
      vm.dirty=true
    end
  end
  local gpu={}
  function gpu.getResolution() return vm.width,vm.height end
  function gpu.maxResolution() return 74,25 end
  function gpu.setResolution(w,h)
    w,h=math.floor(tonumber(w) or 0),math.floor(tonumber(h) or 0)
    if w<28 or h<10 or w>74 or h>25 then return nil,"unsupported virtual resolution" end
    -- The VM window owns the size; guests cannot resize the host app window.
    if w~=vm.width or h~=vm.height then return nil,"VM video mode is fixed by the host" end
    return true
  end
  function gpu.getDepth() return 8 end
  function gpu.maxDepth() return 8 end
  function gpu.setDepth(n) return n==8 and 8 or nil end
  function gpu.getScreen() return componentAddress("screen") end
  function gpu.bind(address) return address==componentAddress("screen") end
  function gpu.getForeground() return vm.fg end
  function gpu.getBackground() return vm.bg end
  function gpu.setForeground(v)
    local old=vm.fg
    vm.fg=math.floor(tonumber(v) or old)%0x1000000
    return old
  end
  function gpu.setBackground(v)
    local old=vm.bg
    vm.bg=math.floor(tonumber(v) or old)%0x1000000
    return old
  end
  function gpu.set(x,y,value)
    x,y=math.floor(tonumber(x) or 0),math.floor(tonumber(y) or 0)
    value=tostring(value or "")
    local at=x
    for uchar in value:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      if at>vm.width then break end
      writeCell(at,y,uchar)
      at=at+1
    end
    return true
  end
  function gpu.fill(x,y,w,h,ch)
    x,y,w,h=math.floor(tonumber(x) or 0),math.floor(tonumber(y) or 0),
      math.floor(tonumber(w) or 0),math.floor(tonumber(h) or 0)
    ch=tostring(ch or " "):sub(1,1)
    if w<0 or h<0 or w*h>4096 then return nil,"invalid fill" end
    for row=math.max(1,y),math.min(vm.height,y+h-1) do
      for col=math.max(1,x),math.min(vm.width,x+w-1) do writeCell(col,row,ch) end
    end
    return true
  end
  function gpu.get(x,y)
    if not within(x,y) then return nil end
    local i=idx(x,y)
    return vm.cells[i],vm.foregrounds[i],vm.backgrounds[i]
  end
  function gpu.copy(x,y,w,h,tx,ty)
    local copied={}
    for row=0,math.min(50,math.max(0,h)-1) do
      for col=0,math.min(74,math.max(0,w)-1) do
        local sx,sy=x+col,y+row
        if within(sx,sy) then
          local i=idx(sx,sy)
          copied[#copied+1]={sx+tx,sy+ty,vm.cells[i],vm.foregrounds[i],vm.backgrounds[i]}
        end
      end
    end
    for _,item in ipairs(copied) do
      if within(item[1],item[2]) then
        local i=idx(item[1],item[2])
        vm.cells[i],vm.foregrounds[i],vm.backgrounds[i]=item[3],item[4],item[5]
      end
    end
    vm.dirty=true
    return true
  end
  function gpu.getPaletteColor(n) return tonumber(n) or 0 end
  function gpu.setPaletteColor(n) return tonumber(n) or 0 end

  local volumes={}
  local fs={}
  local function getPath(p)
    local name=diskapi.canon(p)
    if not name then return nil,"invalid guest path" end
    return name
  end
  function fs.exists(p) return diskapi.exists(disk,p) end
  function fs.isDirectory(p) return diskapi.isDirectory(disk,p) end
  function fs.makeDirectory(p)
    local ok,why=diskapi.makeDirectory(disk,p)
    if ok then vm.wantSave=true end
    return ok,why
  end
  function fs.remove(p)
    local ok,why=diskapi.remove(disk,p)
    if ok then vm.wantSave=true end
    return ok,why
  end
  function fs.rename(a,b)
    local ok,why=diskapi.rename(disk,a,b)
    if ok then vm.wantSave=true end
    return ok,why
  end
  function fs.size(p)
    local data=diskapi.read(disk,p)
    return data and #data or 0
  end
  function fs.spaceTotal() return disk.limit end
  function fs.spaceUsed() return diskapi.used(disk) end
  function fs.isReadOnly() return false end
  function fs.getLabel() return "IDK VHD" end
  function fs.setLabel() return nil,"not supported" end
  function fs.list(path)
    return diskapi.list(disk,path)
  end
  function fs.open(path,mode)
    path=getPath(path)
    mode=mode or "r"
    if not path or (mode~="r" and mode~="w" and mode~="a" and mode~="rb") then return nil,"invalid open" end
    if disk.dirs[path] then return nil,"is a directory" end
    local data=disk.files[path]
    if mode=="r" or mode=="rb" then
      if data==nil then return nil,"file not found" end
    elseif not disk.dirs[path:match("^(.*)/[^/]+$") or "/"] then
      return nil,"directory not found"
    end
    local id=vm.nextHandle
    vm.nextHandle=id+1
    if vm.nextHandle>100000 then vm.nextHandle=1 end
    vm.handles[id]={path=path,mode=mode,data=mode=="w" and "" or (data or ""),
      pos=mode=="a" and #(data or "")+1 or 1}
    return id
  end
  function fs.read(id,n)
    local f=vm.handles[id]
    if not f then return nil,"bad file handle" end
    n=math.max(0,math.min(8192,math.floor(tonumber(n) or 2048)))
    if f.pos>#f.data then return nil end
    local data=f.data:sub(f.pos,f.pos+n-1)
    f.pos=f.pos+#data
    return data
  end
  function fs.write(id,data)
    local f=vm.handles[id]
    if not f or f.mode=="r" or f.mode=="rb" then return nil,"file not writable" end
    data=tostring(data or "")
    if #data>8192 then return nil,"write too large" end
    local new=f.data:sub(1,f.pos-1)..data..f.data:sub(f.pos+#data)
    if #new>disk.limit then return nil,"guest file too large" end
    f.data=new
    f.pos=f.pos+#data
    return true
  end
  function fs.seek(id,where,offset)
    local f=vm.handles[id]
    if not f then return nil,"bad file handle" end
    offset=tonumber(offset) or 0
    local target=where=="end" and #f.data+1+offset or
      where=="cur" and f.pos+offset or 1+offset
    f.pos=math.max(1,math.min(#f.data+1,target))
    return f.pos-1
  end
  function fs.close(id)
    local f=vm.handles[id]
    if not f then return nil,"bad file handle" end
    vm.handles[id]=nil
    if f.mode=="w" or f.mode=="a" then
      local ok,why=diskapi.write(disk,f.path,f.data)
      if not ok then return nil,why end
      vm.wantSave=true
    end
    return true
  end

  local eeprom={}
  function eeprom.get() return disk.files["/eeprom.lua"] or "" end
  function eeprom.set(data)
    data=tostring(data or "")
    if #data>4096 then return nil,"EEPROM capacity exceeded" end
    local ok,why=diskapi.write(disk,"/eeprom.lua",data)
    if ok then vm.wantSave=true end
    return ok,why
  end
  function eeprom.getData() return "/init.lua" end
  function eeprom.getSize() return 4096 end
  function eeprom.getDataSize() return 128 end
  function eeprom.setData() return nil,"boot disk is fixed" end
  function eeprom.makeReadonly() return true end

  local screen={getKeyboards=function() return {componentAddress("keyboard")} end,
    isOn=function() return true end,turnOn=function() return true end,
    turnOff=function() return true end}
  local keyboard={isKeyDown=function() return false end}

  local registry={
    [componentAddress("gpu")]={type="gpu",proxy=gpu},
    [componentAddress("screen")]={type="screen",proxy=screen},
    [componentAddress("filesystem")]={type="filesystem",proxy=fs},
    [componentAddress("eeprom")]={type="eeprom",proxy=eeprom},
    [componentAddress("keyboard")]={type="keyboard",proxy=keyboard}}
  local component={}
  function component.list(kind,exact)
    local keys={}
    for address,item in pairs(registry) do
      if kind==nil or item.type==kind or (not exact and item.type:find(tostring(kind),1,true)) then
        keys[#keys+1]=address
      end
    end
    table.sort(keys)
    local n=0
    return function()
      n=n+1
      local addr=keys[n]
      return addr,addr and registry[addr].type or nil
    end
  end
  function component.proxy(address)
    local item=registry[address]
    return item and item.proxy or nil
  end
  function component.type(address) return registry[address] and registry[address].type end
  function component.invoke(address,method,...)
    local obj=component.proxy(address)
    if not obj or type(obj[method])~="function" then return nil,"no such component method" end
    return obj[method](...)
  end
  function component.isAvailable(kind)
    for _,item in pairs(registry) do if item.type==kind then return true end end
    return false
  end
  setmetatable(component,{__index=function(_,name)
    for _,item in pairs(registry) do if item.type==name then return item.proxy end end
  end})

  local computer={}
  function computer.uptime() return vm.uptime()-vm.started end
  function computer.totalMemory() return vm.ram end
  function computer.freeMemory()
    -- A guest-reported budget, not a hard host-allocated or secure RAM quota.
    return math.max(0,vm.ram-diskapi.used(disk)-vm.width*vm.height*12)
  end
  function computer.getBootAddress() return componentAddress("filesystem") end
  function computer.setBootAddress(address) return address==componentAddress("filesystem") end
  function computer.getDeviceInfo() return {} end
  function computer.pullSignal(timeout)
    return coroutine.yield("signal",tonumber(timeout))
  end
  function computer.pushSignal(...)
    if #vm.queue<48 then vm.queue[#vm.queue+1]={...} return true end
    return nil,"signal buffer full"
  end
  function computer.shutdown(reboot)
    return coroutine.yield("shutdown",reboot and true or false)
  end
  function computer.beep()
    vm.beepUntil=vm.uptime()+0.1
    return true
  end

  local env={}
  for _,name in ipairs({"assert","error","ipairs","pairs","next","select","tonumber",
    "tostring","type","pcall","xpcall","setmetatable","getmetatable","rawget",
    "rawset","rawequal","unpack"}) do env[name]=_G[name] end
  env.string,env.table,env.math,env.coroutine=string,table,math,
    {create=coroutine.create,resume=coroutine.resume,status=coroutine.status,
     yield=coroutine.yield,running=coroutine.running,wrap=coroutine.wrap}
  env.component,env.computer,env.unicode=component,computer,unicode
  env._VERSION=_VERSION
  env._G=env
  local guestFs={}
  for name,value in pairs(fs) do guestFs[name]=value end
  function guestFs.list(path)
    local results,reason=fs.list(path)
    if not results then return nil,reason end
    local i=0
    return function() i=i+1 return results[i] end
  end
  function guestFs.concat(...)
    local parts={}
    for i=1,select("#",...) do parts[#parts+1]=tostring(select(i,...)) end
    return diskapi.canon(table.concat(parts,"/"))
  end
  guestFs.canonical=diskapi.canon
  guestFs.path=function(p) local s=diskapi.canon(p) return s and (s:match("^(.*)/[^/]+$") or "/") end
  guestFs.name=function(p) return tostring(p):match("([^/]+)$") end
  env.filesystem=guestFs
  env.keyboard=keyboard
  local function termScroll()
    for y=2,vm.height do
      for x=1,vm.width do
        local from,to=idx(x,y),idx(x,y-1)
        vm.cells[to],vm.foregrounds[to],vm.backgrounds[to]=
          vm.cells[from],vm.foregrounds[from],vm.backgrounds[from]
      end
    end
    for x=1,vm.width do writeCell(x,vm.height," ") end
  end
  local function textOut(data)
    data=tostring(data or "")
    for c in data:gmatch(".") do
      if c=="\n" then vm.cursorX=1 vm.cursorY=vm.cursorY+1
      elseif c=="\r" then vm.cursorX=1
      else
        if vm.cursorX>vm.width then vm.cursorX=1 vm.cursorY=vm.cursorY+1 end
        if vm.cursorY>vm.height then termScroll() vm.cursorY=vm.height end
        writeCell(vm.cursorX,vm.cursorY,c)
        vm.cursorX=vm.cursorX+1
      end
      if vm.cursorY>vm.height then termScroll() vm.cursorY=vm.height end
    end
  end
  env.print=function(...)
    local parts={}
    for i=1,select("#",...) do parts[#parts+1]=tostring(select(i,...)) end
    textOut(table.concat(parts,"\t").."\n")
  end
  env.write=textOut
  local loaded={
    component=component,computer=computer,filesystem=guestFs,keyboard=keyboard,unicode=unicode,
  }
  env.package={loaded=loaded,path="/lib/?.lua;/?.lua"}
  local function guestLoad(path)
    local source,reason=diskapi.read(disk,path)
    if not source then return nil,reason end
    local chunk,err=load(source,"=vm:"..tostring(path),"t",env)
    return chunk,err
  end
  env.loadfile=guestLoad
  env.dofile=function(path)
    local chunk,reason=guestLoad(path)
    if not chunk then error(reason,2) end
    return chunk()
  end
  env.load=function(source,name,mode)
    return load(source,name or "=vm-string",mode or "t",env)
  end
  env.require=function(name)
    if loaded[name]~=nil then return loaded[name] end
    if type(name)~="string" or not name:match("^[%w%._]+$") then error("unsafe guest module name",2) end
    local relative=name:gsub("%.","/")
    for _,path in ipairs({"/lib/"..relative..".lua","/"..relative..".lua"}) do
      if diskapi.exists(disk,path) then
        local value=env.dofile(path)
        loaded[name]=value==nil and true or value
        return loaded[name]
      end
    end
    error("guest module not found: "..name,2)
  end
  local guestIo={}
  function guestIo.open(path,mode)
    local handle,reason=fs.open(path,mode)
    if not handle then return nil,reason end
    local object={}
    function object:read(spec)
      if spec=="*a" then
        local chunks={}
        while true do
          local part=fs.read(handle,4096)
          if not part then break end
          chunks[#chunks+1]=part
        end
        return table.concat(chunks)
      end
      if spec=="*l" or spec==nil then
        local line={}
        while true do
          local c=fs.read(handle,1)
          if not c or c=="\n" then break end
          line[#line+1]=c
        end
        return #line>0 and table.concat(line) or nil
      end
      return fs.read(handle,tonumber(spec) or 2048)
    end
    function object:write(...)
      for i=1,select("#",...) do
        local ok,why=fs.write(handle,tostring(select(i,...)))
        if not ok then return nil,why end
      end
      return self
    end
    function object:close() return fs.close(handle) end
    function object:seek(way,off) return fs.seek(handle,way,off) end
    return object
  end
  function guestIo.write(...) for i=1,select("#",...) do textOut(select(i,...)) end end
  guestIo.stdout={write=function(_,...) guestIo.write(...) end}
  env.io=guestIo
  env.os={clock=computer.uptime,sleep=function(t) return computer.pullSignal(t) end,
    exit=function() return computer.shutdown(false) end}
  env.event={pull=computer.pullSignal,push=computer.pushSignal}

  local function bootChunk()
    local init,reason=guestLoad("/init.lua")
    if not init then error("virtual boot failed: "..tostring(reason),0) end
    return init()
  end
  vm.env=env
  local function newCpu()
    local co=coroutine.create(bootChunk)
    -- When debug hooks are available, stop guest tight loops before they
    -- monopolize the host desktop. This is not a hard memory/security limit.
    if debug and type(debug.sethook)=="function" then
      pcall(debug.sethook,co,function()
        error("guest exceeded CPU instruction budget; yield with computer.pullSignal()",0)
      end,"",150000)
    end
    return co
  end
  vm.co=newCpu()
  function vm.pushSignal(...)
    if #vm.queue<48 then vm.queue[#vm.queue+1]={...} end
  end
  function vm.step()
    if vm.status~="running" then return end
    local now=vm.uptime()
    if vm.waiting then
      if #vm.queue==0 and (not vm.deadline or now<vm.deadline) then return end
    end
    local event
    if #vm.queue>0 then event=table.remove(vm.queue,1) end
    local ok,what,arg
    if event then ok,what,arg=coroutine.resume(vm.co,unpack(event))
    else ok,what,arg=coroutine.resume(vm.co) end
    vm.waiting=false
    vm.deadline=nil
    if not ok then
      vm.status="crashed"
      vm.error=tostring(what):sub(1,320)
      textOut("\nVM FAULT: "..vm.error.."\n")
      return
    end
    if coroutine.status(vm.co)=="dead" then
      vm.status="halted"
      textOut("\nVM POWERED OFF\n")
    elseif what=="shutdown" then
      if arg then
        vm.co=newCpu()
        resetScreen()
        vm.cursorX,vm.cursorY=1,1
      else
        vm.status="halted"
      end
    elseif what=="signal" then
      vm.waiting=true
      local timeout=tonumber(arg)
      if timeout and timeout>=0 then vm.deadline=now+math.min(timeout,3600) end
    end
    if vm.wantSave then
      local saved,err=diskapi.save(disk)
      if not saved then vm.error="VHD write error: "..tostring(err) end
      vm.wantSave=false
    end
  end
  function vm.stop()
    vm.status="halted"
    vm.queue={}
    vm.co=nil
    for id in pairs(vm.handles) do fs.close(id) end
    vm.wantSave=false
    return diskapi.save(disk)
  end
  return vm
end
return machine
