return function(app)
  local win=app.window{title="neon pong",width=54,height=22,bg=0x101a33}
  local player,ai,ball,score,state,last
  local lastBeep=0
  local function beep(frequency,duration)
    local now=app.computer.uptime()
    if now-lastBeep>=.05 then pcall(app.computer.beep,frequency,duration or .03) lastBeep=now end
  end
  local function reset(full)
    local width,height=win:size()
    player,ai=math.floor(height/2),math.floor(height/2)
    ball={x=math.floor(width/2),y=math.floor(height/2),vx=(math.random(2)==1 and -1 or 1)*15,vy=(math.random()-.5)*10}
    if full then score={0,0} state="play" end last=app.computer.uptime()
  end
  reset(true)
  while true do
    local width,height=win:size() width,height=math.min(width,58),math.min(height,24)
    local now=app.computer.uptime() local dt=math.min(.12,now-last) last=now
    if not app.focused() then app.pull(.15) last=app.computer.uptime()
    else
      if state=="play" then
        ai=ai+(ball.y>ai and 1 or -1)*math.min(math.abs(ball.y-ai),dt*(7+score[1]))
        ball.x,ball.y=ball.x+ball.vx*dt,ball.y+ball.vy*dt
        if ball.y<2 then ball.y=2 ball.vy=math.abs(ball.vy) elseif ball.y>height-1 then ball.y=height-1 ball.vy=-math.abs(ball.vy) end
        if ball.vx<0 and ball.x<=3 and ball.x>=1.5 and math.abs(ball.y-player)<=2.2 then ball.x=3 ball.vx=math.abs(ball.vx)*1.035 ball.vy=ball.vy+(ball.y-player)*2 beep(720,.03) end
        if ball.vx>0 and ball.x>=width-2 and ball.x<=width and math.abs(ball.y-ai)<=2.2 then ball.x=width-2 ball.vx=-math.abs(ball.vx)*1.035 ball.vy=ball.vy+(ball.y-ai)*2 beep(520,.03) end
        if ball.x<1 then score[2]=score[2]+1 beep(180,.09) reset(false) elseif ball.x>width then score[1]=score[1]+1 beep(1100,.08) reset(false) end
        if score[1]>=7 or score[2]>=7 then state="done" beep(score[1]>score[2] and 1400 or 140,.14) end
      end
      local backgrounds,glyphs={},{}
      for y=1,height do for x=1,width do local i=(y-1)*width+x backgrounds[i]=x%2==0 and x==math.floor(width/2) and 0x244060 or 0x101a33 end end
      for y=math.floor(player)-2,math.floor(player)+2 do if y>=2 and y<height then backgrounds[(y-1)*width+2]=0x65c8ff end end
      for y=math.floor(ai)-2,math.floor(ai)+2 do if y>=2 and y<height then backgrounds[(y-1)*width+width-1]=0xff6fae end end
      local bx,by=math.floor(ball.x+.5),math.floor(ball.y+.5)
      if bx>=1 and bx<=width and by>=1 and by<=height then local i=(by-1)*width+bx backgrounds[i],glyphs[i]=0xffffff,"o" end
      win:reset() win:canvas(1,1,width,height,{backgrounds=backgrounds,glyphs=glyphs})
      win:text(2,1,string.format("you %d       neon pong       %d cpu",score[1],score[2]),0xffffff,0x172b4d)
      win:text(2,height,"w/s or arrows | touch height | first to 7",0xffffff,0x172b4d)
      if state=="done" then win:text(math.max(2,math.floor(width/2)-10),math.floor(height/2),(score[1]>score[2] and "you win!" or "cpu wins").." press/tap",0xffffff,0x8f3f73) end
      local name,_,a,b=app.pull(.1)
      if name=="key_down" then
        if a==119 or b==200 then player=math.max(4,player-2) elseif a==115 or b==208 then player=math.min(height-3,player+2)
        elseif state=="done" then reset(true) end
      elseif name=="touch" then if state=="done" then reset(true) else player=math.max(4,math.min(height-3,b)) end end
    end
  end
end
