return function(app)
  local unicode=require("unicode")
  local win=app.window{title="notes",width=58,height=18}
  local path="/home/idkos-notes.txt"
  local text,input="",""
  if app.fs.exists(path) then local file=io.open(path,"r"); if file then text=file:read("*a") or "" file:close() end end

  local function save()
    local temp=path..".tmp"
    local file,reason=io.open(temp,"w")
    if not file then app.notify(reason) return end
    local ok,writeError=file:write(text)
    file:close()
    if not ok then app.fs.remove(temp) app.notify(writeError) return end
    local backup=path..".old"
    if app.fs.exists(backup) then app.fs.remove(backup) end
    if app.fs.exists(path) then
      local saved,saveError=app.fs.rename(path,backup)
      if not saved then app.fs.remove(temp) app.notify(saveError) return end
    end
    local moved,moveError=app.fs.rename(temp,path)
    if not moved then
      if app.fs.exists(backup) then app.fs.rename(backup,path) end
      app.notify(moveError)
    elseif app.fs.exists(backup) then app.fs.remove(backup) end
  end

  while true do
    win:reset()
    local lines={}
    for line in (text.."\n"):gmatch("(.-)\n") do lines[#lines+1]=line end
    local first=math.max(1,#lines-9)
    local y=2
    for i=first,#lines do win:text(2,y,unicode.sub(lines[i],1,52)); y=y+1 end
    win:text(2,12,"new: "..unicode.sub(input,math.max(1,unicode.len(input)-45),unicode.len(input)))
    win:button("add",2,15,14,"save line")
    win:button("clear",18,15,14,"clear all")
    local name,_,a,b=app.pull()
    if name=="idk_button" then
      if a=="add" and input~="" then text=text..(text=="" and "" or "\n")..input input="" save()
      elseif a=="clear" then text="" input="" save() end
    elseif name=="key_down" then
      local char,code=a,b
      if code==14 then input=unicode.sub(input,1,math.max(0,unicode.len(input)-1))
      elseif code==28 and input~="" then text=text..(text=="" and "" or "\n")..input input="" save()
      elseif char and char>=32 then input=input..unicode.char(char) end
    elseif name=="clipboard" then input=input..tostring(a or ""):gsub("[\r\n]"," ") end
  end
end
