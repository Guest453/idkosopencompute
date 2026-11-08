-- idk VM Manager: built-in cooperative guest machines.
return function(app)
  local vdisk=dofile("/idkos/apps/vm.app/vdisk.lua")
  local machine=dofile("/idkos/apps/vm.app/machine.lua")
  local win=app.window{title="virtual machines",width=80,height=29,bg=0x0d1422}
  local ROOT="/home/VMs"
  local diskSizes={64,128,256,512}
  local memorySizes={256,512,1024}
  local diskIndex,ramIndex=2,1
  local disks,selected={},nil
  local active,mode,nameInput,notice=nil,"browse","","ready"
  local FG,BG,DIM,ACCENT=0xe2e8f0,0x101b2b,0x8aa1bd,0x5ea8ff
  local BOOT=[==[
-- small guest OS bundled with idk VM. Guest programs live inside the VHD.
local gpu=component.gpu
local fs=component.filesystem
gpu.setBackground(0x101827)
gpu.setForeground(0xdde7ff)
local W,H=gpu.getResolution()
local function clear()
  gpu.fill(1,1,W,H," ")
  gpu.set(1,1,"idk VM guest OS  |  type help")
  gpu.set(1,2,"virtual disk: IDK VHD  |  Lua")
end
local cursor=4
local function line(text,color)
  if cursor>H then gpu.copy(1,4,W,H-4,0,-1) cursor=H end
  gpu.setForeground(color or 0xdde7ff)
  gpu.fill(1,cursor,W,1," ")
  gpu.set(1,cursor,tostring(text):sub(1,W))
  cursor=cursor+1
end
local function prompt()
  if cursor>H then gpu.copy(1,4,W,H-4,0,-1) cursor=H end
  gpu.setForeground(0x72b8ff)
  gpu.fill(1,cursor,W,1," ")
  gpu.set(1,cursor,"> ")
end
local function command(raw)
  local cmd,arg=raw:match("^(%S+)%s*(.*)$")
  if cmd=="help" then
    line("help, dir, cat FILE, write FILE TEXT")
    line("run FILE, df, clear, reboot, shutdown")
  elseif cmd=="dir" or cmd=="ls" then
    local found=fs.list("/")
    line(found and table.concat(found,"  ") or "disk unavailable")
  elseif cmd=="cat" then
    local fd=fs.open("/"..arg,"r")
    if not fd then line("file not found") return end
    local data=fs.read(fd,4096)
    fs.close(fd)
    line((data or ""):sub(1,W))
  elseif cmd=="write" then
    local file,text=arg:match("^(%S+)%s+(.+)$")
    if not file then line("usage: write NAME TEXT") return end
    local fd,err=fs.open("/"..file,"w")
    if not fd then line(tostring(err)) return end
    local ok,why=fs.write(fd,text.."\n")
    if ok then ok,why=fs.close(fd) else fs.close(fd) end
    line(ok and "saved to virtual disk" or tostring(why))
  elseif cmd=="run" then
    local f,err=loadfile("/"..arg)
    if not f then line(tostring(err)) return end
    local ok,result=pcall(f)
    if not ok then line("guest error: "..tostring(result)) end
  elseif cmd=="df" then
    line(tostring(fs.spaceUsed()).." / "..tostring(fs.spaceTotal()).." bytes used")
  elseif cmd=="reboot" then
    computer.shutdown(true)
  elseif cmd=="shutdown" or cmd=="halt" then
    computer.shutdown(false)
  elseif cmd=="clear" then
    clear()
    cursor=4
  elseif raw~="" then
    line("unknown command: "..tostring(cmd))
  end
end
clear()
prompt()
local buffer=""
while true do
  local signal,_,char,code=computer.pullSignal()
  if signal=="key_down" then
    if code==28 or char==13 then
      line("> "..buffer,0x82beff)
      command(buffer)
      buffer=""
      prompt()
    elseif code==14 or char==8 then
      buffer=buffer:sub(1,-2)
      prompt()
      gpu.setForeground(0xe3e9f2)
      gpu.set(3,cursor,buffer:sub(-W+3))
    elseif type(char)=="number" and char>=32 and char<=126 and #buffer<120 then
      buffer=buffer..string.char(char)
      prompt()
      gpu.setForeground(0xe3e9f2)
      gpu.set(3,cursor,buffer:sub(-W+3))
    end
  end
end
]==]
  local function filesystemReady()
    if not app.fs.exists("/home") then app.fs.makeDirectory("/home") end
    if not app.fs.exists(ROOT) then app.fs.makeDirectory(ROOT) end
  end
  local function scan()
    filesystemReady()
    local entries={}
    local iterator=app.fs.list(ROOT)
    if iterator then
      for name in iterator do
        name=tostring(name):gsub("/$","")
        if name:match("^[%w_%-]+%.vhd$") then
          entries[#entries+1]=name
        end
      end
    end
    table.sort(entries)
    disks=entries
    if selected and not app.fs.exists(ROOT.."/"..selected) then selected=nil end
    if not selected then selected=disks[1] end
  end
  local function safeName(s)
    return tostring(s or ""):lower():gsub("[^%w_-]","-"):gsub("%-+","-"):sub(1,20)
  end
  local function create()
    local short=safeName(nameInput)
    if short=="" then short="my-vm" end
    local path=ROOT.."/"..short..".vhd"
    if app.fs.exists(path) then notice="VHD already exists" return end
    local disk=vdisk.new(path,diskSizes[diskIndex])
    local ok,why=vdisk.write(disk,"/init.lua",BOOT)
    if not ok then notice=tostring(why) return end
    ok,why=vdisk.save(disk)
    if not ok then notice="VHD creation failed: "..tostring(why) return end
    scan()
    selected=short..".vhd"
    notice="created "..selected
    mode="browse"
    nameInput=""
  end
  local function boot()
    if active then notice="stop the running VM first" return end
    if not selected then notice="select a VHD" return end
    local disk,why=vdisk.load(ROOT.."/"..selected)
    if not disk then notice="VHD error: "..tostring(why) return end
    local displayW=math.max(28,math.min(74,win.width-4))
    local displayH=math.max(10,math.min(18,win.height-11))
    active=machine.start(disk,{width=displayW,height=displayH,
      ram=memorySizes[ramIndex],uptime=app.computer.uptime})
    active.step()
    notice="booted "..selected
  end
  local function stop()
    if not active then notice="no running VM" return end
    local ok,why=active.stop()
    active=nil
    notice=ok and "guest powered off; VHD saved" or ("save failed: "..tostring(why))
  end
  local function delete()
    if active then notice="stop your VM before deleting it" return end
    if not selected then notice="nothing selected" return end
    if mode~="confirm" then mode="confirm" notice="click delete again to confirm" return end
    local ok,why=app.fs.remove(ROOT.."/"..selected)
    notice=ok and "VHD deleted" or tostring(why)
    selected=nil
    mode="browse"
    scan()
  end
  local function draw()
    local w,h=win.width,win.height
    win:reset()
    win:fill(1,1,w,h-1,BG)
    win:fill(1,1,w,3,0x17263b)
    win:text(2,1,"IDK VIRTUAL MACHINES",FG,0x17263b)
    win:text(2,2,"Lua virtual computers  |  VHD-backed  |  cooperative",DIM,0x17263b)
    win:button("create",2,4,9,mode=="naming" and "save VM" or "new VM")
    win:button("boot",12,4,9,"boot")
    win:button("stop",22,4,9,"power off")
    win:button("delete",32,4,10,mode=="confirm" and "confirm" or "delete")
    win:button("disk",43,4,12,"VHD "..diskSizes[diskIndex].."k")
    win:button("memory",56,4,13,"RAM "..memorySizes[ramIndex].."k")
    win:button("refresh",70,4,8,"reload")
    if mode=="naming" then
      win:text(2,6,"name: "..nameInput.."_",ACCENT,BG)
      win:text(29,6,"type, then press enter or save VM",DIM,BG)
    else
      win:text(2,6,active and ("running: "..selected) or ("selected: "..(selected or "none")),ACCENT,BG)
      win:text(w-20,6,active and active.status or "powered off",DIM,BG)
    end
    if not active then
      win:text(2,8,"VIRTUAL HARD DISKS",FG,BG)
      if #disks==0 then
        win:text(2,10,"no VHDs yet. choose new VM to create a bootable guest.",DIM,BG)
      end
      for i=1,math.min(#disks,math.max(1,h-17)) do
        local name=disks[i]
        local highlight=(name==selected)
        local rowY=9+i
        local shade=highlight and 0x254161 or (i%2==0 and 0x15243a or BG)
        win:fill(2,rowY,math.min(w-4,70),1,shade)
        win:text(3,rowY,name,highlight and 0xa9d4ff or FG,shade)
        local size=app.fs.size(ROOT.."/"..name) or 0
        win:text(math.min(w-14,57),rowY,math.floor(size/1024).." KB",DIM,shade)
        win:hit("pick:"..name,2,rowY,math.min(w-4,70),1)
      end
      win:text(2,h-5,"guest hardware: GPU, screen, keyboard, EEPROM, VHD, computer",DIM,BG)
      win:text(2,h-4,"bootable Lua scripts; stock OpenOS compatibility is incomplete",DIM,BG)
    else
      local vm=active
      local y=8
      local height=math.min(vm.height,math.max(1,h-y-3))
      local width=math.min(vm.width,w-4)
      win:fill(2,y,width,height,0x101827)
      if height>=1 and width>=1 then
        win:canvas(2,y,width,height,{
          backgrounds=vm.backgrounds,foregrounds=vm.foregrounds,glyphs=vm.cells})
      end
      win:text(2,h-4,"guest keyboard active | use power off to stop",DIM,BG)
      win:text(math.max(2,w-23),h-4,string.format("VHD %dk / RAM %dk",
        math.floor(vm.disk.limit/1024),math.floor(vm.ram/1024)),DIM,BG)
      if vm.status~="running" then
        win:text(2,h-5,"guest "..vm.status..": "..tostring(vm.error or ""),0xffa0a0,BG)
      end
    end
    win:fill(1,h-2,w,2,0x17263b)
    win:text(2,h-2,tostring(notice):sub(1,w-4),0xc9d9ed,0x17263b)
  end
  scan()
  local lastDraw=0
  while true do
    if active then active.step() end
    local now=app.computer.uptime()
    if now-lastDraw>0.1 or (active and active.dirty) then
      draw()
      if active then active.dirty=false end
      lastDraw=now
    end
    local signal,addr,arg,code=app.pull(0.06)
    if signal=="idk_button" then
      if arg=="create" then
        if mode=="naming" then create() else mode="naming" nameInput="" notice="enter VM name" end
      elseif arg=="boot" then boot()
      elseif arg=="stop" then stop()
      elseif arg=="delete" then delete()
      elseif arg=="disk" then diskIndex=diskIndex%#diskSizes+1 notice="VHD capacity selected"
      elseif arg=="memory" then ramIndex=ramIndex%#memorySizes+1 notice="reported RAM selected"
      elseif arg=="refresh" then scan() notice="VHD library refreshed"
      elseif type(arg)=="string" and arg:sub(1,5)=="pick:" then
        if not active then selected=arg:sub(6) notice="selected "..selected end
      end
      lastDraw=0
    elseif signal=="key_down" then
      if mode=="naming" then
        if code==28 or arg==13 then create()
        elseif code==14 or arg==8 then nameInput=nameInput:sub(1,-2)
        elseif type(arg)=="number" and arg>=32 and arg<=126 and #nameInput<20 then
          nameInput=nameInput..string.char(arg)
        end
        lastDraw=0
      elseif active and active.status=="running" then
        active.pushSignal(signal,addr,arg,code)
      end
    elseif signal=="key_up" and active and active.status=="running" then
      active.pushSignal(signal,addr,arg,code)
    end
  end
end
