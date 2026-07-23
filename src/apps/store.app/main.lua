return function(app)
  local internet=app.component.isAvailable("internet") and app.component.internet or nil
  local win=app.window{title="app store",width=68,height=21}
  local base="https://raw.githubusercontent.com/Guest453/idkosopencompute/main/"
  local catalog,status={},"press refresh to load the github catalog"
  local function fetch(url)
    local handle,reason=internet.request(url)
    if not handle then return nil,reason end
    local parts={}
    for chunk in handle do parts[#parts+1]=chunk end
    return table.concat(parts)
  end
  local function refresh()
    if not internet then status="internet card not installed" return end
    status="loading catalog..."
    local data,reason=fetch(base.."store/index.lua")
    if not data then status=tostring(reason) return end
    local fn,err=load(data,"=store-index","t",{})
    if not fn then status=tostring(err) return end
    local ok,result=pcall(fn)
    if ok and type(result)=="table" then catalog=result status=#catalog.." apps available" else status=tostring(result) end
  end
  local function install(item)
    local dir="/home/Apps/"..item.id..".app"
    app.fs.makeDirectory(dir)
    for _,file in ipairs(item.files) do
      status="downloading "..file
      local data,reason=fetch(base..item.path.."/"..file)
      if not data then status=tostring(reason) return end
      local f=assert(io.open(app.fs.concat(dir,file),"w")) f:write(data) f:close()
    end
    status=item.name.." installed. restart idk os to scan it."
  end
  while true do
    win:reset()
    win:text(2,2,"github: Guest453/idkosopencompute")
    win:text(2,3,status)
    win:button("refresh",54,2,10,"refresh")
    for i,item in ipairs(catalog) do
      if i<=12 then
        win:text(2,i+5,string.format("%-18s %-8s %s",item.name,item.version or "?",item.description or ""))
        win:button("install:"..i,55,i+5,10,"install")
      end
    end
    local name,_,id=app.pull()
    if name=="idk_button" then
      if id=="refresh" then refresh()
      else local i=tonumber(id:match("^install:(%d+)$")); if i and catalog[i] then install(catalog[i]) end end
    end
  end
end
