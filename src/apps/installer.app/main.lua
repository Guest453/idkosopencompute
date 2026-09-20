-- installer.lua - copy the running idk os onto a hard disk and boot from it.
--
-- made for machines that run the os from a floppy: the floppy is too small to
-- stage updates or apps, which is why downloads kept dying. this walks the
-- running system tree, erases the picked hard disk, copies init.lua plus the
-- whole /idkos tree (minus update and recovery state), and points the eeprom
-- boot address at the new disk. after a reboot the os runs from the disk with
-- room to actually update.

return function(app)
  local win = app.window{title="idk os installer",width=76,height=22,bg=0xf7f9fc}
  local status = "scanning disks..."
  local busy = true
  local confirm -- id of the disk awaiting a second click
  local disks, chosen

  local function draw()
    local width,height=win.width,win.height
    win:reset()
    win:fill(1,1,width,2,0x26394d)
    win:text(2,1,"idk os installer",0xffffff,0x26394d)
    win:text(2,2,"copy the running system onto a hard disk",0xbdd7ea,0x26394d)
    win:text(3,4,"the picked disk is erased. the floppy or disk this os is",0x617487)
    win:text(3,5,"running from is never touched.",0x617487)
    win:fill(3,7,math.max(1,width-5),3,0xe7eef5)
    win:text(4,8,status,busy and 0xb06b16 or 0x397fca,0xe7eef5)
    if not busy and not chosen then
      local y=11
      for _,disk in ipairs(disks) do
        if y>height-3 then break end
        local label=string.format("%s  %s  %s",
          disk.label~="" and disk.label or "unlabeled disk",
          disk.sizeText,
          disk.boot and "(running system)" or (disk.readonly and "(read only)" or ""))
        win:text(4,y,label,0x1d2b3a,0xf7f9fc)
        if not disk.boot and not disk.readonly and disk.usable then
          win:button("disk:"..disk.address,math.max(46,width-16),y,14,
            confirm==disk.address and "confirm erase" or "install here")
        end
        y=y+1
      end
      if #disks==0 then win:text(4,12,"no other filesystems found - is the hard disk plugged in?",0xc14f5a,0xf7f9fc) end
    end
    if chosen then
      win:text(4,12,"copied "..tostring(chosen.copied).." files to the hard disk.",0x1d2b3a,0xf7f9fc)
      win:text(4,13,"boot address is set. reboot to start the disk install.",0x1d2b3a,0xf7f9fc)
      win:button("reboot",3,height-2,14,"reboot now")
      win:button("close",math.max(20,width-10),height-2,8,"close")
    else
      win:button("refresh",3,height-2,10,"rescan")
      win:button("close",math.max(20,width-10),height-2,8,"close")
    end
  end

  local function diskProxy(address)
    local ok,proxy=pcall(function() return app.component.proxy(address) end)
    if ok and type(proxy)=="table" then return proxy end
    return nil
  end

  local function isRunningSystem(address)
    local proxy=diskProxy(address)
    if not proxy then return false end
    local ok,hasInit=pcall(function() return proxy.exists("/init.lua") end)
    if not ok or not hasInit then return false end
    local ok2,hasRuntime=pcall(function() return proxy.exists("/idkos/system/runtime.lua") end)
    return ok2 and hasRuntime or false
  end

  local function scan()
    busy,status=true,"scanning disks..." draw() app.yield()
    disks={}
    local addresses={}
    local okList,list=pcall(function() return app.component.list("filesystem") end)
    if okList and type(list)=="function" then
      for address in list do addresses[#addresses+1]=address end
    elseif okList and type(list)=="table" then
      for address in pairs(list) do addresses[#addresses+1]=address end
    end
    table.sort(addresses)
    for _,address in ipairs(addresses) do
      local proxy=diskProxy(address)
      if proxy then
        local label, size, used, readonly
        pcall(function() label=proxy.getLabel() or "" end)
        pcall(function() size=proxy.spaceTotal() end)
        pcall(function() used=proxy.spaceUsed() end)
        pcall(function() readonly=proxy.isReadOnly() end)
        local boot=isRunningSystem(address)
        -- the os needs a few hundred kb; anything smaller than 512 kb is a
        -- floppy and will fill up and break updates all over again
        local usable=(tonumber(size) or 0)>=512*1024
        disks[#disks+1]={address=address,label=tostring(label or ""),
          sizeText=string.format("%.1f mb used of %.1f mb",(tonumber(used) or 0)/1048576,(tonumber(size) or 0)/1048576),
          boot=boot,readonly=readonly and true or false,usable=usable,proxy=proxy}
      end
    end
    busy=false
    status=#disks>0 and "pick a hard disk to install onto" or "no filesystems found"
  end

  local function copyTree(source, target, proxy, skip, counter)
    for path in app.fs.list(source) do
      local name=tostring(path):gsub("/$","")
      local from=app.fs.concat(source,name)
      local skipIt=false
      for _,s in ipairs(skip) do if from==s or from:sub(1,#s+1)==s.."/" then skipIt=true break end end
      if not skipIt then
        if app.fs.isDirectory(from) then
          proxy.makeDirectory(target.."/"..name)
          copyTree(from,target.."/"..name,proxy,skip,counter)
        else
          local file,reason=app.fs.open(from,"r")
          if not file then error("cannot read "..from..": "..tostring(reason)) end
          local data,readReason=file:read("*a")
          file:close()
          if not data then error("cannot read "..from..": "..tostring(readReason)) end
          local out,writeReason=proxy.open(target.."/"..name,"w")
          if not out then error("cannot write "..target.."/"..name..": "..tostring(writeReason)) end
          local okWrite=proxy.write(out,data)
          proxy.close(out)
          if not okWrite then error("cannot write "..target.."/"..name) end
          counter.count=counter.count+1
        end
      end
    end
  end

  local function install(disk)
    busy=true status="erasing "..(disk.label~="" and disk.label or "disk").."..." draw() app.yield()
    -- erase: everything on the target goes
    for path in disk.proxy.list("/") do
      local name=tostring(path):gsub("/$","")
      if name~="" and name~="." and name~=".." then
        disk.proxy.remove("/"..name)
      end
    end
    status="copying system files..." draw() app.yield()
    disk.proxy.makeDirectory("/home")
    local counter={count=0}
    local okCopy,copyError=pcall(copyTree,"/idkos","/idkos",disk.proxy,{"/idkos/update","/idkos/recovery"},counter)
    if okCopy then
      local initFile,initReason=disk.proxy.open("/init.lua","w")
      if initFile then
        local init=app.fs.open("/init.lua","r")
        if init then
          local data=init:read("*a")
          init:close()
          if data then disk.proxy.write(initFile,data) counter.count=counter.count+1 end
        end
        disk.proxy.close(initFile)
      else
        okCopy=false copyError="cannot write /init.lua: "..tostring(initReason)
      end
    end
    if not okCopy then
      busy=false status="install failed: "..tostring(copyError).." (disk left erased)" chosen=nil
      return
    end
    local okBoot=pcall(function() app.computer.setBootAddress(disk.address) end)
    if not okBoot then
      busy=false status="copied the files but could not set the boot address" chosen={copied=counter.count}
      return
    end
    chosen={copied=counter.count}
    busy=false status="installed! boot address points at the new disk"
  end

  scan()
  while true do
    draw()
    local name,_,id=app.pull()
    if name=="idk_button" and not busy then
      if id=="close" then return
      elseif id=="reboot" and chosen then app.computer.shutdown(true)
      elseif id=="refresh" and not chosen then confirm=nil scan()
      elseif type(id)=="string" and id:sub(1,6)=="disk:" and not chosen then
        local address=id:sub(7)
        if confirm==address then
          for _,disk in ipairs(disks) do if disk.address==address then install(disk) break end end
          confirm=nil
        else
          confirm=address status="click confirm erase to wipe that disk and install"
        end
      else confirm=nil end
    end
  end
end
