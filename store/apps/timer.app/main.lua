return function(app)
  local win=app.window{title="clock & timer",width=46,height=15}
  local remaining,running,deadline=300,false,nil

  local function current()
    if running then return math.max(0,deadline-app.computer.uptime()) end
    return remaining
  end

  local function adjust(seconds)
    remaining=current()+seconds
    if running then deadline=app.computer.uptime()+remaining end
  end

  while true do
    local left=current()
    if running and left<=0 then
      running,remaining,deadline=false,0,nil
      app.notify("timer finished")
    end
    local whole=math.max(0,math.ceil(left))
    local hours=math.floor(whole/3600)
    local minutes=math.floor(whole/60)%60
    local seconds=whole%60
    local clockok,clock=pcall(os.date,"%H:%M:%S")
    win:reset()
    win:text(2,2,"local time")
    win:text(2,3,clockok and clock or string.format("uptime %.0f",app.computer.uptime()))
    win:text(2,6,"countdown")
    win:text(2,7,string.format("%02d:%02d:%02d",hours,minutes,seconds))
    win:button("toggle",2,10,10,running and "pause" or "start")
    win:button("minute",14,10,8,"+1 min")
    win:button("five",24,10,8,"+5 min")
    win:button("reset",34,10,8,"reset")
    local name,_,id=app.pull(0.2)
    if name=="idk_button" then
      if id=="toggle" then
        if running then remaining=current() running,deadline=false,nil
        elseif remaining>0 then running,deadline=true,app.computer.uptime()+remaining end
      elseif id=="minute" then adjust(60)
      elseif id=="five" then adjust(300)
      elseif id=="reset" then remaining,running,deadline=300,false,nil end
    end
  end
end
