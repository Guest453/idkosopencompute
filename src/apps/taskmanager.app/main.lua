return function(app)
  local win=app.window{title="task manager",width=62,height=20}
  local selected
  while true do
    win:reset()
    win:text(2,2,"pid   application          state       cpu time")
    local y=4
    local rows={}
    for pid,t in pairs(app.tasks()) do rows[#rows+1]={pid=pid,t=t} end
    table.sort(rows,function(a,b)return a.pid<b.pid end)
    for _,r in ipairs(rows) do
      win:text(2,y,string.format("%-5d %-20s %-11s %.3fs",r.pid,r.t.name,r.t.status,r.t.cpu))
      win:button("select:"..r.pid,50,y,8,selected==r.pid and "selected" or "select")
      y=y+1 if y>15 then break end
    end
    win:text(2,17,string.format("memory: %d / %d kb",math.floor((app.computer.totalMemory()-app.computer.freeMemory())/1024),math.floor(app.computer.totalMemory()/1024)))
    win:button("kill",2,18,18,"terminate selected")
    local name,_,id=app.pull(0.5)
    if name=="idk_button" then
      local pid=id:match("^select:(%d+)$")
      if pid then selected=tonumber(pid)
      elseif id=="kill" and selected then app.kill(selected) selected=nil end
    end
  end
end
