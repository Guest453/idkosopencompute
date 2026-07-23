return function(app)
  local internet=app.component.isAvailable("internet") and require("internet") or nil
  local win=app.window{title="app store",width=68,height=21}
  local base="https://raw.githubusercontent.com/Guest453/idkosopencompute/main/"
  local catalog,status={},"press refresh to load the github catalog"
  local maxSize=256*1024

  local function remove(path)
    if app.fs.exists(path) then app.fs.remove(path) end
  end

  local function responseCode(handle)
    local mt=getmetatable(handle)
    local response=mt and mt.__index and mt.__index.response
    if type(response)=="function" then
      local ok,code=pcall(response)
      if ok then return code end
    end
  end

  local function fetch(url)
    local ok,handle,reason=pcall(internet.request,url)
    if not ok then return nil,handle end
    if not handle then return nil,reason or "request failed" end
    local parts,size={},0
    local readOk,readError=pcall(function()
      for chunk in handle do
        size=size+#chunk
        if size>maxSize then error("download exceeds size limit") end
        parts[#parts+1]=chunk
      end
    end)
    if not readOk then pcall(handle.close) return nil,readError end
    local code=responseCode(handle)
    if code and (code<200 or code>=300) then return nil,"http "..tostring(code) end
    local data=table.concat(parts)
    if #data==0 then return nil,"empty response" end
    return data
  end

  local function validItem(item)
    if type(item)~="table" or type(item.id)~="string" or not item.id:match("^[%w_-]+$") then return false end
    if type(item.name)~="string" or type(item.path)~="string" or not item.path:match("^store/apps/[%w_.-]+%.app$") then return false end
    if type(item.files)~="table" or #item.files<1 or #item.files>16 then return false end
    local hasManifest,hasMain=false,false
    for _,file in ipairs(item.files) do
      if type(file)~="string" or not file:match("^[%w_.-]+%.lua$") then return false end
      if file=="manifest.lua" then hasManifest=true elseif file=="main.lua" then hasMain=true end
    end
    return hasManifest and hasMain
  end

  local function refresh()
    if not internet then status="internet card not installed" return end
    status="loading catalog..."
    local data,reason=fetch(base.."store/index.lua")
    if not data then status="catalog: "..tostring(reason) return end
    local fn,err=load(data,"=store-index","t",{})
    if not fn then status="invalid catalog: "..tostring(err) return end
    local ok,result=pcall(fn)
    if not ok or type(result)~="table" then status="invalid catalog: "..tostring(result) return end
    local checked={}
    for _,item in ipairs(result) do if validItem(item) then checked[#checked+1]=item end end
    catalog=checked
    status=#catalog.." apps available"
  end

  local function install(item)
    local root="/home/Apps"
    local dir=app.fs.concat(root,item.id..".app")
    local stage=app.fs.concat(root,"."..item.id..".staging")
    local backup=app.fs.concat(root,"."..item.id..".backup")
    local made,makeError=app.fs.makeDirectory(root)
    if not made and not app.fs.isDirectory(root) then status=tostring(makeError) return end
    if app.fs.exists(backup) then
      if app.fs.exists(dir) then remove(backup)
      else
        local recovered,recoverError=app.fs.rename(backup,dir)
        if not recovered then status=tostring(recoverError) return end
      end
    end
    remove(stage)
    made,makeError=app.fs.makeDirectory(stage)
    if not made then status=tostring(makeError) return end
    for _,file in ipairs(item.files) do
      status="downloading "..file
      local data,reason=fetch(base..item.path.."/"..file)
      if not data then remove(stage) status=tostring(reason) return end
      local fn,syntaxError=load(data,"="..file,"t",{})
      if not fn then remove(stage) status="invalid "..file..": "..tostring(syntaxError) return end
      local out,openError=io.open(app.fs.concat(stage,file),"w")
      if not out then remove(stage) status=tostring(openError) return end
      local written,writeError=out:write(data)
      out:close()
      if not written then remove(stage) status=tostring(writeError) return end
    end
    if app.fs.exists(dir) then
      local saved,saveError=app.fs.rename(dir,backup)
      if not saved then remove(stage) status=tostring(saveError) return end
    end
    local activated,activateError=app.fs.rename(stage,dir)
    if not activated then
      if app.fs.exists(backup) then app.fs.rename(backup,dir) end
      remove(stage)
      status=tostring(activateError)
      return
    end
    remove(backup)
    app.rescanApps()
    status=item.name.." installed and ready"
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
