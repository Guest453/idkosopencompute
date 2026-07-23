return function(app)
  local win=app.window{title="system info",width=66,height=21}
  while true do
    local width,height=app.screen()
    win:reset()
    win:text(2,2,string.format("uptime: %.1f seconds",app.computer.uptime()))
    win:text(2,3,string.format("memory: %d kb free / %d kb total",math.floor(app.computer.freeMemory()/1024),math.floor(app.computer.totalMemory()/1024)))
    win:text(2,4,string.format("desktop: %d x %d",width,height))
    local displays=app.displays()
    win:text(2,5,string.format("displays: 1 primary + %d mirrored (not accelerated)",#displays.mirrors))
    win:text(2,7,"components")
    local rows={}
    for address,kind in app.component.list() do rows[#rows+1]={address=address,kind=kind} end
    table.sort(rows,function(a,b) return a.kind==b.kind and a.address<b.address or a.kind<b.kind end)
    for i=1,math.min(#rows,10) do
      win:text(2,i+7,string.format("%-18s %s",rows[i].kind,rows[i].address:sub(1,36)))
    end
    app.pull(1)
  end
end
