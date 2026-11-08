-- Runs on Lua 5.3 with a tiny host FS shim; no OpenComputers required.
package.preload.filesystem=function()
  local fs={}
  function fs.exists(path)
    local f=io.open(path,"r")
    if f then f:close() return true end
    return false
  end
  fs.remove=os.remove
  fs.rename=os.rename
  return fs
end
local base="src/apps/vm.app/"
local diskapi=dofile(base.."vdisk.lua")
local disk=diskapi.new("/tmp/idkvm-smoke-test.vhd",64)
local program=[[
local gpu=component.gpu
assert(component.isAvailable("gpu"))
assert(component.proxy(component.list("gpu")())==gpu)
gpu.set(1,1,"HELLO")
local signal,address,char,code=computer.pullSignal()
assert(signal=="key_down")
assert(char==65 and code==30)
gpu.set(1,2,"OK")
local fd=assert(component.filesystem.open("/guest-output.txt","w"))
assert(component.filesystem.write(fd,"saved from guest"))
assert(component.filesystem.close(fd))
computer.shutdown(false)
]]
assert(diskapi.parent("/init.lua")=="/")
assert(diskapi.parent("/other/name.txt")=="/other")
assert(diskapi.write(disk,"/init.lua",program))
assert(diskapi.write(disk,"/root.txt","root data"))
assert(diskapi.rename(disk,"/root.txt","/renamed.txt"))
assert(diskapi.read(disk,"/renamed.txt")=="root data")
assert(diskapi.makeDirectory(disk,"/lib"))
assert(diskapi.write(disk,"/lib/test.lua","return 17"))
assert(diskapi.save(disk))
local loaded=assert(diskapi.load(disk.path))
assert(diskapi.read(loaded,"/lib/test.lua")=="return 17")
local vmCode=assert(io.open(base.."machine.lua","r"))
local src=vmCode:read("*a")
vmCode:close()
-- The production loader uses /idkos/apps/vm.app/vdisk.lua, but this CI
-- harness doesn't install idk OS to the actual root.
local realDofile=dofile
local function fakeDofile(path)
  if path=="/idkos/apps/vm.app/vdisk.lua" then return diskapi end
  return realDofile(path)
end
local env=setmetatable({dofile=fakeDofile},{__index=_G})
local guestMachine=assert(load(src,"=machine.lua","t",env))()
local now=0
local vm=guestMachine.start(loaded,{width=40,height=12,ram=256,uptime=function() return now end})
assert(vm.status=="running")
vm.step()
assert(vm.cells[1]=="H")
assert(vm.waiting==true)
vm.pushSignal("key_down","keyboard",65,30)
vm.step()
assert(vm.cells[1+vm.width]=="O")
assert(vm.status=="halted")
local saved,why=vm.stop()
assert(saved,why)
local reopened=assert(diskapi.load(disk.path))
assert(diskapi.read(reopened,"/init.lua")==program)
assert(diskapi.read(reopened,"/guest-output.txt")=="saved from guest")
assert(diskapi.read(reopened,"/renamed.txt")=="root data")
-- Real filesystem passthrough smoke test: selected read-only OC media should
-- boot its own init.lua, not the bundled fallback script in the VHD.
local drivesFile=assert(io.open(base.."drives.lua","r"))
local drivesSrc=drivesFile:read("*a")
drivesFile:close()
local drives=assert(load(drivesSrc,"=drives.lua","t",_G))()
local media={
  ["/init.lua"]=[[
local gpu=component.gpu
assert(computer.getBootAddress()=="real-floppy-1")
local h=assert(component.invoke("real-floppy-1","open","/boot.lua","r"))
local data=assert(component.invoke("real-floppy-1","read",h,8192))
assert(component.invoke("real-floppy-1","close",h))
assert(data=="FLOPPY")
gpu.set(1,1,"FLOPPY BOOT")
computer.shutdown(false)
]],
  ["/boot.lua"]="FLOPPY",
}
local handles={}
local nextHandle=0
local mock={}
function mock.list(kind)
  local emitted=false
  return function()
    if not emitted and (not kind or kind=="filesystem") then
      emitted=true
      return "real-floppy-1","filesystem"
    end
  end
end
function mock.invoke(address,method,...)
  assert(address=="real-floppy-1")
  local args={...}
  if method=="isReadOnly" then return true end
  if method=="getLabel" then return "OpenOS floppy" end
  if method=="spaceTotal" then return 640*1024 end
  if method=="spaceUsed" then return 7000 end
  if method=="exists" then return media[args[1]]~=nil end
  if method=="isDirectory" then return args[1]=="/" end
  if method=="size" then return #(media[args[1]] or "") end
  if method=="open" then
    if args[2]~="r" or not media[args[1]] then return nil,"not found" end
    nextHandle=nextHandle+1
    handles[nextHandle]={data=media[args[1]],pos=1}
    return nextHandle
  end
  if method=="read" then
    local h=handles[args[1]]
    if not h or h.pos>#h.data then return nil end
    local out=h.data:sub(h.pos,h.pos+args[2]-1)
    h.pos=h.pos+#out
    return out
  end
  if method=="close" then handles[args[1]]=nil return true end
  if method=="list" then return {"init.lua","boot.lua"} end
  return nil,"unsupported"
end
local found=drives.discover(mock,"host-boot")
assert(#found==1 and found[1].bootable and found[1].readonly)
local drive=assert(drives.mount(mock,found[1]))
assert(drive.write("/init.lua","BAD")==nil)
local second=guestMachine.start(reopened,{width=40,height=12,ram=256,
  uptime=function() return now end,drive=drive})
second.step()
assert(second.status=="halted",second.error)
assert(second.cells[1]=="F")
assert(second.cells[2]=="L")
assert(second.bootDevice=="real-floppy-1")
assert(second.stop())
os.remove(disk.path)
os.remove(disk.path..".bak")
print("vm smoke test passed")

