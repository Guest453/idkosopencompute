return function(app)
  local win=app.window{title="files",width=64,height=21}
  local path="/home"
  local selected
  local function entries()
    local out={}
    if path~="/" then out[#out+1]=".." end
    if app.fs.exists(path) then for name in app.fs.list(path) do out[#out+1]=name end end
    table.sort(out) return out
  end
  while true do
    win:reset()
    win:text(2,2,path)
    local list=entries()
    for i=1,math.min(#list,14) do
      local name=list[i]
      win:button("open:"..i,2,i+3,46,(selected==i and "> " or "  ")..name)
    end
    win:button("up",50,4,10,"up")
    win:button("terminal",50,6,10,"terminal")
    win:button("tasks",50,8,10,"tasks")
    local eventName,_,id=app.pull()
    if eventName=="idk_button" then
      if id=="up" then path=app.fs.path(path:sub(1,-2)) or "/"
      elseif id=="terminal" then app.launch("terminal")
      elseif id=="tasks" then app.launch("taskmanager")
      else
        local index=tonumber(id:match("^open:(%d+)$"))
        if index and list[index] then
          local name=list[index]
          if name==".." then path=app.fs.path(path:sub(1,-2)) or "/"
          else
            local target=app.fs.concat(path,name)
            if app.fs.isDirectory(target) then path=target selected=nil
            elseif name:sub(-4)==".lua" then
              local ok,err=pcall(dofile,target)
              app.notify(ok and ("ran "..name) or tostring(err))
            else selected=index end
          end
        end
      end
    end
  end
end
