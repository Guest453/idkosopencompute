local component = require("component")
local computer = require("computer")
local event = require("event")
local filesystem = require("filesystem")
local keyboard = require("keyboard")
local unicode = require("unicode")
local ui = dofile("/idkos/system/ui_next.lua")

local core = {
  apps={}, tasks={}, windows={}, nextPid=100,
  running=true, focused=nil, dragging=nil, dirty=true, menu=false,
  theme={
    desktop=0x12324b, desktopAlt=0x194b68, panel=0xf2f6fa, panelDark=0xc5d2dd,
    dockTop=0xdde7ef, dockMid=0x879bac, dockBottom=0x34495e,
    window=0xf8fbfd, title=0xdce7ef, accent=0x397fca, text=0x1d2b3a,
    muted=0x617487, lightText=0xffffff, danger=0xe45b67, warning=0xf0b84b,
    success=0x55b978, shadow=0x081923, card=0x245a78
  }
}

local gpu=component.gpu
if not gpu then error("primary gpu is unavailable",0) end
local resolutionOk,oldW,oldH=pcall(gpu.getResolution)
if not resolutionOk then error("gpu resolution is unavailable: "..tostring(oldW),0) end
local foregroundOk,oldFg,oldFgPalette=pcall(gpu.getForeground)
local backgroundOk,oldBg,oldBgPalette=pcall(gpu.getBackground)
local depthOk,oldDepth=pcall(gpu.getDepth)
local W,H,display

local function dockHeight()
  if not H then return 1 end
  if H>=20 then return 5 end
  if H>=15 then return 4 end
  return 1
end
local function workspaceBottom() return math.max(2,H-dockHeight()) end

local function primaryScreen()
  local ok,screen=pcall(gpu.getScreen)
  return ok and screen or nil
end

