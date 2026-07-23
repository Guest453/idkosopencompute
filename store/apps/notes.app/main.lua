return function(app)
  local win=app.window{title="notes",width=58,height=18}
  local path="/home/idkos-notes.txt"
  local text="click add line to append a timestamped note"
  if app.fs.exists(path) then local f=io.open(path,"r"); text=f:read("*a") or text; f:close() end
  while true do
    win:reset()
    local y=2
    for line in (text.."\n"):gmatch("(.-)\n") do win:text(2,y,line:sub(1,52)); y=y+1; if y>13 then break end end
    win:button("add",2,15,14,"add line")
    win:button("clear",18,15,14,"clear")
    local name,_,id=app.pull()
    if name=="idk_button" then
      if id=="add" then text=text.."\nnew note @ "..math.floor(app.computer.uptime())
      elseif id=="clear" then text="" end
      local f=io.open(path,"w"); f:write(text); f:close()
    end
  end
end
