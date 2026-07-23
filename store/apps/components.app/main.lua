return function(app)
  local unicode=require("unicode")
  local win=app.window{title="component browser",width=66,height=20}
  local entries,selected,page,status={},nil,1,""
  local function scan()
    entries={}
    local ok,reason=pcall(function()
      for address,kind in app.component.list() do entries[#entries+1]={address=address,kind=kind} end
    end)
    if not ok then status=tostring(reason) else status=#entries.." components" end
    table.sort(entries,function(a,b) return a.kind==b.kind and a.address<b.address or a.kind<b.kind end)
    page=1
  end
  scan()
  while true do
    local rows=math.max(1,math.min(10,win.height-8))
    win:reset()
    win:text(2,2,status,0x617487)
    win:button("refresh",math.max(14,win.width-12),2,10,"rescan")
    if selected then
      win:button("back",2,4,9,"< list")
      win:text(2,6,selected.kind)
      win:text(2,7,selected.address,0x617487)
      win:text(2,9,"exported methods")
      local methods={}
      local ok,result=pcall(app.component.methods,selected.address)
      if ok and type(result)=="table" then for name in pairs(result) do methods[#methods+1]=name end table.sort(methods) end
      for i=1,math.min(math.max(1,win.height-11),#methods) do win:text(4,9+i,unicode.sub(methods[i],1,56)) end
      if not ok then win:text(4,11,"unable to inspect this component",0xb84d58) elseif #methods==0 then win:text(4,11,"no methods reported",0x617487) end
    else
      local first=(page-1)*rows+1
      for row=1,rows do
        local index=first+row-1 local item=entries[index]
        if item then
          win:text(2,row+4,unicode.sub(item.kind,1,18))
          win:text(22,row+4,unicode.sub(item.address,1,27),0x617487)
          win:button("open:"..index,math.max(14,win.width-14),row+4,10,"inspect")
        end
      end
      local pages=math.max(1,math.ceil(#entries/rows))
      local navY=win.height-2
      win:button("previous",2,navY,10,"previous")
      win:text(28,navY,string.format("%d/%d",page,pages))
      win:button("next",math.max(14,win.width-12),navY,10,"next")
    end
    local name,_,id=app.pull()
    if name=="idk_button" then
      if id=="refresh" then scan() selected=nil
      elseif id=="back" then selected=nil
      elseif id=="previous" then page=math.max(1,page-1)
      elseif id=="next" then page=math.min(math.max(1,math.ceil(#entries/rows)),page+1)
      else local index=tonumber(tostring(id):match("^open:(%d+)$")); if index then selected=entries[index] end end
    end
  end
end
