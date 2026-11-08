-- idk VM Manager. Real hardware discovery + guest viewer, not a fake OpenOS shell.
return function(app)
  local vdisk=dofile("/idkos/apps/vm.app/vdisk.lua")
  local machine=dofile("/idkos/apps/vm.app/machine.lua")
  local drives=dofile("/idkos/apps/vm.app/drives.lua")
  local win=app.window{title="virtual machines",width=78,height=23,bg=0x0c1423}
  local ROOT="/home/VMs"
  local diskSizes={64,128,256,512}
  local memorySizes={256,512,1024}
  local diskIndex,ramIndex=2,2
  local selected,tab,mode,nameInput=nil,"machines","browse",""
  local disks,physical,selectedDevice,active={}, {}, nil, nil
  local bootOrder="vhd"
  local scroll,notice,confirm=1,"ready",nil
  local DARK=0x0c1423
  local PANEL=0x162337
  local PANEL2=0x1b2d45
  local WHITE=0xecf3fc
  local MUTED=0x9aaec8
  local BLUE=0x80b7ff
  local CYAN=0x65d9d0
  local GOLD=0xf4c572
  local function clip(s,n)
    return tostring(s or ""):sub(1,math.max(0,n))
  end
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
    local result={}
    local iterator=app.fs.list(ROOT)
    if iterator then
      for file in iterator do
        local name=tostring(file):gsub("/$","")
        if name:match("^[%w_%-]+%.vhd$") then
          result[#result+1]=name
        end
      end
    end
    table.sort(result)
    disks=result
    if selected and not app.fs.exists(ROOT.."/"..selected) then selected=nil end
    if not selected then selected=disks[1] end
  end
  local function scanDevices()
    local bootAddress
    pcall(function() bootAddress=app.computer.getBootAddress() end)
    physical=drives.discover(app.component,bootAddress)
    if selectedDevice then
      local found=false
      for _,item in ipairs(physical) do
        if item.address==selectedDevice then found=true break end
      end
      if not found then selectedDevice=nil end
    end
  end
  local function safeName(s)
    return tostring(s or ""):lower():gsub("[^%w_-]","-"):gsub("%-+","-"):sub(1,20)
  end
  local function create()
    local short=safeName(nameInput)
    if short=="" then notice="enter a name for the VM" return end
    local path=ROOT.."/"..short..".vhd"
    if app.fs.exists(path) then notice="a VM with this name already exists" return end
    local d=vdisk.new(path,diskSizes[diskIndex])
    vdisk.makeDirectory(d,"/lib")
    vdisk.makeDirectory(d,"/bin")
    local ok,reason=vdisk.write(d,"/init.lua",BOOT)
    if ok then ok,reason=vdisk.save(d) end
    if not ok then notice="could not create VHD: "..tostring(reason) return end
    scan()
    selected=short..".vhd"
    mode="browse"
    tab="machines"
    nameInput=""
    notice="created "..selected
  end
  local function selectedHardware()
    for _,device in ipairs(physical) do
      if device.address==selectedDevice then return device end
    end
  end
  local function boot()
    if active and active.status=="running" then notice="shut down the running guest first" return end
    if not selected then notice="create or select a virtual machine" return end
    if active then active.stop() active=nil end
    local disk,err=vdisk.load(ROOT.."/"..selected)
    if not disk then notice="VHD problem: "..tostring(err) return end
    local attachment,bootLabel
    if bootOrder=="floppy" then
      scanDevices()
      local info=selectedHardware()
      if not info then notice="choose a removable filesystem in Devices" tab="devices" return end
      if not info.bootable then notice="selected media has no /init.lua" tab="devices" return end
      attachment,err=drives.mount(app.component,info)
      if not attachment then notice="cannot attach disk: "..tostring(err) return end
      bootLabel=info.label.." (read-only)"
    else
      bootLabel=selected
    end
    active=machine.start(disk,{width=80,height=25,
      ram=memorySizes[ramIndex],drive=attachment,uptime=app.computer.uptime})
    scroll=1
    tab="console"
    active.step()
    notice="boot device: "..bootLabel
  end
  local function stop()
    if not active then notice="there is no running VM" return end
    local ok,err=active.stop()
    active=nil
    notice=ok and "virtual computer powered off; VHD saved"
      or "VHD save failed: "..tostring(err)
  end
  local function remove()
    if active then notice="power off the guest before deleting" return end
    if not selected then notice="select a VM first" return end
    if confirm~=selected then confirm=selected notice="click delete again to erase "..selected return end
    local ok,err=app.fs.remove(ROOT.."/"..selected)
    if not ok then notice="delete failed: "..tostring(err) return end
    confirm=nil
    selected=nil
    scan()
    notice="VM file deleted"
  end
  local function importBoot()
    if active then notice="power off the VM first" return end
    if not selected then notice="select a VM first" return end
    local file=io.open(ROOT.."/guest-init.lua","r")
    if not file then notice="place guest-init.lua in /home/VMs" return end
    local src=file:read("*a") or ""
    file:close()
    if #src<1 or #src>32768 then notice="boot script must fit in 32 KB" return end
    local chunk,err=load(src,"=guest-init","t",{})
    if not chunk then notice="invalid guest script: "..tostring(err):sub(1,40) return end
    local d,reason=vdisk.load(ROOT.."/"..selected)
    if not d then notice=tostring(reason) return end
    local old=vdisk.read(d,"/init.lua")
    if old then
      local ok,why=vdisk.write(d,"/init.bak",old)
      if not ok then notice=tostring(why) return end
    end
    local ok,why=vdisk.write(d,"/init.lua",src)
    if ok then ok,why=vdisk.save(d) end
    notice=ok and "boot script installed; old script saved as /init.bak"
      or "failed to save: "..tostring(why)
  end

  local function action(id,x,y,width,title,activeButton)
    win:button(id,x,y,width,title,activeButton)
  end
  local function panel(x,y,w,h,color)
    if w>0 and h>0 then win:fill(x,y,w,h,color) end
  end
  local function drawMachines(w,h)
    local left=math.max(22,math.min(26,math.floor(w*0.34)))
    panel(2,5,left,h-8,PANEL)
    win:text(3,6,"YOUR MACHINES",WHITE,PANEL)
    win:button("new",3,7,10,mode=="create" and "create" or "new VM")
    if mode=="create" then
      win:text(3,9,"name:",MUTED,PANEL)
      win:text(3,10,clip(nameInput,19).."_",BLUE,PANEL)
      win:text(3,12,"type a name / enter",MUTED,PANEL)
    else
      for i=1,math.min(#disks,math.max(1,h-15)) do
        local item=disks[i]
        local y=8+i
        local shade=item==selected and 0x2d527d or PANEL
        panel(3,y,left-2,1,shade)
        win:text(4,y,clip(item,left-5),item==selected and WHITE or MUTED,shade)
        win:hit("select:"..item,3,y,left-2,1)
      end
      if #disks==0 then win:text(3,9,"no virtual disks",MUTED,PANEL) end
    end

    local x=left+4
    local width=w-x-1
    panel(x,5,width,h-8,PANEL2)
    win:text(x+2,6,"MACHINE DETAILS",WHITE,PANEL2)
    win:text(x+2,8,clip(selected or "none selected",width-4),BLUE,PANEL2)
    local vmStatus=active and active.status or "powered off"
    win:text(x+2,9,vmStatus,active and CYAN or MUTED,PANEL2)
    if h>=19 then
      win:text(x+2,11,"boot: "..(bootOrder=="floppy" and "physical floppy" or "virtual disk"),WHITE,PANEL2)
      win:text(x+2,12,"storage: "..diskSizes[diskIndex].." KB  |  RAM: "..memorySizes[ramIndex].." KB",MUTED,PANEL2)
    end
    local row=h-7
    action("boot",x+2,row,9,"start")
    action("stop",x+12,row,9,"stop")
    action("delete",x+22,row,10,confirm==selected and "confirm" or "delete")
    if h>=19 then
      action("disk",x+2,row+2,13,"VHD "..diskSizes[diskIndex].."K")
      action("ram",x+16,row+2,13,"RAM "..memorySizes[ramIndex].."K")
      action("import",x+30,row+2,10,"import")
    else
      action("disk",x+2,row+2,12,"disk "..diskSizes[diskIndex])
      action("ram",x+15,row+2,12,"RAM "..memorySizes[ramIndex])
      action("import",x+28,row+2,9,"import")
    end
  end
  local function drawDevices(w,h)
    panel(2,5,w-3,h-8,PANEL)
    win:text(4,6,"BOOT DEVICES",WHITE,PANEL)
    win:text(4,7,"host drives are protected; physical media is read-only",MUTED,PANEL)
    action("rescan",w-15,6,12,"scan disks")
    local row=9
    for i=1,math.min(#physical,math.max(1,h-15)) do
      local item=physical[i]
      local match=selectedDevice==item.address
      local shade=match and 0x2d527d or (i%2==0 and 0x1b2d45 or PANEL)
      panel(4,row,w-7,1,shade)
      local label=clip(item.label,17)
      local state=item.host and "HOST" or (not item.readonly and "WRITABLE"
        or (item.bootable and "BOOTABLE" or "NO INIT"))
      win:text(5,row,clip(label,18),match and WHITE or MUTED,shade)
      win:text(25,row,clip(item.address,13),MUTED,shade)
      win:text(math.max(41,w-18),row,clip(state,11),
        item.bootable and CYAN or (item.host and GOLD or MUTED),shade)
      win:hit("drive:"..item.address,4,row,w-7,1)
      row=row+1
    end
    if #physical==0 then win:text(4,9,"no physical filesystem components detected",MUTED,PANEL) end
    local bottom=h-6
    win:text(4,bottom,"boot order",WHITE,PANEL)
    action("vhdfirst",15,bottom,13,"virtual disk",bootOrder=="vhd")
    action("floppyfirst",29,bottom,16,"attached floppy",bootOrder=="floppy")
    win:text(4,h-4,clip("select a read-only disk with /init.lua; then click start",w-8),MUTED,PANEL)
  end
  local function drawConsole(w,h)
    panel(2,5,w-3,h-8,PANEL)
    if not active then
      win:text(4,7,"NO RUNNING GUEST",WHITE,PANEL)
      win:text(4,9,"select a VM in Machines and press start",MUTED,PANEL)
      return
    end
    local vm=active
    local rows=math.min(vm.height,math.max(4,h-11))
    local cols=math.min(vm.width,w-7)
    scroll=math.max(1,math.min(scroll,vm.height-rows+1))
    win:text(4,5,string.format("VIRTUAL GPU  %dx%d    VIEW %d-%d",vm.width,vm.height,
      scroll,scroll+rows-1),MUTED,PANEL)
    action("up",w-17,5,7,"up")
    action("down",w-9,5,7,"down")
    local bg,fg,ch={},{},{}
    for y=1,rows do
      for x=1,cols do
        local source=(scroll+y-2)*vm.width+x
        local at=(y-1)*cols+x
        bg[at]=vm.backgrounds[source] or 0x111827
        fg[at]=vm.foregrounds[source] or WHITE
        ch[at]=vm.cells[source] or " "
      end
    end
    win:canvas(4,6,cols,rows,{backgrounds=bg,foregrounds=fg,glyphs=ch})
    win:text(4,h-4,clip("status: "..vm.status..
      (vm.error and " - "..vm.error or ""),w-8),
      vm.status=="crashed" and 0xff7777 or MUTED,PANEL)
  end
  local function draw()
    local w,h=win.width,win.height
    win:reset()
    panel(1,1,w,h-1,DARK)
    panel(1,1,w,3,PANEL)
    panel(1,1,2,3,0x4e9de7)
    win:text(4,1,"VIRTUAL MACHINES",WHITE,PANEL)
    win:text(4,2,"real devices / virtual hardware",MUTED,PANEL)
    win:text(math.max(5,w-18),2,active and "GUEST ONLINE" or "POWERED OFF",
      active and CYAN or MUTED,PANEL)
    action("machines",3,4,13,"machines",tab=="machines")
    action("devices",17,4,13,"devices",tab=="devices")
    action("console",31,4,13,"console",tab=="console")
    if tab=="devices" then drawDevices(w,h)
    elseif tab=="console" then drawConsole(w,h)
    else drawMachines(w,h) end
    panel(1,h-2,w,2,0x1b2d45)
    win:text(3,h-2,clip(notice,w-6),MUTED,0x1b2d45)
  end

  scan()
  scanDevices()
  local last=0
  while true do
    if active then active.step() end
    local now=app.computer.uptime()
    if now-last>0.15 or (active and active.dirty) then
      draw()
      if active then active.dirty=false end
      last=now
    end
    local signal,addr,arg,code=app.pull(0.08)
    if signal=="idk_button" then
      if arg=="machines" or arg=="devices" or arg=="console" then
        tab=arg
      elseif arg=="new" then
        if mode=="create" then create()
        else nameInput="" mode="create" confirm=nil notice="type the VM name, then press enter" end
      elseif arg=="boot" then boot()
      elseif arg=="stop" then stop()
      elseif arg=="delete" then remove()
      elseif arg=="disk" then diskIndex=diskIndex%#diskSizes+1
      elseif arg=="ram" then ramIndex=ramIndex%#memorySizes+1
      elseif arg=="import" then importBoot()
      elseif arg=="rescan" then scanDevices() notice="hardware list refreshed"
      elseif arg=="vhdfirst" then bootOrder="vhd" notice="booting from virtual hard disk"
      elseif arg=="floppyfirst" then bootOrder="floppy" notice="booting from selected physical floppy"
      elseif arg=="up" then scroll=math.max(1,scroll-3)
      elseif arg=="down" then scroll=scroll+3
      elseif type(arg)=="string" and arg:sub(1,7)=="select:" then
        if not active then selected=arg:sub(8) mode="browse" confirm=nil end
      elseif type(arg)=="string" and arg:sub(1,6)=="drive:" then
        local addr=arg:sub(7)
        for _,dev in ipairs(physical) do
          if dev.address==addr then
            if dev.host then
              notice="this is the host boot disk; it cannot be passed through"
            elseif not dev.readonly then
              notice="writable physical drives cannot be passed through"
            elseif not dev.bootable then
              notice="no /init.lua found on this filesystem"
            else
              selectedDevice=addr
              bootOrder="floppy"
              notice="selected read-only floppy: "..dev.label
            end
            break
          end
        end
      end
      last=0
    elseif signal=="key_down" then
      if mode=="create" and tab=="machines" then
        if code==28 or arg==13 then create()
        elseif code==14 or arg==8 then nameInput=nameInput:sub(1,-2)
        elseif type(arg)=="number" and arg>=32 and arg<=126 and #nameInput<20 then
          nameInput=nameInput..string.char(arg)
        end
        last=0
      elseif tab=="console" and active and active.status=="running" then
        -- Re-map the real keyboard address to the guest's virtual keyboard.
        active.pushSignal("key_down","idkvm-keyboard-0001",arg,code)
      end
    elseif signal=="key_up" and tab=="console" and active and active.status=="running" then
      active.pushSignal("key_up","idkvm-keyboard-0001",arg,code)
    elseif signal=="clipboard" and mode=="create" and tab=="machines" then
      nameInput=(tostring(arg or "")):sub(1,20)
      last=0
    end
  end
end
