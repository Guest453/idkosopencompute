return function(app)
  local unicode=require("unicode")
  local internet=app.component.isAvailable("internet") and require("internet") or nil
  local win=app.window{title="app store",width=70,height=22}
  local base="https://raw.githubusercontent.com/Guest453/idkosopencompute/main/"
  local maxSize,maxFiles,maxPackageSize=256*1024,16,4*1024*1024
  local catalog,categories={}, {"all"}
  local view,category,page,selected="browse","all",1,nil
  local status,busy,confirm="press refresh to load the catalog",false,nil

  local function short(value,limit)
    value=tostring(value or ""):gsub("[%c]"," "):gsub("%s+"," ")
    return unicode.sub(value,1,limit)
  end

  local function target(item) return "/home/Apps/"..item.id..".app" end
  local function installed(item)
    local found=app.apps()[item.id]
    return found and found.path==target(item) and found or nil
  end

  local function versionParts(value)
    if type(value)~="string" or #value>24 then return nil end
    local parts={}
    for part in value:gmatch("[^.]+") do if not part:match("^%d+$") then return nil end parts[#parts+1]=tonumber(part) end
    if #parts<1 or #parts>3 or table.concat(parts,".")~=value:gsub("^0+(%d)","%1"):gsub("%.0+(%d)",".%1") then return nil end
    return parts
  end

  local function compareVersions(a,b)
    local aa,bb=versionParts(a),versionParts(b)
    if not aa or not bb then return 0 end
    for i=1,math.max(#aa,#bb) do
      local av,bv=aa[i] or 0,bb[i] or 0
      if av<bv then return -1 elseif av>bv then return 1 end
    end
    return 0
  end

  local function itemState(item)
    local localApp=installed(item)
    if not localApp then return "available" end
    local comparison=compareVersions(localApp.version,item.version)
    if comparison<0 then return "update" elseif comparison>0 then return "newer installed" end
    return "installed"
  end

  local function filtered()
    local result={}
    for _,item in ipairs(catalog) do if category=="all" or item.category==category then result[#result+1]=item end end
    return result
  end

  local function draw()
    local width,height=win.width,win.height
    local right=math.max(14,width-12)
    win:reset()
    win:fill(1,1,width,2,0xe7eef5)
    win:text(2,1,"idk app store",0x1d2b3a,0xe7eef5)
    win:text(2,2,short(status,math.max(12,width-18)),busy and 0xb06b16 or 0x617487,0xe7eef5)
    win:button("refresh",right,1,10,busy and "working" or "refresh")
    if view=="detail" and selected then
      local item=selected
      win:button("back",2,4,10,"< browse")
      win:fill(2,6,math.max(1,width-4),math.max(4,height-11),0xf0f4f8)
      win:icon(4,6,item.icon,item.color)
      win:text(13,6,short(item.name,30),0x1d2b3a,0xf0f4f8)
      win:text(13,7,"version "..item.version.."  |  "..item.category.."  |  "..short(item.author,16),0x617487,0xf0f4f8)
      win:text(13,9,short(item.description,math.max(8,width-19)),0x1d2b3a,0xf0f4f8)
      win:text(13,10,short(item.details,math.max(8,width-19)),0x617487,0xf0f4f8)
      local state=itemState(item)
      local actionY=math.max(12,height-3)
      win:text(6,actionY-2,"status: "..state,0x397fca,0xf0f4f8)
      win:button("install",6,actionY,15,state=="update" and "update" or "install")
      if installed(item) then win:button("uninstall",23,actionY,15,confirm==item.id and "confirm remove" or "uninstall") end
      if confirm==item.id then win:text(6,actionY+1,short("click confirm again; data outside the package is kept",width-8),0xc14f5a) end
    else
      win:text(2,4,"browse")
      local x=10
      for _,name in ipairs(categories) do
        local buttonWidth=math.min(12,unicode.len(name)+2)
        if x+buttonWidth<width then win:button("category:"..name,x,4,buttonWidth,name==category and "["..name.."]" or name) x=x+buttonWidth+1 end
      end
      local items=filtered()
      local rows=math.max(1,math.min(4,math.floor((height-8)/3)))
      local pages=math.max(1,math.ceil(#items/rows)) page=math.max(1,math.min(page,pages))
      for row=1,rows do
        local index=(page-1)*rows+row
        local item=items[index]
        if item then
          local y=5+(row-1)*3
          win:fill(2,y,math.max(1,width-4),3,row%2==0 and 0xf0f4f8 or 0xf8fafc)
          win:icon(3,y,item.icon,item.color,"small")
          win:text(10,y,short(item.name,19))
          if width>=64 then win:text(31,y,short(item.category,12),0x617487) end
          win:text(width>=64 and 45 or 31,y,short(itemState(item),width>=64 and 12 or 14),0x397fca)
          win:text(10,y+1,short(item.description,math.max(8,width-23)),0x617487)
          win:button("detail:"..item.id,math.max(8,width-11),y,8,"details")
        end
      end
      local navY=height-2
      win:button("previous",2,navY,10,"previous")
      win:text(math.max(14,math.floor(width/2)-4),navY,string.format("page %d/%d",page,pages))
      win:button("next",right,navY,10,"next")
    end
  end

  local function pulse(message)
    status,busy=message,true
    draw()
    app.yield()
  end

  local function responseCode(handle)
    local mt=getmetatable(handle)
    local response=mt and mt.__index and mt.__index.response
    if type(response)=="function" then local ok,code=pcall(response); if ok then return code end end
  end

  local function fetch(url)
    if not internet then return nil,"internet card not installed" end
    local ok,handle,reason=pcall(internet.request,url)
    if not ok then return nil,short(handle,100) end
    if not handle then return nil,reason or "request failed" end
    local parts,size={},0
    local readOk,readError=pcall(function()
      for chunk in handle do
        if type(chunk)~="string" then error("invalid response chunk") end
        size=size+#chunk
        if size>maxSize then error("download exceeds 256 kib limit") end
        parts[#parts+1]=chunk
      end
    end)
    if not readOk then pcall(handle.close) return nil,short(readError,100) end
    local code=responseCode(handle)
    pcall(handle.close)
    if code and (code<200 or code>=300) then return nil,"http "..tostring(code) end
    local data=table.concat(parts)
    if #data==0 then return nil,"empty response" end
    return data
  end

  local function sanitize(raw)
    if type(raw)~="table" or type(raw.id)~="string" or not raw.id:match("^[%w_-]+$") or #raw.id>32 then return nil end
    if type(raw.name)~="string" or raw.name=="" or type(raw.path)~="string" or raw.path~="store/apps/"..raw.id..".app" then return nil end
    if not versionParts(raw.version) or type(raw.files)~="table" or #raw.files<2 or #raw.files>maxFiles then return nil end
    local files,seen,hasManifest,hasMain={},{}
    for _,file in ipairs(raw.files) do
      local extension=type(file)=="string" and file:match("%.([%w]+)$")
      if type(file)~="string" or #file>48 or not file:match("^[%w][%w_.-]*%.[%w]+$") or
        (extension~="lua" and extension~="wad" and extension~="txt") or seen[file] then return nil end
      seen[file]=true files[#files+1]=file
      hasManifest=hasManifest or file=="manifest.lua" hasMain=hasMain or file=="main.lua"
    end
    if not hasManifest or not hasMain or files[1]~="manifest.lua" then return nil end
    local color=tonumber(raw.color)
    if not color or color<0 or color>0xffffff or color%1~=0 then color=0x397fca end
    local category=short(raw.category or "utilities",14):lower()
    if category=="" or not category:match("^[%w _-]+$") then category="utilities" end
    local icon=type(raw.icon)=="string" and raw.icon:match("^[%w_-]+$") and short(raw.icon,24) or raw.id
    local package=raw.package
    if package~=nil and (type(package)~="string" or #package>64 or not package:match("^[%w_.-]+$")) then return nil end
    return {id=raw.id,name=short(raw.name,36),version=raw.version,path=raw.path,files=files,package=package,
      author=short(raw.author or "unknown",24),description=short(raw.description or "no description",100),
      details=short(raw.details or raw.description or "",140),category=category,icon=icon,color=color}
  end

  local function little32(data,position)
    local a,b,c,d=data:byte(position,position+3)
    if not d then return nil end
    return a+b*256+c*65536+d*16777216
  end

  local function validWad(data)
    local magic=data:sub(1,4)
    if magic~="PWAD" and magic~="IWAD" then return nil,"invalid wad magic" end
    local count,offset=little32(data,5),little32(data,9)
    if not count or count<1 or count>16384 or not offset or offset<12 or offset+count*16>#data then return nil,"invalid wad directory" end
    for index=0,count-1 do
      local position=offset+index*16+1
      local lumpOffset,lumpSize=little32(data,position),little32(data,position+4)
      if not lumpOffset or not lumpSize or lumpOffset>#data or lumpSize>#data-lumpOffset then return nil,"wad lump outside file" end
    end
    return true
  end

  local function exactFiles(manifest,item)
    if item.package==nil then return true end
    if manifest.package~=item.package or type(manifest.files)~="table" or #manifest.files~=#item.files then return false end
    for index,file in ipairs(item.files) do if manifest.files[index]~=file then return false end end
    return true
  end

  local function refresh()
    pulse("loading catalog...")
    local data,reason=fetch(base.."store/index.lua")
    if not data then status,busy="catalog: "..tostring(reason),false return end
    local fn,syntaxError=load(data,"=store-index","t",{})
    if not fn then status,busy="invalid catalog: "..short(syntaxError,90),false return end
    local ok,result=pcall(fn)
    if not ok or type(result)~="table" then status,busy="catalog did not return a table",false return end
    local checked,ids,categorySet,newCategories={},{}, {all=true},{"all"}
    for _,raw in ipairs(result) do
      local item=sanitize(raw)
      if item and not ids[item.id] then
        ids[item.id]=true checked[#checked+1]=item
        if not categorySet[item.category] then categorySet[item.category]=true newCategories[#newCategories+1]=item.category end
      end
    end
    table.sort(checked,function(a,b) return a.name<b.name end)
    table.sort(newCategories,function(a,b) if a==b then return false elseif a=="all" then return true elseif b=="all" then return false else return a<b end end)
    catalog,categories,category,page=checked,newCategories,"all",1
    status,busy=#catalog.." verified apps available",false
  end

  local function removeTree(path,root)
    local paths={}
    local function inspect(current,depth)
      if type(current)~="string" or current~=root and current:sub(1,#root+1)~=root.."/" then return nil,"unsafe removal path" end
      if depth>16 then return nil,"package tree is too deep" end
      if not app.fs.exists(current) then return true end
      paths[#paths+1]=current
      if #paths>1024 then return nil,"package tree is too large" end
      if app.fs.isDirectory(current) then
        local iterator,reason=app.fs.list(current)
        if not iterator then return nil,reason end
        local names,count={},0
        for name in iterator do
          name=tostring(name):gsub("/$","") count=count+1
          if count>256 or name=="" or name=="." or name==".." or name:find("/",1,true) then return nil,"unsafe package contents" end
          names[#names+1]=name
        end
        for _,name in ipairs(names) do local ok,err=inspect(app.fs.concat(current,name),depth+1); if not ok then return nil,err end end
      end
      return true
    end
    local safe,inspectError=inspect(path,0)
    if not safe then return nil,inspectError end
    for index=#paths,1,-1 do
      local current=paths[index]
      local ok,reason=app.fs.remove(current)
      if not ok and app.fs.exists(current) then return nil,reason or "remove failed" end
    end
    return true
  end

  local function install(item)
    local root,dir="/home/Apps",target(item)
    local stage,backup=root.."/."..item.id..".staging",root.."/."..item.id..".backup"
    local collision=app.apps()[item.id]
    if collision and collision.path~=dir then status,busy="a protected built-in uses this id",false return end
    pulse("preparing "..item.name.."...")
    local made,makeError=app.fs.makeDirectory(root)
    if not made and not app.fs.isDirectory(root) then status,busy=tostring(makeError),false return end
    if app.fs.exists(backup) then
      if app.fs.exists(dir) then
        local cleaned,cleanError=removeTree(backup,backup)
        if not cleaned then status,busy="backup cleanup: "..tostring(cleanError),false return end
      else
        local recovered,recoverError=app.fs.rename(backup,dir)
        if not recovered then status,busy="recovery: "..tostring(recoverError),false return end
      end
    end
    local cleaned,cleanError=removeTree(stage,stage)
    if not cleaned then status,busy="staging cleanup: "..tostring(cleanError),false return end
    made,makeError=app.fs.makeDirectory(stage)
    if not made then status,busy=tostring(makeError),false return end
    local totalSize=0
    for index,file in ipairs(item.files) do
      pulse(string.format("downloading %d/%d: %s",index,#item.files,file))
      local data,reason=fetch(base..item.path.."/"..file)
      if not data then removeTree(stage,stage) status,busy=tostring(reason),false return end
      totalSize=totalSize+#data
      if totalSize>maxPackageSize then removeTree(stage,stage) status,busy="package exceeds 4 mib limit",false return end
      local extension=file:match("%.([%w]+)$")
      local fn,syntaxError
      if extension=="lua" then
        fn,syntaxError=load(data,"="..file,"t",{})
        if not fn then removeTree(stage,stage) status,busy="invalid "..file..": "..short(syntaxError,70),false return end
      elseif extension=="wad" then
        local valid,wadError=validWad(data)
        if not valid then removeTree(stage,stage) status,busy=file..": "..wadError,false return end
      end
      if file=="manifest.lua" then
        local valid,result=pcall(fn)
        if not valid or type(result)~="table" or result.id~=item.id or result.version~=item.version or not exactFiles(result,item) then
          removeTree(stage,stage) status,busy="manifest package identity mismatch",false return
        end
      end
      local out,openError=io.open(app.fs.concat(stage,file),"w")
      if not out then removeTree(stage,stage) status,busy=tostring(openError),false return end
      local written,writeError=out:write(data) out:close()
      if not written then removeTree(stage,stage) status,busy=tostring(writeError),false return end
    end
    if app.fs.exists(dir) then
      local saved,saveError=app.fs.rename(dir,backup)
      if not saved then removeTree(stage,stage) status,busy=tostring(saveError),false return end
    end
    local activated,activateError=app.fs.rename(stage,dir)
    if not activated then
      if app.fs.exists(backup) then
        local restored,restoreError=app.fs.rename(backup,dir)
        if not restored then activateError=tostring(activateError).."; restore: "..tostring(restoreError) end
      end
      removeTree(stage,stage) status,busy=tostring(activateError),false return
    end
    app.rescanApps()
    local exact=app.apps()[item.id]
    if not exact or exact.path~=dir or exact.version~=item.version or not exactFiles(exact,item) then
      local removed,removeError=removeTree(dir,dir)
      local restored,restoreError=true,nil
      if removed and app.fs.exists(backup) then restored,restoreError=app.fs.rename(backup,dir) end
      app.rescanApps()
      if not removed then status,busy="activation failed; rollback cleanup: "..tostring(removeError),false
      elseif not restored then status,busy="activation failed; restore: "..tostring(restoreError),false
      else status,busy="activation verification failed; previous version restored",false end
      return
    end
    local backupRemoved,backupError=removeTree(backup,backup)
    status,busy=item.name.." "..item.version.." installed"..(backupRemoved and "" or "; backup cleanup: "..tostring(backupError)),false
  end

  local function uninstall(item)
    local dir=target(item)
    if not installed(item) then status,confirm="downloaded package is not installed",nil return end
    pulse("removing "..item.name.."...")
    local ok,reason=removeTree(dir,dir)
    app.rescanApps()
    if not ok then status,busy="uninstall: "..tostring(reason),false
    elseif app.apps()[item.id] and app.apps()[item.id].path==dir then status,busy="uninstall verification failed",false
    else status,busy=item.name.." uninstalled",false end
    confirm=nil
  end

  while true do
    draw()
    local name,_,id=app.pull()
    if name=="idk_button" and not busy then
      if id=="refresh" then refresh()
      elseif id=="back" then view,selected,confirm="browse",nil,nil
      elseif id=="previous" then page=math.max(1,page-1)
      elseif id=="next" then page=page+1
      elseif tostring(id):match("^category:") then category=id:sub(10) page=1
      elseif tostring(id):match("^detail:") then
        local wanted=id:sub(8) for _,item in ipairs(catalog) do if item.id==wanted then selected,view=item,"detail" break end end
      elseif id=="install" and selected then confirm=nil install(selected)
      elseif id=="uninstall" and selected then
        if confirm==selected.id then uninstall(selected) else confirm=selected.id status="confirm removal for "..selected.name end
      end
    end
  end
end