local function sortedWindows()
  local out={}
  for _,win in pairs(core.windows) do out[#out+1]=win end
  table.sort(out,function(a,b) return a.z<b.z end)
  return out
end

function core.restore()
  pcall(gpu.setResolution,oldW,oldH)
  if depthOk then pcall(gpu.setDepth,oldDepth) end
  if foregroundOk then pcall(gpu.setForeground,oldFg,oldFgPalette) end
  if backgroundOk then pcall(gpu.setBackground,oldBg,oldBgPalette) end
  pcall(gpu.fill,1,1,oldW,oldH," ")
end

function core.scanApps()
  core.apps={}
  for _,root in ipairs({"/idkos/apps","/home/Apps"}) do
    if filesystem.exists(root) then
      local iterator=filesystem.list(root)
      for name in iterator or function() end do
        name=tostring(name):gsub("/$","")
        if name:sub(-4)==".app" then
          local path=filesystem.concat(root,name)
          local mf=filesystem.concat(path,"manifest.lua")
          if filesystem.exists(mf) then
            local ok,manifest=pcall(dofile,mf)
            if ok and type(manifest)=="table" and type(manifest.id)=="string" then
              manifest.path=path
              manifest.name=manifest.name or manifest.id
              manifest.entry=manifest.entry or "main.lua"
              manifest.icon=type(manifest.icon)=="string" and manifest.icon or manifest.id
              if type(manifest.color)~="number" then manifest.color=nil end
              core.apps[manifest.id]=manifest
            end
          end
        end
      end
    end
  end
end

local Window={}
Window.__index=Window
function Window:clear(bg) self.bg=bg or self.bg self.dirty=true end
function Window:text(x,y,text,fg,bg)
  self.draws[#self.draws+1]={kind="text",x=x,y=y,text=tostring(text),fg=fg,bg=bg}
  self.dirty=true
end
function Window:fill(x,y,w,h,bg,char)
  self.draws[#self.draws+1]={kind="fill",x=x,y=y,w=w,h=h,bg=bg,char=char}
  self.dirty=true
end
function Window:icon(x,y,name,color,size)
  self.draws[#self.draws+1]={kind="icon",x=x,y=y,name=name,color=color,size=size}
  self.dirty=true
end
function Window:button(id,x,y,w,label)
  self.buttons[id]={x=x,y=y,w=w,h=1,label=label}
  self.dirty=true
end
function Window:reset() self.draws,self.buttons,self.canvasCells={},{},0 self.dirty=true end
function Window:size() return self.width,math.max(0,self.height-1) end
function Window:canvas(x,y,width,height,cells)
  x,y=math.floor(tonumber(x) or 1),math.floor(tonumber(y) or 1)
  width,height=math.floor(tonumber(width) or 0),math.floor(tonumber(height) or 0)
  if type(cells)~="table" or type(cells.backgrounds)~="table" then return nil,"invalid canvas" end
  local maxWidth,maxHeight=math.max(0,self.width-x+1),math.max(0,self.height-y)
  width,height=math.min(math.max(0,width),maxWidth),math.min(math.max(0,height),maxHeight)
  local count=width*height
  if x<1 or y<1 or count<1 or count>4096 or self.canvasCells+count>4096 then return nil,"canvas exceeds window bounds" end
  local backgrounds,foregrounds,glyphs={},{},{}
  for i=1,count do
    local bg=tonumber(cells.backgrounds[i])
    backgrounds[i]=(bg and bg>=0 and bg<=0xffffff) and bg or 0x000000
    local fg=cells.foregrounds and tonumber(cells.foregrounds[i])
    foregrounds[i]=(fg and fg>=0 and fg<=0xffffff) and fg or nil
    local glyph=cells.glyphs and cells.glyphs[i]
    if glyph~=nil then glyphs[i]=unicode.sub(tostring(glyph),1,1) end
  end
  self.draws[#self.draws+1]={kind="canvas",x=x,y=y,w=width,h=height,backgrounds=backgrounds,foregrounds=foregrounds,glyphs=glyphs}
  self.canvasCells=self.canvasCells+count self.dirty=true return true
end
function Window:close() core.closeTask(self.pid) end

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
    if win.restoreGeometry then win.x,win.y,win.width,win.height=table.unpack(win.restoreGeometry) end
    win.maximized,win.restoreGeometry=false,nil
  else
    win.restoreGeometry={win.x,win.y,win.width,win.height}
    win.x,win.y,win.width,win.height=1,2,W,math.max(1,workspaceBottom()-1)
    win.maximized=true
  end
  fitWindows() core.dirty=true
end

local function useResolution(width,height,setGpu)
  local maxOk,maxW,maxH=pcall(gpu.maxResolution)
  if not maxOk then return nil,maxW end
  width=ui.clip(math.floor(tonumber(width) or 1),1,maxW)
  height=ui.clip(math.floor(tonumber(height) or 1),1,maxH)
  if setGpu then
    local ok,changed,reason=pcall(gpu.setResolution,width,height)
    if not ok or changed==false then return nil,reason or changed end
  end
  local ok,actualW,actualH=pcall(gpu.getResolution)
  if not ok then return nil,actualW end
  local renderOk,newDisplay=pcall(ui.renderer,gpu,actualW,actualH)
  if not renderOk then return nil,newDisplay end
  W,H,display=actualW,actualH,newDisplay
  fitWindows() core.dirty=true return true
end

function core.setDisplay(mode)
  local ok,maxW,maxH=pcall(gpu.maxResolution)
  if not ok then return nil,maxW end
  local limits={compact={60,20},balanced={80,25}}
  if mode=="native" or mode=="maximum" then
    local freeOk,freeMemory=pcall(computer.freeMemory)
    local totalOk,totalMemory=pcall(computer.totalMemory)
    local safe,required=ui.memorySafe(maxW,maxH,freeOk and freeMemory,totalOk and totalMemory)
    if not safe then return nil,"native mode needs "..tostring(required or "more").." bytes" end
    return useResolution(maxW,maxH,true)
  end
  local size=limits[mode]
  if not size then return nil,"unknown display mode" end
  return useResolution(math.min(maxW,size[1]),math.min(maxH,size[2]),true)
end

function core.createWindow(pid,options)
  options=options or {}
  local width=ui.clip(options.width or 52,math.min(24,math.max(1,W-2)),math.max(1,W-2))
  local height=ui.clip(options.height or 17,math.min(7,math.max(1,workspaceBottom()-1)),math.max(1,workspaceBottom()-1))
  local count=0 for _ in pairs(core.windows) do count=count+1 end
  local win=setmetatable({
    pid=pid,title=options.title or "app",x=options.x or (3+(count*3)%math.max(3,W-width-3)),
    y=options.y or (3+(count*2)%math.max(3,H-height-4)),width=width,height=height,
    bg=options.bg or core.theme.window,draws={},buttons={},canvasCells=0,z=computer.uptime(),minimized=false,dirty=true
  },Window)
  core.windows[pid]=win fitWindows() core.focused=pid core.dirty=true return win
end

local function appApi(task)
  local api={}
  function api.window(options) return core.createWindow(task.pid,options) end
  function api.pull(timeout) return coroutine.yield("pull",timeout) end
  function api.sleep(seconds) return coroutine.yield("sleep",seconds or 0) end
  function api.yield() return coroutine.yield("yield") end
  function api.exit() return coroutine.yield("exit") end
  function api.launch(id) return core.launch(id) end
  function api.kill(pid) return core.closeTask(pid) end
  function api.tasks() return core.tasks end
  function api.apps() return core.apps end
  function api.notify(text) core.notification={text=tostring(text),untilTime=computer.uptime()+4} core.dirty=true end
  function api.theme() return core.theme end
  function api.screen() return W,H end
  function api.focused() local win=core.windows[task.pid] return core.focused==task.pid and win and not win.minimized or false end
  function api.display(mode) return core.setDisplay(mode) end
  function api.displays() return {primary={screen=primaryScreen(),width=W,height=H},mirrors={}} end
  function api.rescanApps() core.scanApps() core.dirty=true end
  api.fs,api.component,api.computer=filesystem,component,computer
  return api
end

function core.launch(id)
  local manifest=core.apps[id]
  if not manifest then return nil,"app not found: "..tostring(id) end
  local entryPath=filesystem.concat(manifest.path,manifest.entry)
  local ok,entry=pcall(dofile,entryPath)
  if not ok then return nil,entry end
  if type(entry)~="function" then return nil,"app entry must return a function" end
  local pid=core.nextPid core.nextPid=pid+1
  local task={pid=pid,id=id,name=manifest.name,status="starting",wake=0,queue={},started=computer.uptime(),cpu=0}
  task.co=coroutine.create(function() return entry(appApi(task)) end)
  core.tasks[pid]=task core.focused=pid core.dirty=true return pid
end

function core.closeTask(pid)
  core.tasks[pid]=nil core.windows[pid]=nil
  if core.focused==pid then core.focused=nil end
  core.dirty=true
end

local function resumeTask(task,...)
  local before=computer.uptime()
  local ok,action,arg=coroutine.resume(task.co,...)
  task.cpu=task.cpu+(computer.uptime()-before)
  if not ok then
    core.notification={text=task.name.." crashed: "..unicode.sub(tostring(action),1,38),untilTime=computer.uptime()+6}
    core.closeTask(task.pid) return
  end
  if coroutine.status(task.co)=="dead" or action=="exit" then core.closeTask(task.pid)
  elseif action=="sleep" then task.status,task.wake="sleeping",computer.uptime()+(tonumber(arg) or 0)
  elseif action=="pull" then task.status,task.deadline="waiting",arg and (computer.uptime()+arg) or nil
  else task.status="ready" end
end

local function send(pid,name,...)
  local task=core.tasks[pid]
  if task then task.queue[#task.queue+1]={name,...} end
end
local function dispatch(name,...)
  for _,task in pairs(core.tasks) do task.queue[#task.queue+1]={name,...} end
end
local function scheduler()
  local now=computer.uptime()
  local snapshot={} for _,task in pairs(core.tasks) do snapshot[#snapshot+1]=task end
  for _,task in ipairs(snapshot) do
    if core.tasks[task.pid] then
      if task.status=="starting" or task.status=="ready" then resumeTask(task)
      elseif task.status=="sleeping" and now>=task.wake then resumeTask(task)
      elseif task.status=="waiting" then
        local ev=table.remove(task.queue,1)
        if ev then resumeTask(task,table.unpack(ev))
        elseif task.deadline and now>=task.deadline then resumeTask(task) end
      end
    end
  end
end

local function drawWallpaper()
  ui.fill(display,1,1,W,H,core.theme.desktop)
  local horizon=math.max(4,math.floor(H*0.48))
  ui.fill(display,1,horizon,W,H-horizon+1,core.theme.desktopAlt)
  if H<12 then return end
  local phase=math.floor(computer.uptime()*3)
  for x=1,W do
    local wave=math.floor(math.sin((x+phase)/8)*2+math.sin((x-phase)/19))
    local y=horizon+3+wave
    local color=({0x1c5875,0x236682,0x2b7590})[(math.floor(x/11)%3)+1]
    ui.semiRect(display,x,y*2,1,math.max(1,(H-y+1)*2),color,core.theme.desktopAlt)
  end
  local sunX=math.floor(W*0.73+math.sin(phase/12)*3)
  local sunY=math.max(3,math.floor(H*0.28))
  for radius=3,1,-1 do
    ui.semiRect(display,sunX-radius,sunY*2-radius,2*radius+1,2*radius,({0x315f76,0x5c8797,0xa9ccd5})[4-radius],core.theme.desktop)
  end
end

local function drawDesktop()
  drawWallpaper()
  ui.fill(display,1,1,W,1,core.theme.panel)
  ui.fill(display,1,1,8,1,core.theme.accent)
  ui.text(display,2,1,"idk os",core.theme.lightText,core.theme.accent)
  local focused=core.focused and core.tasks[core.focused]
  if W>=24 then ui.text(display,11,1,focused and unicode.sub(focused.name,1,18) or "finder",core.theme.text,core.theme.panel) end
  if W>=36 then
    local memory=math.floor((1-computer.freeMemory()/computer.totalMemory())*100)
    local text="memory "..memory.."%"
    ui.text(display,W-unicode.len(text)-1,1,text,core.theme.muted,core.theme.panel)
  end
  core.desktopHits={}
  if W>=52 and H>=18 then
    local ids={"files","store"}
    local y=3
    for _,id in ipairs(ids) do
      local m=core.apps[id]
      if m then
        local x=W-9
        ui.fill(display,x+1,y+1,7,7,core.theme.shadow)
        ui.fill(display,x,y,7,7,core.theme.card)
        ui.image(display,x+1,y,ui.icon(m.icon,m.color))
        ui.center(display,x,y+5,7,unicode.sub(m.name,1,7),core.theme.lightText,core.theme.card)
        core.desktopHits[#core.desktopHits+1]={x=x,y=y,w=7,h=7,id=id}
        y=y+8
      end
    end
  end
end

local pinned={"files","store","terminal","settings"}
local function firstTask(id)
  local found
  for _,task in pairs(core.tasks) do if task.id==id and (not found or task.pid<found.pid) then found=task end end
  return found
end

local function dockSlots()
  local slots={{kind="launchpad",id="launchpad",name="apps",icon="launchpad"}}
  local pinnedSet={}
  for _,id in ipairs(pinned) do
    local m=core.apps[id]
    if m then
      pinnedSet[id]=true
      local running=firstTask(id)
      slots[#slots+1]={kind="app",id=id,pid=running and running.pid,name=m.name,icon=m.icon,color=m.color,running=running~=nil}
    end
  end
  local tasks={} for _,task in pairs(core.tasks) do if not pinnedSet[task.id] then tasks[#tasks+1]=task end end
  table.sort(tasks,function(a,b) return a.pid<b.pid end)
  for _,task in ipairs(tasks) do
    local m=core.apps[task.id] or {}
    slots[#slots+1]={kind="task",id=task.id,pid=task.pid,name=task.name,icon=m.icon or task.id,color=m.color,running=true}
  end
  return slots
end

local function drawDock()
  local dh=dockHeight()
  core.dockButtons={}
  if dh==1 then
    ui.fill(display,1,H,W,1,core.theme.dockBottom)
    ui.button(display,2,H,8,"apps",core.menu,core.theme.accent,core.theme.dockBottom)
    core.dockButtons[1]={x=2,y=H,w=8,h=1,kind="launchpad"}
    return
  end
  local slots=dockSlots()
  local slotWidth=6
  local maxSlots=math.max(1,math.floor((W-8)/slotWidth))
  while #slots>maxSlots do table.remove(slots) end
  local width=#slots*slotWidth+4
  local x=math.max(1,math.floor((W-width)/2)+1)
  local y=H-dh+1
  local shelfTop,shelfMid,shelfBottom=H-2,H-1,H
  ui.fill(display,x+2,shelfTop-1,width-4,1,core.theme.shadow)
  ui.fill(display,x+2,shelfTop,width-4,1,core.theme.dockTop)
  ui.fill(display,x+1,shelfMid,width-2,1,core.theme.dockMid)
  ui.fill(display,x,shelfBottom,width,1,core.theme.dockBottom)
  display.cell(x,shelfMid,"/",0xeaf2f7,core.theme.dockMid)
  display.cell(x+width-1,shelfMid,"\\",0xeaf2f7,core.theme.dockMid)
  local sx=x+2
  for _,slot in ipairs(slots) do
    local focused=slot.pid and core.focused==slot.pid
    local iconY=focused and math.max(2,y-1) or y
    if focused then ui.fill(display,sx-1,iconY,5,4,0x4f7fa2) end
    ui.image(display,sx,iconY,ui.icon(slot.icon,slot.color,"dock"))
    if slot.running then display.cell(sx+1,H,".",0xffffff,core.theme.dockBottom) end
    core.dockButtons[#core.dockButtons+1]={x=sx-1,y=math.max(1,iconY),w=5,h=math.min(H-iconY+1,5),kind=slot.kind,id=slot.id,pid=slot.pid}
    sx=sx+slotWidth
  end
end

local function drawWindow(win)
  if win.minimized then return end
  local x,y,w,h=win.x,win.y,win.width,win.height
  if x+w<=W then ui.fill(display,x+w,y+1,1,math.min(h,H-y),core.theme.shadow) end
  if y+h<=workspaceBottom() then ui.fill(display,x+1,y+h,math.min(w,W-x),1,core.theme.shadow) end
  ui.fill(display,x,y,w,h,win.bg)
  local focused=core.focused==win.pid
  ui.fill(display,x,y,w,1,focused and core.theme.title or core.theme.panelDark)
  display.cell(x+1,y,"o",core.theme.lightText,core.theme.danger)
  display.cell(x+3,y,"o",core.theme.text,core.theme.warning)
  display.cell(x+5,y,"o",core.theme.lightText,core.theme.success)
  if w>=10 then ui.center(display,x+7,y,w-7,unicode.sub(win.title,1,math.max(1,w-9)),focused and core.theme.text or core.theme.muted,focused and core.theme.title or core.theme.panelDark) end
  display.pushClip(x,y+1,w,math.max(0,h-1))
  for _,d in ipairs(win.draws) do
    local dx,dy=x+d.x-1,y+d.y
    if d.kind=="text" and d.y>=1 and d.y<h then
      ui.text(display,dx,dy,unicode.sub(d.text,1,math.max(0,w-d.x+1)),d.fg or core.theme.text,d.bg or win.bg)
    elseif d.kind=="fill" and d.y<h and d.y+d.h>0 then
      ui.fill(display,dx,math.max(y+1,dy),math.min(d.w,w-d.x+1),math.min(d.h,y+h-math.max(y+1,dy)),d.bg or win.bg,d.char)
    elseif d.kind=="icon" and d.y>=1 and d.y<h then
      ui.image(display,dx,dy,ui.icon(d.name,d.color,d.size))
    elseif d.kind=="canvas" then
      for py=1,d.h do
        for px=1,d.w do
          local i=(py-1)*d.w+px
          display.cell(dx+px-1,dy+py-1,d.glyphs[i] or " ",d.foregrounds[i] or (d.glyphs[i] and 0xffffff) or d.backgrounds[i],d.backgrounds[i])
        end
      end
    end
  end
  for _,b in pairs(win.buttons) do
    if b.y>=1 and b.y<h and b.x<=w then ui.button(display,x+b.x-1,y+b.y,math.min(b.w,w-b.x+1),b.label,false) end
  end
  display.popClip()
end

local function drawMenu()
  if not core.menu then return end
  local apps={} for _,m in pairs(core.apps) do apps[#apps+1]=m end
  table.sort(apps,function(a,b) return a.name<b.name end)
  core.menuHits={}
  local cols=math.max(1,math.min(5,math.floor((W-6)/12)))
  local rows=math.ceil(#apps/cols)
  local width=math.min(W-4,cols*12+3)
  local height=math.min(workspaceBottom()-2,rows*7+3)
  local x=math.floor((W-width)/2)+1
  local y=2
  ui.fill(display,x+1,y+1,width,height,core.theme.shadow)
  ui.fill(display,x,y,width,height,core.theme.panel)
  ui.text(display,x+2,y,"launchpad",core.theme.text,core.theme.panel)
  core.menuBox={x=x,y=y,w=width,h=height}
  local visible=math.min(#apps,cols*math.max(1,math.floor((height-3)/7)))
  for i=1,visible do
    local m=apps[i]
    local col=(i-1)%cols
    local row=math.floor((i-1)/cols)
    local bx=x+2+col*12
    local by=y+2+row*7
    ui.fill(display,bx,by,10,6,0xf9fbfd)
    ui.image(display,bx+2,by,ui.icon(m.icon,m.color))
    ui.center(display,bx,by+5,10,unicode.sub(m.name,1,10),core.theme.text,0xf9fbfd)
    core.menuHits[#core.menuHits+1]={x=bx,y=by,w=10,h=6,id=m.id}
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
    local width=unicode.len(text)+4
    local x=math.max(1,W-width-1)
    ui.fill(display,x,3,width,3,core.theme.dockBottom)
    ui.text(display,x+2,4,text,core.theme.lightText,core.theme.dockBottom)
  end
  display.flush()
  core.dirty=false
  for _,win in pairs(core.windows) do win.dirty=false end
end

local function acceptedScreen(screen) return not screen or screen==primaryScreen() end

local function focusOrLaunch(button)
  if button.kind=="launchpad" then core.menu=not core.menu core.dirty=true return end
  if button.pid and core.windows[button.pid] then
    local win=core.windows[button.pid]
    win.minimized=false win.z=computer.uptime() core.focused=button.pid core.menu=false core.dirty=true return
  end
  if button.id then
    local pid,reason=core.launch(button.id)
    if not pid then core.notification={text=tostring(reason),untilTime=computer.uptime()+5} end
    core.menu=false core.dirty=true
  end
end

local function handleTouch(_,screen,x,y,button,player)
  if not acceptedScreen(screen) then return end
  if y==1 and x<=9 then core.menu=not core.menu core.dirty=true return end
  for _,item in ipairs(core.dockButtons or {}) do
    if ui.inside(x,y,item.x,item.y,item.w,item.h) then focusOrLaunch(item) return end
  end
  if core.menu and core.menuBox and ui.inside(x,y,core.menuBox.x,core.menuBox.y,core.menuBox.w,core.menuBox.h) then
    for _,item in ipairs(core.menuHits or {}) do
      if ui.inside(x,y,item.x,item.y,item.w,item.h) then focusOrLaunch(item) return end
    end
    return
  elseif core.menu then core.menu=false core.dirty=true end
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
      send(win.pid,"touch",screen,x-win.x+1,y-win.y,button,player) return
    end
  end
  for _,item in ipairs(core.desktopHits or {}) do
    if ui.inside(x,y,item.x,item.y,item.w,item.h) then focusOrLaunch(item) return end
  end
end

local function handleDrag(_,screen,x,y)
  if not acceptedScreen(screen) or not core.dragging then return end
  local win=core.windows[core.dragging.pid]
  if win then
    win.x=ui.clip(x-core.dragging.dx,1,math.max(1,W-win.width+1))
    win.y=ui.clip(y-core.dragging.dy,2,math.max(2,workspaceBottom()-win.height+1))
    core.dirty=true
  end
end

function core.run()
  local depthSet,maxDepth=pcall(gpu.maxDepth)
  if depthSet and type(maxDepth)=="number" then pcall(gpu.setDepth,math.min(maxDepth,8)) end
  local maxOk,maxW,maxH=pcall(gpu.maxResolution)
  if not maxOk then error("gpu limits unavailable: "..tostring(maxW)) end
  local freeOk,freeMemory=pcall(computer.freeMemory)
  local totalOk,totalMemory=pcall(computer.totalMemory)
  local mode=ui.startupDisplayMode(maxW,maxH,freeOk and freeMemory,totalOk and totalMemory)
  local resized,reason=core.setDisplay(mode)
  if not resized and mode~="balanced" then resized,reason=core.setDisplay("balanced") end
  if not resized then resized,reason=core.setDisplay("compact") end
  if not resized then error("could not configure display: "..tostring(reason)) end
  core.scanApps()
  local pid,launchReason=core.launch("files")
  if not pid then core.notification={text=tostring(launchReason),untilTime=computer.uptime()+8} end
  local lastDraw=0
  while core.running do
    scheduler()
    local now=computer.uptime()
    local dirty=core.dirty
    if not dirty then for _,win in pairs(core.windows) do if win.dirty then dirty=true break end end end
    if dirty or now-lastDraw>=0.25 then redraw() lastDraw=now end
    local ev={event.pull(0.05)}
    if ev[1] then
      if ev[1]=="touch" then handleTouch(table.unpack(ev))
      elseif ev[1]=="drag" then handleDrag(table.unpack(ev))
      elseif ev[1]=="drop" then core.dragging=nil
      elseif ev[1]=="screen_resized" and acceptedScreen(ev[2]) then useResolution(ev[3],ev[4],false)
      elseif ev[1]=="key_down" and ev[4]==16 and keyboard.isControlDown() then core.running=false
      elseif (ev[1]=="key_down" or ev[1]=="key_up" or ev[1]=="clipboard") and core.focused then send(core.focused,table.unpack(ev))
      else dispatch(table.unpack(ev)) end
    end
  end
end

return core
