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
computer.shutdown(false)
]]
assert(diskapi.write(disk,"/init.lua",program))
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
os.remove(disk.path)
os.remove(disk.path..".bak")
print("vm smoke test passed")
