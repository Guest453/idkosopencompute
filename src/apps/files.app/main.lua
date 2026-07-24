return function(app)
  local keyboard=require("keyboard")
  local unicode=require("unicode")
  local win=app.window{title="finder",width=72,height=22}
  local path="/home"
  local history={path}
  local historyIndex=1
  local selected,offset,status,confirmDelete=nil,0,"ready",nil

  local favorites={
    {name="home",path="/home",icon="finder"},
    {name="applications",path="/home/Apps",icon="launchpad"},
    {name="system",path="/idkos",icon="settings"},
    {name="computer",path="/",icon="components"}
  }

  local function cleanName(name) return tostring(name or ""):gsub("/$","") end
  local function short(text,limit) return unicode.sub(tostring(text or ""),1,math.max(0,limit or 1)) end
  local function humanSize(bytes)
    bytes=tonumber(bytes) or 0
    if bytes>=1024*1024 then return string.format("%.1f mb",bytes/1024/1024) end
    if bytes>=1024 then return string.format("%.1f kb",bytes/1024) end
    return tostring(bytes).." b"
  end

  local function remember(nextPath)
    if type(nextPath)~="string" or not app.fs.exists(nextPath) or not app.fs.isDirectory(nextPath) then
      status="folder is unavailable" return false
    end
    path=nextPath
    for i=#history,historyIndex+1,-1 do history[i]=nil end
    if history[historyIndex]~=path then history[#history+1]=path historyIndex=#history end
    selected,offset,confirmDelete=nil,0,nil
    status="opened "..path
    return true
  end

  local function goHistory(delta)
    local nextIndex=historyIndex+delta
    if history[nextIndex] and app.fs.exists(history[nextIndex]) then
      historyIndex=nextIndex path=history[nextIndex]
      selected,offset,confirmDelete=nil,0,nil
      status=delta<0 and "back" or "forward"
    end
  end

  local function entries()
    local result={}
    local iterator,reason=app.fs.list(path)
    if not iterator then status=tostring(reason) return result end
    for raw in iterator do
      local name=cleanName(raw)
      if name~="" then
        local target=app.fs.concat(path,name)
        local dir=app.fs.isDirectory(target)
        result[#result+1]={name=name,target=target,dir=dir,size=dir and 0 or (app.fs.size(target) or 0)}
      end
    end
    table.sort(result,function(a,b)
      if a.dir~=b.dir then return a.dir end
      return a.name:lower()<b.name:lower()
    end)
    return result
  end

  local function selectedEntry(list)
    return selected and list[selected] or nil
  end

  local function preview(entry)
    if not entry then return {"nothing selected"} end
    if entry.dir then return {entry.name,"folder","double-click style: select, then open"} end
    local lines={entry.name,humanSize(entry.size)}
    if entry.size>8192 then lines[#lines+1]="preview disabled: file is large" return lines end
    local file,reason=io.open(entry.target,"r")
    if not file then lines[#lines+1]=tostring(reason) return lines end
    local data=file:read(300) or ""
    file:close()
    data=data:gsub("\r",""):gsub("[%c]"," "):gsub("%s+"," ")
    local position=1
    while position<=#data and #lines<8 do
      lines[#lines+1]=data:sub(position,position+21)
      position=position+22
    end
    return lines
  end

  local function openEntry(entry)
    if not entry then status="select an item first" return end
    confirmDelete=nil
    if entry.dir then remember(entry.target)
    else
      local lines=preview(entry)
      status=table.concat(lines,"  ")
    end
  end

  local function runEntry(entry)
    if not entry or entry.dir or entry.name:sub(-4)~=".lua" then status="select a lua file" return end
    local ok,reason=pcall(dofile,entry.target)
    status=ok and ("ran "..entry.name) or ("script error: "..tostring(reason))
  end

  local function newFolder()
    local base=app.fs.concat(path,"untitled folder")
    local target=base
    local number=2
    while app.fs.exists(target) and number<100 do target=base.." "..number number=number+1 end
    local ok,reason=app.fs.makeDirectory(target)
    status=ok and ("created "..cleanName(target:match("[^/]+$") or target)) or tostring(reason)
    selected,confirmDelete=nil,nil
  end

  local function deleteEntry(entry)
    if not entry then status="select an item first" return end
    if confirmDelete~=entry.target then confirmDelete=entry.target status="press delete again to confirm" return end
    local ok,reason=app.fs.remove(entry.target)
    status=ok and ("moved out of finder: "..entry.name) or ("delete failed: "..tostring(reason))
    selected,confirmDelete=nil,nil
  end

  local function draw()
    local width,height=win.width,win.height
    local sidebar=width>=50 and 15 or 0
    local previewWidth=width>=66 and 18 or 0
    local mainX=sidebar>0 and 17 or 2
    local mainRight=previewWidth>0 and width-previewWidth-2 or width-2
    local mainWidth=math.max(12,mainRight-mainX+1)
    local rows=math.max(4,height-7)
    local list=entries()
    if selected and not list[selected] then selected=nil end
    offset=math.max(0,math.min(offset,math.max(0,#list-rows)))

    win:reset()
    win:fill(1,1,width,2,0xe6eef5)
    win:button("back",2,1,7,"< back")
    win:button("forward",10,1,9,"forward >")
    win:button("up",20,1,6,"up")
    win:button("home",27,1,7,"home")
    win:button("refresh",35,1,9,"refresh")
    win:text(2,2,short(path,width-4),0x38536a,0xe6eef5)

    if sidebar>0 then
      win:fill(1,3,sidebar,height-5,0xd8e3ec)
      win:text(2,3,"favorites",0x617487,0xd8e3ec)
      for index,item in ipairs(favorites) do
        local y=4+(index-1)*3
        win:icon(2,y,item.icon,0x397fca,"small")
        win:button("favorite:"..index,6,y+1,sidebar-6,item.name)
      end
      win:text(2,height-3,"idk finder",0x617487,0xd8e3ec)
    end

    win:fill(mainX,3,mainWidth,height-5,0xf9fbfd)
    win:text(mainX+1,3,"name",0x617487,0xf9fbfd)
    if mainWidth>=28 then win:text(mainX+mainWidth-10,3,"size",0x617487,0xf9fbfd) end
    for row=1,rows do
      local index=offset+row
      local entry=list[index]
      if entry then
        local y=3+row
        local selectedNow=selected==index
        local bg=selectedNow and 0xbddcf5 or (row%2==0 and 0xf0f5f9 or 0xf9fbfd)
        win:fill(mainX,y,mainWidth,1,bg)
        win:text(mainX+1,y,entry.dir and "D" or "F",entry.dir and 0x397fca or 0x8ba3ba,bg)
        local label=(entry.dir and "[folder] " or "")..entry.name
        local labelWidth=mainWidth-(mainWidth>=28 and 11 or 3)
        win:button("select:"..index,mainX+3,y,math.max(5,labelWidth),short(label,labelWidth-2))
        if mainWidth>=28 then win:text(mainX+mainWidth-10,y,entry.dir and "--" or humanSize(entry.size),0x617487,bg) end
      end
    end

    if previewWidth>0 then
      local px=width-previewWidth
      win:fill(px,3,previewWidth,height-5,0xedf3f7)
      win:text(px+1,3,"preview",0x617487,0xedf3f7)
      local info=preview(selectedEntry(list))
      for index,line in ipairs(info) do
        if index+3<height-2 then win:text(px+1,index+3,short(line,previewWidth-2),index==1 and 0x1d2b3a or 0x617487,0xedf3f7) end
      end
    end

    local actionY=height-2
    win:button("open",2,actionY,8,"open")
    win:button("newfolder",11,actionY,11,"new folder")
    win:button("delete",23,actionY,9,confirmDelete and "confirm" or "delete")
    win:button("run",33,actionY,7,"run")
    win:button("prev",41,actionY,7,"page <")
    win:button("next",49,actionY,7,"page >")
    win:text(math.min(width-12,57),actionY,short(string.format("%d items",#list),12),0x617487)
    win:text(2,height-1,short(status or "ready",width-4),0x38536a)
    return list,rows
  end

  while true do
    local list,rows=draw()
    local name,address,id,code,player=app.pull()
    if name=="idk_button" then
      if id=="back" then goHistory(-1)
      elseif id=="forward" then goHistory(1)
      elseif id=="up" then remember(app.fs.path(path) or "/")
      elseif id=="home" then remember("/home")
      elseif id=="refresh" then status="refreshed" selected=nil confirmDelete=nil
      elseif id=="open" then openEntry(selectedEntry(list))
      elseif id=="run" then runEntry(selectedEntry(list))
      elseif id=="newfolder" then newFolder()
      elseif id=="delete" then deleteEntry(selectedEntry(list))
      elseif id=="prev" then offset=math.max(0,offset-rows) selected=nil
      elseif id=="next" then if offset+rows<#list then offset=offset+rows selected=nil end
      else
        local favorite=tonumber(tostring(id):match("^favorite:(%d+)$"))
        local index=tonumber(tostring(id):match("^select:(%d+)$"))
        if favorite and favorites[favorite] then remember(favorites[favorite].path)
        elseif index and list[index] then
          if selected==index then openEntry(list[index]) else selected=index status=list[index].name confirmDelete=nil end
        end
      end
    elseif name=="key_down" then
      if code==keyboard.keys.up then selected=math.max(1,(selected or 1)-1)
      elseif code==keyboard.keys.down then selected=math.min(#list,(selected or 0)+1)
      elseif code==keyboard.keys.enter then openEntry(selectedEntry(list))
      elseif code==keyboard.keys.back then goHistory(-1) end
    end
  end
end
