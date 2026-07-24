return function(app)
  local win=app.window{title="prism breakout",width=54,height=23,bg=0x101a31}
  local paddle,ball,bricks,score,lives,wave,state,last,lastBeep
  local palette={0xff6685,0xf2c94c,0x6bd6a0,0x55c8ff,0xb184f5}
  local function beep(frequency,duration)
    local now=app.computer.uptime()
    if now-(lastBeep or 0)>=.055 then pcall(app.computer.beep,frequency,duration or .025) lastBeep=now end
  end
  local function serve(width,height)
    paddle=math.floor(width/2)
    ball={x=paddle,y=height-3,vx=(math.random(2)==1 and -1 or 1)*(11+wave),vy=-(8+wave*.6)}
    last=app.computer.uptime()
  end
  local function build(width)
    bricks={} local cols=math.max(6,math.floor((width-4)/5))
    local brickW=math.max(3,math.floor((width-3)/cols))
    for row=1,4+math.min(wave,2) do for col=1,cols do
      bricks[#bricks+1]={x=2+(col-1)*brickW,y=2+row,w=brickW-1,alive=true,color=palette[(row+col+wave)%#palette+1]}
    end end
  end
  local function reset(full)
    local width,height=win:size() width,height=math.min(width,60),math.min(height,24)
    if full then score,lives,wave,state=0,3,1,"play" end
    build(width) serve(width,height)
  end
  local function remaining()
    local count=0 for _,brick in ipairs(bricks) do if brick.alive then count=count+1 end end return count
  end
  local function movePaddle(value,width) paddle=math.max(4,math.min(width-3,value)) end
  reset(true)
  while true do
    local width,height=win:size() width,height=math.min(width,60),math.min(height,24)
    local now=app.computer.uptime()
    if not app.focused() then app.pull(.18) last=app.computer.uptime()
    else
      local dt=math.min(.07,math.max(0,now-last)) last=now
      if state=="play" then
        local oldY=ball.y
        ball.x,ball.y=ball.x+ball.vx*dt,ball.y+ball.vy*dt
        if ball.x<1 then ball.x=1 ball.vx=math.abs(ball.vx) beep(390)
        elseif ball.x>width then ball.x=width ball.vx=-math.abs(ball.vx) beep(390) end
        if ball.y<2 then ball.y=2 ball.vy=math.abs(ball.vy) beep(450) end
        if ball.vy>0 and oldY<=height-2 and ball.y>=height-2 and math.abs(ball.x-paddle)<=4 then
          ball.y=height-2 ball.vy=-math.abs(ball.vy)*1.015 ball.vx=ball.vx+(ball.x-paddle)*1.5 beep(760)
        end
        for _,brick in ipairs(bricks) do
          if brick.alive and ball.x>=brick.x and ball.x<brick.x+brick.w and ball.y>=brick.y and ball.y<brick.y+1 then
            brick.alive=false score=score+10*wave ball.vy=(oldY<brick.y) and -math.abs(ball.vy) or math.abs(ball.vy) beep(880+wave*90) break
          end
        end
        if ball.y>height then
          lives=lives-1 beep(150,.1)
          if lives<1 then state="lost" else serve(width,height) end
        elseif remaining()==0 then
          if wave>=3 then state="won" beep(1350,.14)
          else wave=wave+1 build(width) serve(width,height) beep(1120,.09) end
        end
      end
      local backgrounds,glyphs,foregrounds={},{},{}
      for i=1,width*height do backgrounds[i]=0x101a31 end
      for _,brick in ipairs(bricks) do if brick.alive then for x=brick.x,math.min(width,brick.x+brick.w-1) do backgrounds[(brick.y-1)*width+x]=brick.color end end end
      for x=math.floor(paddle)-3,math.floor(paddle)+3 do if x>=1 and x<=width then backgrounds[(height-2)*width+x]=0x68d8ff end end
      local bx,by=math.floor(ball.x+.5),math.floor(ball.y+.5)
      if bx>=1 and bx<=width and by>=1 and by<=height then local i=(by-1)*width+bx backgrounds[i],glyphs[i],foregrounds[i]=0xffffff,"o",0x17284a end
      win:reset() win:canvas(1,1,width,height,{backgrounds=backgrounds,foregrounds=foregrounds,glyphs=glyphs})
      win:text(2,1,string.format("score %04d   wave %d/3   lives %d",score,wave,lives),0xffffff,0x17284a)
      win:text(2,height,"a/d or arrows | touch to steer",0xffffff,0x17284a)
      if state~="play" then win:text(math.max(2,math.floor(width/2)-11),math.floor(height/2),(state=="won" and "all waves clear!" or "out of lives").." press/tap",0xffffff,state=="won" and 0x31885f or 0x9b3e55) end
      local name,_,a,b=app.pull(state=="play" and .045 or .15)
      if name=="key_down" then
        if state~="play" then reset(true)
        elseif a==97 or b==203 then movePaddle(paddle-4,width)
        elseif a==100 or b==205 then movePaddle(paddle+4,width)
        end
      elseif name=="touch" then if state~="play" then reset(true) else movePaddle(a,width) end end
    end
  end
end
