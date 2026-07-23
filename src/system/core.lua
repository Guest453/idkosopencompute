local component = require("component")
local computer = require("computer")
local event = require("event")
local filesystem = require("filesystem")
local keyboard = require("keyboard")
local unicode = require("unicode")
local ui = dofile("/idkos/system/ui.lua")

local core = {
  apps = {}, tasks = {}, windows = {}, nextPid = 100,
  running = true, focused = nil, dragging = nil, dirty = true,
  theme = {
    desktop=0x173554, desktopAlt=0x214d70, panel=0xe9eef4, dock=0x172332,
    window=0xf4f7fa, title=0xdce5ee, accent=0x4287d6, text=0x202b36,
    muted=0x657483, lightText=0xf7f9fb, danger=0xe76568, warning=0xe7b34f,
    success=0x56b47b, shadow=0x10263b, card=0x285878
  }
}

local gpu = component.gpu
local oldW, oldH = gpu.getResolution()
local oldFg, oldFgPalette = gpu.getForeground()
local oldBg, oldBgPalette = gpu.getBackground()
local oldDepth = gpu.getDepth()
local W, H
local display

local function dockHeight() return H and H>=16 and 3 or 1 end
local function workspaceBottom() return math.max(2,H-dockHeight()) end

local function sortedWindows()
  local t = {}
  for _, win in pairs(core.windows) do t[#t + 1] = win end
  table.sort(t, function(a,b) return a.z < b.z end)
  return t
end

function core.restore()
  pcall(gpu.setResolution, oldW, oldH)
  pcall(gpu.setDepth, oldDepth)
  pcall(gpu.setForeground, oldFg, oldFgPalette)
  pcall(gpu.setBackground, oldBg, oldBgPalette)
  pcall(gpu.fill, 1,1,oldW,oldH," ")
end

function core.scanApps()
  core.apps = {}
  local roots = {"/idkos/apps", "/home/Apps"}
  for _, root in ipairs(roots) do
    if filesystem.exists(root) then
      local iterator = filesystem.list(root)
      for name in iterator or function() end do
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
              if type(manifest.icon)~="string" then manifest.icon=manifest.id end
              if type(manifest.color)~="number" or manifest.color<0 or manifest.color>0xffffff then manifest.color=nil end
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

local function fitWindows()
  for _,win in pairs(core.windows) do
    if win.maximized then
      win.x,win.y,win.width,win.height=1,2,W,math.max(1,workspaceBottom()-1)
    else
      win.width=ui.clip(win.width,math.min(24,math.max(1,W-2)),math.max(1,W-2))
      win.height=ui.clip(win.height,math.min(7,math.max(1,workspaceBottom()-1)),math.max(1,workspaceBottom()-1))
      win.x=ui.clip(win.x,1,math.max(1,W-win.width+1))
      win.y=ui.clip(win.y,2,math.max(2,workspaceBottom()-win.height+1))
    end
    win.dirty=true
  end
end

local function toggleMaximize(win)
  if win.maximized then
    local restore=win.restoreGeometry
    if restore then win.x,win.y,win.width,win.height=table.unpack(restore) end
    win.maximized,win.restoreGeometry=false,nil
  else
    win.restoreGeometry={win.x,win.y,win.width,win.height}
    win.x,win.y,win.width,win.height=1,2,W,math.max(1,workspaceBottom()-1)
    win.maximized=true
  end
  fitWindows()
  core.dirty=true
end

local function useResolution(width,height,setGpu)
  local limitsOk,maxW,maxH=pcall(gpu.maxResolution)
  if not limitsOk then return nil,maxW end
  width=tonumber(width)
  height=tonumber(height)
  if not width or not height then return nil,"invalid resolution" end
  width=ui.clip(math.floor(width),1,maxW)
  height=ui.clip(math.floor(height),1,maxH)
  if setGpu and (width~=W or height~=H) then
    local called,changed,reason=pcall(gpu.setResolution,width,height)
    if not called then return nil,changed end
    if not changed then return nil,reason or "resolution rejected by gpu" end
  end
  local resolutionOk,actualW,actualH=pcall(gpu.getResolution)
  if not resolutionOk then
    if setGpu then pcall(gpu.setResolution,W or oldW,H or oldH) end
    return nil,actualW
  end
  local rendererOk,newDisplay=pcall(ui.renderer,gpu,actualW,actualH)
  if not rendererOk then
    if setGpu then pcall(gpu.setResolution,W or oldW,H or oldH) end
    return nil,newDisplay
  end
  W,H=actualW,actualH
  display=newDisplay
  fitWindows()
  core.dirty=true
  return true
end

function core.setDisplay(mode)
  local ok,maxW,maxH=pcall(gpu.maxResolution)
  if not ok then return nil,maxW end
  local limits={compact={60,20},balanced={80,25}}
  if mode=="native" or mode=="maximum" then return useResolution(maxW,maxH,true) end
  local size=limits[mode]
  if not size then return nil,"unknown display mode" end
  return useResolution(math.min(maxW,size[1]),math.min(maxH,size[2]),true)
end

function core.createWindow(pid, options)
  options = options or {}
  local width = ui.clip(options.width or 50, math.min(24,math.max(1,W-2)), math.max(1,W-2))
  local height = ui.clip(options.height or 16, math.min(7,math.max(1,workspaceBottom()-1)), math.max(1,workspaceBottom()-1))
  local count = 0 for _ in pairs(core.windows) do count = count + 1 end
  local win = setmetatable({
    pid=pid, title=options.title or "app", x=options.x or (3+(count*3)%math.max(3,W-width-3)),
    y=options.y or (3+(count*2)%math.max(3,H-height-4)), width=width, height=height,
    bg=options.bg or core.theme.window, draws={}, buttons={}, z=computer.uptime(), minimized=false, dirty=true
  }, Window)
  core.windows[pid] = win
  fitWindows()
  core.focused = pid
  core.dirty = true
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
  function api.notify(text) core.notification = {text=tostring(text),untilTime=computer.uptime()+4} core.dirty=true end
  function api.theme() return core.theme end
  function api.screen() return W,H end
  function api.display(mode) return core.setDisplay(mode) end
  function api.rescanApps() core.scanApps() core.dirty=true end
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
  core.dirty = true
  return pid
end

function core.closeTask(pid)
  local task = core.tasks[pid]
  if task then task.status = "terminated" end
  core.tasks[pid] = nil
  core.windows[pid] = nil
  if core.focused == pid then core.focused = nil end
  core.dirty = true
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

local function send(pid,name,...)
  local task=core.tasks[pid]
  if task then task.queue[#task.queue+1]={name,...} end
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
  ui.fill(display,1,1,W,H,core.theme.desktop)
  if H>=10 then
    ui.fill(display,1,math.floor(H*.48),W,H-math.floor(H*.48)+1,core.theme.desktopAlt)
    local base=core.theme.desktopAlt
    for i=0,math.min(10,math.floor(W/8)) do
      local ax=W-i*7
      ui.semiRect(display,ax,math.max(4,H*2-12-i),math.min(7,W-ax+1),4,0x2b6183,base)
    end
    ui.semiRect(display,1,math.floor(H*.8),math.max(6,math.floor(W*.22)),5,0x286080,core.theme.desktop)
  end
  ui.fill(display,1,1,W,1,core.theme.panel)
  ui.fill(display,1,1,7,1,core.theme.accent)
  ui.text(display,2,1,"idk os",core.theme.lightText,core.theme.accent)
  if W>=16 then ui.text(display,10,1,"apps",core.theme.text,core.theme.panel) end
  local focused=core.focused and core.tasks[core.focused]
  if focused and W>=34 then ui.text(display,17,1,unicode.sub(focused.name,1,16),core.theme.muted,core.theme.panel) end
  if W>=30 then
    local memory=math.floor((1-computer.freeMemory()/computer.totalMemory())*100)
    local status=string.format("mem %d%%",memory)
    ui.text(display,W-unicode.len(status)-1,1,status,core.theme.muted,core.theme.panel)
  end
  core.desktopHits={}
  if W>=42 and H>=18 then
    local wanted={"files","store","terminal","settings"}
    local tx=3
    for _,id in ipairs(wanted) do
      local manifest=core.apps[id]
      if manifest and tx+8<=W then
        ui.fill(display,tx,3,9,5,core.theme.card)
        ui.image(display,tx+2,4,ui.icon(manifest.icon,manifest.color))
        ui.center(display,tx,7,9,unicode.sub(manifest.name,1,9),core.theme.lightText,core.theme.card)
        core.desktopHits[#core.desktopHits+1]={x=tx,y=3,w=9,h=5,id=id}
        tx=tx+11
      end
    end
  end
end

local function drawDock()
  local tasks={}
  for _,task in pairs(core.tasks) do tasks[#tasks+1]=task end
  table.sort(tasks,function(a,b) return a.pid<b.pid end)
  local dh=dockHeight()
  local unit=dh==3 and 7 or 11
  local visible=math.min(#tasks,math.max(0,math.floor((W-8)/unit)))
  local dockWidth=7+visible*unit
  local dockX=math.max(1,math.floor((W-dockWidth)/2)+1)
  local dockY=H-dh+1
  if dockX>1 then ui.fill(display,dockX-1,dockY-1,math.min(W-dockX+2,dockWidth+2),1,core.theme.shadow) end
  ui.fill(display,dockX,dockY,dockWidth,dh,core.theme.dock)
  core.appsButton={x=dockX,y=dockY,w=7,h=dh}
  core.taskButtons={}
  if dh==1 then
    ui.button(display,dockX,H,7,"apps",core.menu,core.theme.accent,core.theme.dock)
  else
    ui.image(display,dockX+1,dockY,ui.icon("store",core.menu and core.theme.accent or 0x6885a0))
  end
  local x=dockX+7
  for i=1,visible do
    local task=tasks[i]
    local manifest=core.apps[task.id] or {}
    if dh==1 then
      ui.button(display,x,H,10,unicode.sub(task.name,1,9),core.focused==task.pid,core.theme.accent,core.theme.dock)
      core.taskButtons[#core.taskButtons+1]={x=x,y=H,w=10,h=1,pid=task.pid}
    else
      local tile=core.focused==task.pid and core.theme.accent or core.theme.dock
      ui.fill(display,x,dockY,7,3,tile)
      ui.image(display,x+1,dockY,ui.icon(manifest.icon or task.id,manifest.color))
      core.taskButtons[#core.taskButtons+1]={x=x,y=dockY,w=7,h=3,pid=task.pid}
    end
    x=x+unit
  end
end

local function drawWindow(win)
  if win.minimized then return end
  local x,y,w,h=win.x,win.y,win.width,win.height
  if x+w<=W then ui.fill(display,x+w,y+1,1,math.min(h,H-y),core.theme.shadow) end
  if y+h<=workspaceBottom() then ui.fill(display,x+1,y+h,math.min(w,W-x),1,core.theme.shadow) end
  ui.fill(display,x,y,w,h,win.bg)
  ui.fill(display,x,y,w,1,core.focused==win.pid and core.theme.title or 0xc9cdd3)
  display.cell(x,y," ",core.theme.text,core.theme.window)
  display.cell(x+w-1,y," ",core.theme.text,core.theme.window)
  ui.text(display,x+1,y,"x",core.theme.lightText,core.theme.danger)
  ui.text(display,x+3,y,"-",core.theme.text,core.theme.warning)
  ui.text(display,x+5,y,"+",core.theme.lightText,core.theme.success)
  if w>=10 then ui.center(display,x+7,y,w-7,unicode.sub(win.title,1,math.max(0,w-9)),core.theme.text,core.focused==win.pid and core.theme.title or 0xc9cdd3) end
  display.pushClip(x,y+1,w,math.max(0,h-1))
  for _, d in ipairs(win.draws) do
    local dx,dy=x+d.x-1,y+d.y
    if d.kind=="text" and d.y>=1 and d.y<h then
      ui.text(display,dx,dy,unicode.sub(d.text,1,math.max(0,w-d.x+1)),d.fg or core.theme.text,d.bg or win.bg)
    elseif d.kind=="fill" and d.y<h and d.y+d.h>0 then
      ui.fill(display,dx,math.max(y+1,dy),math.min(d.w,w-d.x+1),math.min(d.h,y+h-math.max(y+1,dy)),d.bg or win.bg,d.char)
    end
  end
  for _, b in pairs(win.buttons) do
    if b.y>=1 and b.y<h and b.x<=w then ui.button(display,x+b.x-1,y+b.y,math.min(b.w,w-b.x+1),b.label,false) end
  end
  display.popClip()
end

local function drawMenu()
  if not core.menu then return end
  local apps={} for _,m in pairs(core.apps) do apps[#apps+1]=m end
  table.sort(apps,function(a,b)return a.name<b.name end)
  core.menuHits={}
  local launcherCols=math.max(1,math.min(4,math.floor((W-6)/17)))
  local launcherRows=math.ceil(#apps/launcherCols)
  local graphical=W>=40 and H>=15 and launcherRows*4+3<=workspaceBottom()
  if graphical then
    local cols,rows=launcherCols,math.max(1,launcherRows)
    local mw=math.min(W-4,cols*17+3)
    local mh=math.min(workspaceBottom()-2,rows*4+3)
    local mx=math.floor((W-mw)/2)+1
    ui.fill(display,mx+1,3,mw,mh,core.theme.shadow)
    ui.fill(display,mx,2,mw,mh,core.theme.panel)
    ui.text(display,mx+2,2,"applications",core.theme.text,core.theme.panel)
    core.menuBox={x=mx,y=2,w=mw,h=mh}
    for i=1,math.min(#apps,rows*cols) do
      local m=apps[i]
      local col=(i-1)%cols local row=math.floor((i-1)/cols)
      local x=mx+2+col*17 local y=4+row*4
      ui.fill(display,x,y,15,4,0xf8fafc)
      ui.image(display,x+1,y,ui.icon(m.icon,m.color))
      ui.text(display,x+7,y+1,unicode.sub(m.name,1,7),core.theme.text,0xf8fafc)
      ui.text(display,x+7,y+2,"open",core.theme.accent,0xf8fafc)
      core.menuHits[#core.menuHits+1]={x=x,y=y,w=15,h=4,id=m.id}
    end
  else
    local mh=math.min(workspaceBottom()-1,2+#apps)
    local mw=math.min(30,W-2)
    ui.fill(display,2,2,mw,mh,core.theme.panel)
    core.menuBox={x=2,y=2,w=mw,h=mh}
    ui.text(display,4,2,"applications",core.theme.text,core.theme.panel)
    for i,m in ipairs(apps) do
      local y=2+i
      if y<2+mh then
        ui.text(display,4,y,unicode.sub(m.name,1,mw-4),core.theme.text,core.theme.panel)
        core.menuHits[#core.menuHits+1]={x=2,y=y,w=mw,h=1,id=m.id}
      end
    end
  end
end

local function redraw()
  display.beginFrame()
  drawDesktop()
  for _,win in ipairs(sortedWindows()) do drawWindow(win) end
  drawMenu()
  drawDock()
  if core.notification and computer.uptime()<core.notification.untilTime then
    local text=unicode.sub(core.notification.text,1,math.max(1,W-8))
    local length=unicode.len(text)
    local nx=math.max(1,W-length-5)
    ui.fill(display,nx,3,math.min(W,length+3),3,core.theme.dock)
    ui.text(display,nx+1,4,text,core.theme.lightText,core.theme.dock)
  end
  display.flush()
  core.dirty=false
  for _,win in pairs(core.windows) do win.dirty=false end
end

local function handleTouch(_,screen,x,y,button,player)
  if screen~=gpu.getScreen() then return end
  if (y==1 and x>=9 and x<=15) or (core.appsButton and ui.inside(x,y,core.appsButton.x,core.appsButton.y,core.appsButton.w,core.appsButton.h)) then
    core.menu=not core.menu core.dirty=true return
  end
  for _,item in ipairs(core.taskButtons or {}) do
    if ui.inside(x,y,item.x,item.y,item.w,item.h) then
      local win=core.windows[item.pid]
      if win then win.minimized=false win.z=computer.uptime() end
      core.focused=item.pid core.menu=false core.dirty=true
      return
    end
  end
  if core.menu and core.menuBox and ui.inside(x,y,core.menuBox.x,core.menuBox.y,core.menuBox.w,core.menuBox.h) then
    for _,item in ipairs(core.menuHits or {}) do
      if ui.inside(x,y,item.x,item.y,item.w,item.h) then
        local pid,reason=core.launch(item.id)
        if not pid then core.notification={text=tostring(reason),untilTime=computer.uptime()+5} end
        core.menu=false core.dirty=true return
      end
    end
    return
  end
  local wins=sortedWindows()
  for i=#wins,1,-1 do
    local win=wins[i]
    if not win.minimized and ui.inside(x,y,win.x,win.y,win.width,win.height) then
      core.focused=win.pid win.z=computer.uptime() core.dirty=true
      if y==win.y and x==win.x+1 then core.closeTask(win.pid) return end
      if y==win.y and x==win.x+3 then win.minimized=true core.dirty=true return end
      if y==win.y and x==win.x+5 then toggleMaximize(win) return end
      if y==win.y then core.dragging={pid=win.pid,dx=x-win.x,dy=y-win.y} return end
      for id,b in pairs(win.buttons) do
        if ui.inside(x,y,win.x+b.x-1,win.y+b.y,b.w,b.h) then send(win.pid,"idk_button",win.pid,id,player) return end
      end
      send(win.pid,"touch",screen,x-win.x+1,y-win.y,button,player)
      return
    end
  end
  for _,item in ipairs(core.desktopHits or {}) do
    if ui.inside(x,y,item.x,item.y,item.w,item.h) then
      local pid,reason=core.launch(item.id)
      if not pid then core.notification={text=tostring(reason),untilTime=computer.uptime()+5} end
      core.dirty=true return
    end
  end
end

local function handleDrag(_,screen,x,y)
  if core.dragging then
    local win=core.windows[core.dragging.pid]
    if win then win.x=ui.clip(x-core.dragging.dx,1,W-win.width+1) win.y=ui.clip(y-core.dragging.dy,2,workspaceBottom()-win.height+1) core.dirty=true end
  end
end

function core.run()
  local depthOk,maxDepth=pcall(gpu.maxDepth)
  if depthOk then pcall(gpu.setDepth,math.min(maxDepth,8)) end
  local resized,resizeError=core.setDisplay("native")
  if not resized then resized,resizeError=core.setDisplay("balanced") end
  if not resized then resized,resizeError=core.setDisplay("compact") end
  if not resized then
    local currentOk,currentW,currentH=pcall(gpu.getResolution)
    if currentOk then resized,resizeError=useResolution(currentW,currentH,false) end
  end
  if not resized then error("could not configure display: "..tostring(resizeError)) end
  core.scanApps()
  core.launch("files")
  local lastDraw=0
  while core.running do
    scheduler()
    local now=computer.uptime()
    local dirty=core.dirty
    if not dirty then for _,win in pairs(core.windows) do if win.dirty then dirty=true break end end end
    if dirty or now-lastDraw>=1 then redraw() lastDraw=now end
    local ev={event.pull(0.05)}
    if ev[1] then
      if ev[1]=="touch" then handleTouch(table.unpack(ev))
      elseif ev[1]=="drag" then handleDrag(table.unpack(ev))
      elseif ev[1]=="drop" then core.dragging=nil
      elseif ev[1]=="screen_resized" and ev[2]==gpu.getScreen() then useResolution(ev[3],ev[4],false)
      elseif ev[1]=="key_down" and ev[4]==16 and keyboard.isControlDown() then core.running=false
      elseif (ev[1]=="key_down" or ev[1]=="key_up" or ev[1]=="clipboard") and core.focused then send(core.focused,table.unpack(ev))
      else dispatch(table.unpack(ev)) end
    end
  end
end

return core
