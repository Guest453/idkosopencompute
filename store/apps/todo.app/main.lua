return function(app)
  local unicode=require("unicode")
  local win=app.window{title="todo list",width=62,height=20}
  local path="/home/idkos-todo.txt"
  local items,input,status,page={},"",nil,1

  local function recover()
    local temp,backup=path..".tmp",path..".old"
    if app.fs.exists(backup) then
      if app.fs.exists(path) then app.fs.remove(backup)
      else
        local ok,reason=app.fs.rename(backup,path)
        if not ok then status="recovery: "..tostring(reason) return nil end
      end
    end
    if app.fs.exists(temp) then app.fs.remove(temp) end
    return true
  end

  local function loaditems()
    if not recover() then return end
    if not app.fs.exists(path) or (tonumber(app.fs.size(path)) or 0)>65536 then return end
    local file=io.open(path,"r")
    if not file then return end
    for line in file:lines() do
      local done,text=line:match("^([01])\t(.*)$")
      if done and text and #items<100 then items[#items+1]={done=done=="1",text=text} end
    end
    file:close()
  end

  local function saveitems()
    if not recover() then return nil end
    local temp,backup=path..".tmp",path..".old"
    local file,reason=io.open(temp,"w")
    if not file then status=tostring(reason) return nil end
    for _,item in ipairs(items) do
      local ok,writeerror=file:write(item.done and "1\t" or "0\t",item.text,"\n")
      if not ok then file:close() app.fs.remove(temp) status=tostring(writeerror) return nil end
    end
    file:close()
    if app.fs.exists(backup) then app.fs.remove(backup) end
    if app.fs.exists(path) then
      local saved,saveerror=app.fs.rename(path,backup)
      if not saved then app.fs.remove(temp) status=tostring(saveerror) return nil end
    end
    local moved,moveerror=app.fs.rename(temp,path)
    if not moved then
      if app.fs.exists(backup) then app.fs.rename(backup,path) end
      app.fs.remove(temp)
      status=tostring(moveerror)
      return nil
    end
    if app.fs.exists(backup) then app.fs.remove(backup) end
    status="saved"
    return true
  end

  loaditems()
  while true do
    win:reset()
    win:text(2,2,"task: "..unicode.sub(input,math.max(1,unicode.len(input)-47),unicode.len(input)))
    win:button("add",52,2,7,"add")
    local first=(page-1)*10+1
    for row=1,10 do
      local i=first+row-1
      local item=items[i]
      if item then
        win:button("toggle:"..i,2,row+3,5,item.done and "[x]" or "[ ]")
        win:text(8,row+3,unicode.sub(item.text,1,42),item.done and 0x7b8490 or nil)
        win:button("delete:"..i,52,row+3,7,"delete")
      end
    end
    local pages=math.max(1,math.ceil(#items/10))
    win:button("previous",2,15,10,"previous")
    win:button("next",14,15,10,"next")
    win:text(27,15,string.format("page %d/%d",page,pages))
    win:text(2,16,string.format("%d tasks%s",#items,status and " - "..status or ""))
    win:text(2,17,"type a task, then press enter or add")
    local name,_,a,b=app.pull()
    if name=="idk_button" then
      if a=="previous" then page=math.max(1,page-1)
      elseif a=="next" then page=math.min(pages,page+1)
      elseif a=="add" and input~="" and #items<100 then
        items[#items+1]={done=false,text=input} input="" saveitems()
        page=math.ceil(#items/10)
      else
        local index=tonumber(tostring(a):match("^toggle:(%d+)$"))
        if index and items[index] then items[index].done=not items[index].done saveitems()
        else
          index=tonumber(tostring(a):match("^delete:(%d+)$"))
          if index and items[index] then table.remove(items,index) page=math.min(page,math.max(1,math.ceil(#items/10))) saveitems() end
        end
      end
    elseif name=="key_down" then
      if b==14 then input=unicode.sub(input,1,math.max(0,unicode.len(input)-1))
      elseif b==28 and input~="" and #items<100 then items[#items+1]={done=false,text=input} input="" saveitems() page=math.ceil(#items/10)
      elseif a and a>=32 and unicode.len(input)<120 then input=input..unicode.char(a) end
    elseif name=="clipboard" then
      input=unicode.sub(input..tostring(a or ""):gsub("[\r\n\t]"," "),1,120)
    end
  end
end
