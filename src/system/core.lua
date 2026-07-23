local component = require("component")
local computer = require("computer")
local event = require("event")
local filesystem = require("filesystem")
local unicode = require("unicode")
local ui = dofile("/idkos/system/ui.lua")

local core = {
  apps = {}, tasks = {}, windows = {}, nextPid = 100,
  running = true, focused = nil, dragging = nil,
  theme = {desktop=0x111827, panel=0x171a21, window=0x22262e, title=0x30343b, accent=0x3b82f6, text=0xf5f7fa, muted=0x9ca3af, danger=0xef4444}
}

local gpu = component.gpu
local oldW, oldH = gpu.getResolution()
local oldFg, oldBg = gpu.getForeground(), gpu.getBackground()
local W, H

local function sortedWindows()
  local t = {}
  for _, win in pairs(core.windows) do t[#t + 1] = win end
  table.sort(t, function(a,b) return a.z < b.z end)
  return t
end

function core.restore()
  pcall(gpu.setResolution, oldW, oldH)
  gpu.setForeground(oldFg)
  gpu.setBackground(oldBg)
  gpu.fill(1,1,oldW,oldH," ")
end

function core.scanApps()
  core.apps = {}
  local roots = {"/idkos/apps", "/home/Apps"}
  for _, root in ipairs(roots) do
    if filesystem.exists(root) then
      for name in filesystem.list(root) do
        name = name:gsub("/$", "")
        if name:sub(-4) == ".app" then
          local path = filesystem.concat(root, name)
          local mf = filesystem.concat(path, "manifest.lua")
          if filesystem.exists(mf) then
            local ok, manifest = pcall(dofile, mf)
            if ok and type(manifest) == "table" and manifest.id then
              manifest.path = path
              manifest.name = manifest.name or manifest.id
              manifest.entry = manifest.entry or "main.lua"
              core.apps[manifest.id] = manifest
            end
          end
        end
      end
    end
  end
end

local Window = {}
Window.__index = Window
function Window:clear(bg)
  self.bg = bg or self.bg
  self.dirty = true
end
function Window:text(x,y,text,fg,bg)
  self.draws[#self.draws+1] = {kind="text",x=x,y=y,text=tostring(text),fg=fg,bg=bg}
  self.dirty = true
end
function Window:fill(x,y,w,h,bg,char)
  self.draws[#self.draws+1] = {kind="fill",x=x,y=y,w=w,h=h,bg=bg,char=char}
  self.dirty = true
end
function Window:button(id,x,y,w,label)
  self.buttons[id] = {x=x,y=y,w=w,h=1,label=label}
  self.dirty = true
end
function Window:reset()
  self.draws, self.buttons = {}, {}
  self.dirty = true
end
function Window:close()
  core.closeTask(self.pid)
end

function core.createWindow(pid, options)
  options = options or {}
  local width = ui.clip(options.width or 50, 24, W-2)
  local height = ui.clip(options.height or 16, 7, H-2)
  local count = 0 for _ in pairs(core.windows) do count = count + 1 end
  local win = setmetatable({
    pid=pid, title=options.title or "app", x=options.x or (3+(count*3)%math.max(3,W-width-3)),
    y=options.y or (3+(count*2)%math.max(3,H-height-4)), width=width, height=height,
    bg=options.bg or core.theme.window, draws={}, buttons={}, z=computer.uptime(), minimized=false, dirty=true
  }, Window)
  core.windows[pid] = win
  core.focused = pid
  return win
end

local function appApi(task)
  local api = {}
  function api.window(options)
    return core.createWindow(task.pid, options)
  end
  function api.pull(timeout)
    return coroutine.yield("pull", timeout)
  end
  function api.sleep(seconds)
    return coroutine.yield("sleep", seconds or 0)
  end
  function api.yield()
    return coroutine.yield("yield")
  end
  function api.exit()
    return coroutine.yield("exit")
  end
  function api.launch(id) return core.launch(id) end
  function api.kill(pid) return core.closeTask(pid) end
  function api.tasks() return core.tasks end
  function api.apps() return core.apps end
  function api.notify(text) core.notification = {text=tostring(text),untilTime=computer.uptime()+4} end
  function api.theme() return core.theme end
  function api.screen() return W,H end
  api.fs, api.component, api.computer = filesystem, component, computer
  return api
end

function core.launch(id)
  local manifest = core.apps[id]
  if not manifest then return nil, "app not found: " .. tostring(id) end
  local entryPath = filesystem.concat(manifest.path, manifest.entry)
  local ok, entry = pcall(dofile, entryPath)
  if not ok then return nil, entry end
  if type(entry) ~= "function" then return nil, "app entry must return a function" end
  local pid = core.nextPid core.nextPid = pid + 1
  local task = {pid=pid,id=id,name=manifest.name,status="starting",wake=0,queue={},started=computer.uptime(),cpu=0,lastError=nil}
  task.co = coroutine.create(function() return entry(appApi(task)) end)
  core.tasks[pid] = task
  return pid
end

function core.closeTask(pid)
  local task = core.tasks[pid]
  if task then task.status = "terminated" end
  core.tasks[pid] = nil
  core.windows[pid] = nil
  if core.focused == pid then core.focused = nil end
end

local function resumeTask(task, ...)
  local before = computer.uptime()
  local ok, action, arg = coroutine.resume(task.co, ...)
  task.cpu = task.cpu + (computer.uptime() - before)
  if not ok then
    task.lastError = tostring(action)
    core.notification = {text=task.name .. " crashed",untilTime=computer.uptime()+5}
    core.closeTask(task.pid)
    return
  end
  if coroutine.status(task.co) == "dead" or action == "exit" then
    core.closeTask(task.pid)
  elseif action == "sleep" then
    task.status, task.wake = "sleeping", computer.uptime() + (tonumber(arg) or 0)
  elseif action == "pull" then
    task.status, task.deadline = "waiting", arg and (computer.uptime()+arg) or nil
  else
    task.status = "ready"
  end
end

local function dispatch(name, ...)
  for _, task in pairs(core.tasks) do
    task.queue[#task.queue+1] = {name,...}
  end
end

local function scheduler()
  local now = computer.uptime()
  local snapshot = {}
  for _, task in pairs(core.tasks) do snapshot[#snapshot+1]=task end
  for _, task in ipairs(snapshot) do
    if core.tasks[task.pid] then
      if task.status == "starting" or task.status == "ready" then
        resumeTask(task)
      elseif task.status == "sleeping" and now >= task.wake then
        resumeTask(task)
      elseif task.status == "waiting" then
        local ev = table.remove(task.queue,1)
        if ev then resumeTask(task, table.unpack(ev))
        elseif task.deadline and now >= task.deadline then resumeTask(task) end
      end
    end
  end
end

local function drawDesktop()
  ui.fill(gpu,1,1,W,H,core.theme.desktop)
  ui.fill(gpu,1,1,W,1,core.theme.panel)
  ui.text(gpu,2,1," idk os ",core.theme.text,core.theme.accent)
  ui.text(gpu,W-18,1,string.format("mem %d%%",math.floor((1-computer.freeMemory()/computer.totalMemory())*100)),core.theme.muted,core.theme.panel)
  ui.fill(gpu,1,H,W,1,core.theme.panel)
  ui.button(gpu,2,H,10,"apps",false)
  local x=13
  for _, task in pairs(core.tasks) do
    local label=unicode.sub(task.name,1,10)
    ui.button(gpu,x,H,12,label,core.focused==task.pid)
    x=x+13 if x>W-12 then break end
  end
end

local function drawWindow(win)
  if win.minimized then return end
  local x,y,w,h=win.x,win.y,win.width,win.height
  ui.fill(gpu,x,y,w,h,win.bg)
  ui.fill(gpu,x,y,w,1,core.focused==win.pid and core.theme.accent or core.theme.title)
  ui.text(gpu,x+1,y,unicode.sub(win.title,1,w-7),core.theme.text)
  ui.text(gpu,x+w-4,y,"[_]",core.theme.text)
  ui.text(gpu,x+w-1,y,"x",core.theme.text)
  for _, d in ipairs(win.draws) do
    if d.kind=="text" then ui.text(gpu,x+d.x-1,y+d.y,d.text,d.fg or core.theme.text,d.bg or win.bg)
    else ui.fill(gpu,x+d.x-1,y+d.y,d.w,d.h,d.bg or win.bg,d.char) end
  end
  for _, b in pairs(win.buttons) do ui.button(gpu,x+b.x-1,y+b.y,b.w,b.label,false) end
end

local function drawMenu()
  if not core.menu then return end
  local mh=math.min(H-3, 4 + (function() local n=0 for _ in pairs(core.apps) do n=n+1 end return n end)())
  ui.fill(gpu,2,H-mh,30,mh,core.theme.panel)
  ui.text(gpu,4,H-mh+1,"applications",core.theme.text)
  local y=H-mh+3
  local apps={} for _,m in pairs(core.apps) do apps[#apps+1]=m end
  table.sort(apps,function(a,b)return a.name<b.name end)
  core.menuRows={}
  for _,m in ipairs(apps) do
    ui.text(gpu,4,y,"[] "..unicode.sub(m.name,1,23),core.theme.text)
    core.menuRows[y]=m.id y=y+1
  end
end

local function redraw()
  drawDesktop()
  for _,win in ipairs(sortedWindows()) do drawWindow(win) end
  drawMenu()
  if core.notification and computer.uptime()<core.notification.untilTime then
    local text=unicode.sub(core.notification.text,1,W-8)
    ui.fill(gpu,W-#text-5,3,#text+3,3,0x30343b)
    ui.text(gpu,W-#text-4,4,text,core.theme.text)
  end
end

local function handleTouch(_,screen,x,y,button,player)
  if y==H and x<=11 then core.menu=not core.menu return end
  if core.menu and core.menuRows and core.menuRows[y] then
    local pid,reason=core.launch(core.menuRows[y])
    if not pid then core.notification={text=tostring(reason),untilTime=computer.uptime()+5} end
    core.menu=false return
  end
  local wins=sortedWindows()
  for i=#wins,1,-1 do
    local win=wins[i]
    if not win.minimized and ui.inside(x,y,win.x,win.y,win.width,win.height) then
      core.focused=win.pid win.z=computer.uptime()
      if y==win.y and x==win.x+win.width-1 then core.closeTask(win.pid) return end
      if y==win.y and x>=win.x+win.width-4 then win.minimized=true return end
      if y==win.y then core.dragging={pid=win.pid,dx=x-win.x,dy=y-win.y} return end
      for id,b in pairs(win.buttons) do
        if ui.inside(x,y,win.x+b.x-1,win.y+b.y,b.w,b.h) then dispatch("idk_button",win.pid,id,player) return end
      end
      dispatch("touch",screen,x-win.x+1,y-win.y,button,player)
      return
    end
  end
end

local function handleDrag(_,screen,x,y)
  if core.dragging then
    local win=core.windows[core.dragging.pid]
    if win then win.x=ui.clip(x-core.dragging.dx,1,W-win.width+1) win.y=ui.clip(y-core.dragging.dy,2,H-win.height) end
  end
end

function core.run()
  local maxW,maxH=gpu.maxResolution()
  W,H=math.min(maxW,100),math.min(maxH,32)
  gpu.setResolution(W,H)
  gpu.setDepth(math.min(gpu.maxDepth(),8))
  core.scanApps()
  core.launch("files")
  while core.running do
    scheduler()
    redraw()
    local ev={event.pull(0.05)}
    if ev[1] then
      if ev[1]=="touch" then handleTouch(table.unpack(ev))
      elseif ev[1]=="drag" then handleDrag(table.unpack(ev))
      elseif ev[1]=="drop" then core.dragging=nil
      elseif ev[1]=="key_down" and ev[4]==16 and ev[5] then core.running=false
      else dispatch(table.unpack(ev)) end
    end
  end
end

return core
