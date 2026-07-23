return function(app)
  local win=app.window{title="disk usage",width=66,height=20}
  local volumes,page,status={},1,nil

  local function amount(bytes)
    bytes=tonumber(bytes) or 0
    if bytes>=1024*1024 then return string.format("%.1f mb",bytes/(1024*1024)) end
    return string.format("%.1f kb",bytes/1024)
  end

  local function refresh()
    volumes,status={},nil
    local ok,reason=pcall(function()
      for proxy,path in app.fs.mounts() do
        local totalok,total=pcall(proxy.spaceTotal)
        local usedok,used=pcall(proxy.spaceUsed)
        local readonlyok,readonly=pcall(proxy.isReadOnly)
        volumes[#volumes+1]={
          path=path or "?",address=tostring(proxy.address or "unknown"),
          total=totalok and total or 0,used=usedok and used or 0,
          readonly=readonlyok and readonly or false
        }
      end
    end)
    if not ok then status=tostring(reason) end
    table.sort(volumes,function(a,b) return a.path<b.path end)
    page=math.min(page,math.max(1,math.ceil(#volumes/5)))
  end

  refresh()
  while true do
    win:reset()
    win:text(2,2,"mounted filesystems")
    for row=1,5 do
      local item=volumes[(page-1)*5+row]
      if item then
        local y=3+(row-1)*3
        win:text(2,y,string.format("%-20s %s",item.path,item.readonly and "read only" or "writable"))
        win:text(4,y+1,string.format("%s used / %s total  %s",amount(item.used),amount(item.total),item.address:sub(1,16)))
      end
    end
    win:button("previous",2,17,10,"previous")
    win:button("refresh",14,17,10,"refresh")
    win:button("next",26,17,10,"next")
    win:text(40,17,string.format("page %d/%d",page,math.max(1,math.ceil(#volumes/5))))
    if status then win:text(2,18,status) end
    local name,_,id=app.pull(5)
    if name=="idk_button" then
      if id=="previous" then page=math.max(1,page-1)
      elseif id=="next" then page=math.min(math.max(1,math.ceil(#volumes/5)),page+1)
      elseif id=="refresh" then refresh() end
    elseif not name then refresh() end
  end
end
