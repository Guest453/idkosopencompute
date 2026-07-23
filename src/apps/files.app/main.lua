return function(app)
  local win=app.window{title="files",width=64,height=21}
  local path="/home"
  local selected,offset,status

  local function parent()
    path=app.fs.path(path) or "/"
    if path=="" then path="/" end
    selected,offset,status=nil,0,nil
  end

  local function entries()
    local out={}
    if path~="/" then out[#out+1]=".." end
    local iterator,reason=app.fs.list(path)
    if not iterator then status=tostring(reason) return out end
    for name in iterator do out[#out+1]=name end
    table.sort(out,function(a,b)
      if a==".." then return true end
      if b==".." then return false end
      local ad=a:sub(-1)=="/" and 0 or 1
      local bd=b:sub(-1)=="/" and 0 or 1
      return ad==bd and a:lower()<b:lower() or ad<bd
    end)
    return out
  end

  local function preview(target,name)
    if app.fs.size(target)>8192 then status="file is too large to preview" return end
    local file,reason=io.open(target,"r")
    if not file then status=tostring(reason) return end
    local data=file:read(160) or ""
    file:close()
    data=data:gsub("[%c]"," ")
    status=name..": "..data
  end

  offset=0
  while true do
    win:reset()
    win:text(2,2,path)
    local list=entries()
    for row=1,12 do
      local index=offset+row
      local name=list[index]
      if name then win:button("select:"..index,2,row+3,46,(selected==index and "> " or "  ")..name) end
    end
    win:button("up",50,4,10,"up")
    win:button("open",50,6,10,"open")
    win:button("prev",50,8,10,"previous")
    win:button("next",50,10,10,"next")
    win:button("terminal",50,12,10,"terminal")
    win:button("tasks",50,14,10,"tasks")
    if status then win:text(2,17,status:sub(1,58)) end
    win:text(2,18,string.format("%d items  page %d",#list,math.floor(offset/12)+1))
    local eventName,_,id=app.pull()
    if eventName=="idk_button" then
      if id=="up" then parent()
      elseif id=="prev" then offset=math.max(0,offset-12) selected=nil
      elseif id=="next" then if offset+12<#list then offset=offset+12 selected=nil end
      elseif id=="terminal" then app.launch("terminal")
      elseif id=="tasks" then app.launch("taskmanager")
      elseif id=="open" and selected and list[selected] then
        local name=list[selected]
        if name==".." then parent()
        else
          local target=app.fs.concat(path,name)
          if app.fs.isDirectory(target) then path=target selected,offset,status=nil,0,nil
          elseif name:sub(-4)==".lua" then
            local ok,err=pcall(dofile,target)
            status=ok and ("ran "..name) or tostring(err)
          else preview(target,name) end
        end
      else
        local index=tonumber(id:match("^select:(%d+)$"))
        if index and list[index] then selected=index status=nil end
      end
    end
  end
end
