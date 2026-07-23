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
    desktop=0x102a43, desktopAlt=0x173f5f, panel=0xeef3f8, dock=0x142334,
    window=0xf7f9fc, title=0xdde8f1, accent=0x397fca, text=0x1d2b3a,
    muted=0x617487, lightText=0xf8fbff, danger=0xdd5c68, warning=0xe3ad4d,
    success=0x43a976, shadow=0x0b2033, card=0x235475
  }
}

local gpu = component.gpu
if not gpu then error("primary gpu is unavailable", 0) end
local resolutionOk, oldW, oldH = pcall(gpu.getResolution)
if not resolutionOk or type(oldW)~="number" or type(oldH)~="number" then
  error("primary gpu resolution is unavailable: "..tostring(oldW), 0)
end
local foregroundOk, oldFg, oldFgPalette = pcall(gpu.getForeground)
local backgroundOk, oldBg, oldBgPalette = pcall(gpu.getBackground)
local depthOk, oldDepth = pcall(gpu.getDepth)
local W, H
local display
local mirrors={}
local maxMirrors=3

local function componentAddresses(kind)
  local found,seen={},{}
  local listOk,iterator=pcall(component.list,kind)
  if not listOk or type(iterator)~="function" then return found end
  while true do
    local nextOk,address=pcall(iterator)
    if not nextOk or not address then break end
    if type(address)=="string" and not seen[address] then found[#found+1],seen[address]=address,true end
  end
  table.sort(found)
  return found
end

local function primaryScreen()
  local ok,screen=pcall(gpu.getScreen)
  return ok and screen or nil
end

local function clearMirrors()
  for i=#mirrors,1,-1 do mirrors[i]=nil end
end

-- extra gpus can only drive independent screens; compatible pairs mirror the desktop.
local function configureMirrors(width,height)
  clearMirrors()
  local mainScreen=primaryScreen()
  local addressOk,primaryAddress=pcall(function() return gpu.address end)
  if not addressOk then primaryAddress=nil end
  local occupied={}
  if mainScreen then occupied[mainScreen]=true end
  local candidates={}
  for _,address in ipairs(componentAddresses("gpu")) do
    if address~=primaryAddress then
      local ok,proxy=pcall(component.proxy,address)
      if ok and proxy and proxy~=gpu then
        local screenOk,screen=pcall(proxy.getScreen)
        if screenOk and screen and screen~=mainScreen and not occupied[screen] then occupied[screen]=true candidates[#candidates+1]={address=address,gpu=proxy,screen=screen,bound=true}
        elseif screenOk and not screen then candidates[#candidates+1]={address=address,gpu=proxy,bound=false} end
      end
    end
  end
  local unused={}
  for _,address in ipairs(componentAddresses("screen")) do if not occupied[address] then unused[#unused+1]=address end end
  table.sort(candidates,function(a,b) if a.bound~=b.bound then return a.bound end return a.address<b.address end)
  local primaryDepthOk,primaryDepth=pcall(gpu.getDepth)
  primaryDepth=primaryDepthOk and primaryDepth or 1
  for _,candidate in ipairs(candidates) do
    if #mirrors>=maxMirrors then break end
    local maxOk,maxW,maxH=pcall(candidate.gpu.maxResolution)
    local depthOk,maxDepth=pcall(candidate.gpu.maxDepth)
    if maxOk and depthOk and type(maxW)=="number" and type(maxH)=="number" and type(maxDepth)=="number" and maxW>=width and maxH>=height and maxDepth>=primaryDepth then
      local screen=candidate.screen
      if not screen and #unused>0 then
        screen=table.remove(unused,1)
        local bindOk,bound=pcall(candidate.gpu.bind,screen,false)
        if not bindOk or bound==false then screen=nil end
      end
      if screen then
        local configured=pcall(function()
          local depthSet,depthReason=candidate.gpu.setDepth(primaryDepth)
          if depthSet==false then error(depthReason or "depth rejected") end
          local resolutionSet,resolutionReason=candidate.gpu.setResolution(width,height)
          if resolutionSet==false then error(resolutionReason or "resolution rejected") end
          local actualW,actualH=candidate.gpu.getResolution()
          if actualW~=width or actualH~=height then error("resolution mismatch") end
        end)
        if configured then mirrors[#mirrors+1]={gpu=candidate.gpu,address=candidate.address,screen=screen} end
      end
    end
  end
end

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
  if depthOk then pcall(gpu.setDepth, oldDepth) end
  if foregroundOk then pcall(gpu.setForeground, oldFg, oldFgPalette) end
  if backgroundOk then pcall(gpu.setBackground, oldBg, oldBgPalette) end
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
function Window:icon(x,y,name,color,size)
  self.draws[#self.draws+1] = {kind="icon",x=x,y=y,name=name,color=color,size=size}
  self.dirty = true
end
function Window:button(id,x,y,w,label)
  self.buttons[id] = {x=x,y=y,w=w,h=1,label=label}
  self.dirty = true
end
function Window:reset()
  self.draws, self.buttons, self.canvasCells = {}, {}, 0
  self.dirty = true
end
function Window:size()
  return self.width,math.max(0,self.height-1)
end
-- submit one bounded, flat cell frame. input planes are copied across the app boundary.
function Window:canvas(x,y,width,height,cells)
  x,y=math.floor(tonumber(x) or 1),math.floor(tonumber(y) or 1)
  width,height=math.floor(tonumber(width) or 0),math.floor(tonumber(height) or 0)
  if type(cells)~="table" or type(cells.backgrounds)~="table" then return nil,"invalid canvas" end
  if x<1 or y<1 or x>self.width or y>=self.height then return nil,"canvas origin outside window" end
  local maxWidth,maxHeight=math.max(0,self.width-x+1),math.max(0,self.height-y)
  width,height=math.min(math.max(0,width),maxWidth),math.min(math.max(0,height),maxHeight)
  local count=width*height
  if count<1 or count>math.min(4096,self.width*math.max(0,self.height-1)) or self.canvasCells+count>4096 then return nil,"canvas exceeds window bounds" end
  local backgrounds,foregrounds,glyphs={}, {}, {}
  for i=1,count do
    local bg=tonumber(cells.backgrounds[i])
    backgrounds[i]=(bg and bg>=0 and bg<=0xffffff and bg%1==0) and bg or 0x000000
    local fg=cells.foregrounds and tonumber(cells.foregrounds[i])
    foregrounds[i]=(fg and fg>=0 and fg<=0xffffff and fg%1==0) and fg or nil
    local glyph=cells.glyphs and cells.glyphs[i]
    if glyph~=nil then glyphs[i]=unicode.sub(tostring(glyph),1,1) end
  end
  self.draws[#self.draws+1]={kind="canvas",x=x,y=y,w=width,h=height,backgrounds=backgrounds,foregrounds=foregrounds,glyphs=glyphs}
  self.canvasCells=self.canvasCells+count
  self.dirty=true
  return true
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
  if not limitsOk or type(maxW)~="number" or type(maxH)~="number" then return nil,maxW end
  width=tonumber(width)
  height=tonumber(height)
  if not width or not height then return nil,"invalid resolution" end
  width=ui.clip(math.floor(width),1,maxW)
  height=ui.clip(math.floor(height),1,maxH)
  if setGpu then
    local currentOk,currentW,currentH=pcall(gpu.getResolution)
    if not currentOk then return nil,currentW end
    if width~=currentW or height~=currentH then
      local called,changed,reason=pcall(gpu.setResolution,width,height)
      if not called then return nil,changed end
      if not changed then return nil,reason or "resolution rejected by gpu" end
    end
  end
  local resolutionOk,actualW,actualH=pcall(gpu.getResolution)
  if not resolutionOk then
    if setGpu then pcall(gpu.setResolution,W or oldW,H or oldH) end
    return nil,actualW
  end
  -- mirrors are optional: discovery and configuration cannot reject the primary.
  local mirrorsOk=pcall(configureMirrors,actualW,actualH)
  if not mirrorsOk then clearMirrors() end
  local rendererOk,newDisplay=pcall(ui.renderer,gpu,actualW,actualH,mirrors,function()
    core.notification={text="a mirror display was disconnected",untilTime=computer.uptime()+4}
    core.dirty=true
  end)
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
  if not ok or type(maxW)~="number" or type(maxH)~="number" then return nil,maxW end
  local limits={compact={60,20},balanced={80,25}}
  if mode=="native" or mode=="maximum" then
    local freeOk,freeMemory=pcall(computer.freeMemory)
    local totalOk,totalMemory=pcall(computer.totalMemory)
    local safe,required=ui.memorySafe(maxW,maxH,freeOk and freeMemory,totalOk and totalMemory)
    if not safe then
      local available=tonumber(freeOk and freeMemory) or 0
      return nil,"native resolution is unsafe: "..tostring(math.floor(available)).." bytes free; "..tostring(required or "unknown").." required"
    end
    return useResolution(maxW,maxH,true)
  end
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
    bg=options.bg or core.theme.window, draws={}, buttons={}, canvasCells=0, z=computer.uptime(), minimized=false, dirty=true
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
  function api.focused() local win=core.windows[task.pid] return core.focused==task.pid and win and not win.minimized or false end
  function api.display(mode) return core.setDisplay(mode) end
  function api.displays()
    local result={primary={screen=primaryScreen(),width=W,height=H},mirrors={}}
    for i,mirror in ipairs(mirrors) do result.mirrors[i]={gpu=mirror.address,screen=mirror.screen,width=W,height=H} end
    return result
  end
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

local function drawWallpaper()
  ui.fill(display,1,1,W,H,core.theme.desktop)
  if H<10 then return end
  local animated=display.depth>=4 and display.semiPixels and W>=50 and H>=18
  local phase=animated and math.floor(computer.uptime()*4) or 0
  local horizon=math.floor(H*.46)
  ui.fill(display,1,horizon,W,H-horizon+1,core.theme.desktopAlt)
  local colors={0x194766,0x1c506f,0x215a78}
  for x=1,W do
    local wave=math.floor(math.sin((x+phase*.35)/8)*2+math.sin((x-phase*.2)/17))
    local y=horizon+4+wave
    ui.semiRect(display,x,y*2,1,math.max(1,(H-y+1)*2),colors[math.floor(x/12)%#colors+1],core.theme.desktopAlt)
  end
  local orbX=math.floor(W*.72+math.sin(phase/18)*math.max(2,W*.06))
  local orbY=math.floor(H*.30+math.cos(phase/23)*2)
  for radius=4,1,-1 do
    local color=({0x173b59,0x245f7d,0x3b7892,0x72a9b8})[5-radius]
    ui.semiRect(display,orbX-radius,orbY*2-radius,2*radius+1,2*radius,color,core.theme.desktop)
  end
  local stars=math.min(12,math.floor(W/7))
  for i=1,stars do
    local sx=2+((i*29)%math.max(2,W-3))
    local sy=2+((i*11)%math.max(2,horizon-3))
    if not animated or (phase+i)%10<8 then display.cell(sx,sy,"*",0x8db8cb,core.theme.desktop) end
  end
end

local function drawDesktop()
  drawWallpaper()
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
  if W>=48 and H>=18 then
    local wanted={"files","store","terminal","settings"}
    local tx=3
    for _,id in ipairs(wanted) do
      local manifest=core.apps[id]
       if manifest and tx+10<=W then
         ui.fill(display,tx+1,4,10,6,core.theme.shadow)
         ui.fill(display,tx,3,10,6,core.theme.card)
         ui.image(display,tx+1,3,ui.icon(manifest.icon,manifest.color))
         ui.center(display,tx,8,10,unicode.sub(manifest.name,1,10),core.theme.lightText,core.theme.card)
         core.desktopHits[#core.desktopHits+1]={x=tx,y=3,w=10,h=6,id=id}
         tx=tx+12
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
     ui.image(display,dockX+1,dockY,ui.icon("store",core.menu and core.theme.accent or nil,"small"))
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
       ui.image(display,x+1,dockY,ui.icon(manifest.icon or task.id,manifest.color,"small"))
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
  local focused=core.focused==win.pid
  ui.fill(display,x,y,w,1,focused and core.theme.title or 0xc8d0d8)
  ui.fill(display,x,y,3,1,core.theme.danger)
  ui.fill(display,x+3,y,3,1,core.theme.warning)
  ui.fill(display,x+6,y,3,1,core.theme.success)
  ui.center(display,x,y,3,"x",core.theme.lightText,core.theme.danger)
  ui.center(display,x+3,y,3,"-",core.theme.text,core.theme.warning)
  ui.center(display,x+6,y,3,"+",core.theme.lightText,core.theme.success)
  if w>=12 then ui.center(display,x+9,y,w-9,unicode.sub(win.title,1,math.max(0,w-11)),focused and core.theme.text or core.theme.muted,focused and core.theme.title or 0xc8d0d8) end
  display.pushClip(x,y+1,w,math.max(0,h-1))
  for _, d in ipairs(win.draws) do
    local dx,dy=x+d.x-1,y+d.y
    if d.kind=="text" and d.y>=1 and d.y<h then
      ui.text(display,dx,dy,unicode.sub(d.text,1,math.max(0,w-d.x+1)),d.fg or core.theme.text,d.bg or win.bg)
    elseif d.kind=="fill" and d.y<h and d.y+d.h>0 then
      ui.fill(display,dx,math.max(y+1,dy),math.min(d.w,w-d.x+1),math.min(d.h,y+h-math.max(y+1,dy)),d.bg or win.bg,d.char)
    elseif d.kind=="icon" and d.y>=1 and d.y<h then
      ui.image(display,dx,dy,ui.icon(d.name,d.color,d.size))
    elseif d.kind=="canvas" then
      for py=1,d.h do
        local offset=(py-1)*d.w
        for px=1,d.w do
          local i=offset+px
          display.cell(dx+px-1,dy+py-1,d.glyphs[i] or " ",d.foregrounds[i] or (d.glyphs[i] and 0xffffff) or d.backgrounds[i],d.backgrounds[i])
        end
      end
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
  local launcherCols=math.max(1,math.min(4,math.floor((W-6)/18)))
  local launcherRows=math.ceil(#apps/launcherCols)
  local graphical=W>=44 and H>=17 and launcherRows*7+3<=workspaceBottom()
  if graphical then
    local cols,rows=launcherCols,math.max(1,launcherRows)
    local mw=math.min(W-4,cols*18+3)
    local mh=math.min(workspaceBottom()-2,rows*7+3)
    local mx=math.floor((W-mw)/2)+1
    ui.fill(display,mx+1,3,mw,mh,core.theme.shadow)
    ui.fill(display,mx,2,mw,mh,core.theme.panel)
    ui.text(display,mx+2,2,"applications",core.theme.text,core.theme.panel)
    core.menuBox={x=mx,y=2,w=mw,h=mh}
    for i=1,math.min(#apps,rows*cols) do
      local m=apps[i]
      local col=(i-1)%cols local row=math.floor((i-1)/cols)
       local x=mx+2+col*18 local y=4+row*7
       ui.fill(display,x+1,y+1,16,6,0xcbd7e1)
       ui.fill(display,x,y,16,6,0xf8fafc)
       ui.image(display,x+1,y,ui.icon(m.icon,m.color))
       ui.text(display,x+9,y+1,unicode.sub(m.name,1,8),core.theme.text,0xf8fafc)
       ui.text(display,x+9,y+3,"open  >",core.theme.accent,0xf8fafc)
       core.menuHits[#core.menuHits+1]={x=x,y=y,w=16,h=6,id=m.id}
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

local function acceptedScreen(screen)
  if not screen then return false end
  if screen==primaryScreen() then return true end
  for _,mirror in ipairs(mirrors) do if mirror.screen==screen then return true end end
  return false
end

local function handleTouch(_,screen,x,y,button,player)
  if not acceptedScreen(screen) then return end
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
       if y==win.y and x<win.x+3 then core.closeTask(win.pid) return end
       if y==win.y and x<win.x+6 then win.minimized=true core.dirty=true return end
       if y==win.y and x<win.x+9 then toggleMaximize(win) return end
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
  if not acceptedScreen(screen) then return end
  if core.dragging then
    local win=core.windows[core.dragging.pid]
    if win then win.x=ui.clip(x-core.dragging.dx,1,W-win.width+1) win.y=ui.clip(y-core.dragging.dy,2,workspaceBottom()-win.height+1) core.dirty=true end
  end
end

function core.run()
  local depthOk,maxDepth=pcall(gpu.maxDepth)
  if depthOk and type(maxDepth)=="number" then pcall(gpu.setDepth,math.min(maxDepth,8)) end
  local limitsOk,maxW,maxH=pcall(gpu.maxResolution)
  if not limitsOk or type(maxW)~="number" or type(maxH)~="number" then error("primary gpu limits are unavailable: "..tostring(maxW)) end
  local freeOk,freeMemory=pcall(computer.freeMemory)
  local totalOk,totalMemory=pcall(computer.totalMemory)
  local startupMode=ui.startupDisplayMode(maxW,maxH,freeOk and freeMemory,totalOk and totalMemory)
  local resized,resizeError=core.setDisplay(startupMode)
  if not resized and startupMode~="balanced" then resized,resizeError=core.setDisplay("balanced") end
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
    local animate=display.depth>=4 and display.semiPixels and W>=50 and H>=18
    if dirty or now-lastDraw>=(animate and 0.25 or 1) then redraw() lastDraw=now end
    local ev={event.pull(0.05)}
    if ev[1] then
      if ev[1]=="touch" then handleTouch(table.unpack(ev))
      elseif ev[1]=="drag" then handleDrag(table.unpack(ev))
      elseif ev[1]=="drop" and acceptedScreen(ev[2]) then core.dragging=nil
      elseif ev[1]=="screen_resized" and ev[2]==primaryScreen() then
        if ev[3]~=W or ev[4]~=H then
          local resizeFreeOk,resizeFree=pcall(computer.freeMemory)
          local resizeTotalOk,resizeTotal=pcall(computer.totalMemory)
          local memoryOk=ui.memorySafe(ev[3],ev[4],resizeFreeOk and resizeFree,resizeTotalOk and resizeTotal)
          if memoryOk then useResolution(ev[3],ev[4],false)
          else
            local reduced=core.setDisplay("balanced")
            if not reduced then core.setDisplay("compact") end
          end
        end
      elseif ev[1]=="screen_resized" and acceptedScreen(ev[2]) then
        -- mirror resize events are consequences of configuration; do not rebuild.
      elseif ev[1]=="component_added" or ev[1]=="component_removed" then
        if ev[3]=="gpu" or ev[3]=="screen" then
          local configured=pcall(configureMirrors,W,H)
          if not configured then clearMirrors() end
          if display then display.invalidate() core.dirty=true end
        end
        dispatch(table.unpack(ev))
      elseif ev[1]=="key_down" and ev[4]==16 and keyboard.isControlDown() then core.running=false
      elseif (ev[1]=="key_down" or ev[1]=="key_up" or ev[1]=="clipboard") and core.focused then send(core.focused,table.unpack(ev))
      else dispatch(table.unpack(ev)) end
    end
  end
end

return core
