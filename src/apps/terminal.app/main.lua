return function(app)
  local shell=require("shell")
  local win=app.window{title="terminal",width=72,height=20,bg=0x101010}
  local lines={"idk os terminal","use the openos terminal for interactive commands.","buttons below run safe quick commands."}
  while true do
    win:reset()
    for i=1,math.min(#lines,13) do win:text(2,i+1,lines[math.max(1,#lines-12)+i-1],0xdddddd,0x101010) end
    win:button("ls",2,16,10,"list home")
    win:button("mem",14,16,10,"memory")
    win:button("reboot",26,16,10,"reboot")
    local name,_,id=app.pull()
    if name=="idk_button" then
      if id=="ls" then
        local names={} for n in app.fs.list("/home") do names[#names+1]=n:gsub("/$","") end
        lines[#lines+1]="$ ls /home" lines[#lines+1]=table.concat(names,"  ")
      elseif id=="mem" then lines[#lines+1]=string.format("free memory: %d kb",app.computer.freeMemory()/1024)
      elseif id=="reboot" then app.computer.shutdown(true) end
    end
  end
end
