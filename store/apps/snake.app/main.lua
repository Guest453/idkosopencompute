return function(app)
  local win=app.window{title="garden snake",width=48,height=22,bg=0x142d28}
  local snake,direction,nextDirection,food,score,state,lastStep
  local function beep(frequency,duration) pcall(app.computer.beep,frequency,duration or .04) end
  local function placeFood(width,height)
    repeat food={x=2+math.random(math.max(1,width-3)),y=3+math.random(math.max(1,height-5))}
    until (function() for _,part in ipairs(snake) do if part.x==food.x and part.y==food.y then return false end end return true end)()
  end
  local function reset()
    local width,height=win:size()
    snake={{x=math.floor(width/2),y=math.floor(height/2)},{x=math.floor(width/2)-1,y=math.floor(height/2)}}
    direction,nextDirection={x=1,y=0},{x=1,y=0} score,state,lastStep=0,"play",app.computer.uptime()
    placeFood(width,height)
  end
  local function steer(x,y)
    if state~="play" then reset() elseif not (x==-direction.x and y==-direction.y) then nextDirection={x=x,y=y} end
  end
  reset()
  while true do
    local width,height=win:size()
    width,height=math.min(width,52),math.min(height,24)
    local now=app.computer.uptime()
    if not app.focused() then app.pull(.15) lastStep=now
    else
      if state=="play" and now-lastStep>=math.max(.07,.16-score*.004) then
        lastStep=now direction=nextDirection
        local head={x=snake[1].x+direction.x,y=snake[1].y+direction.y}
        if head.x<1 or head.x>width or head.y<2 or head.y>=height then state="lost" beep(160,.12)
        else
          for _,part in ipairs(snake) do if part.x==head.x and part.y==head.y then state="lost" beep(160,.12) break end end
          if state=="play" then
            table.insert(snake,1,head)
            if head.x==food.x and head.y==food.y then score=score+1 beep(850+math.min(score,10)*35,.04) placeFood(width,height) else table.remove(snake) end
          end
        end
      end
      local backgrounds,glyphs={},{}
      for i=1,width*height do backgrounds[i]=0x173f35 end
      for i,part in ipairs(snake) do local n=(part.y-1)*width+part.x backgrounds[n]=i==1 and 0x8ff0ad or 0x55d98b end
      local fi=(food.y-1)*width+food.x backgrounds[fi],glyphs[fi]=0xf4cf55,"*"
      win:reset() win:canvas(1,1,width,height,{backgrounds=backgrounds,glyphs=glyphs})
      win:text(2,1,"garden snake   score "..score,0xffffff,0x102c25)
      win:text(2,height,"arrows/wasd | touch around the snake",0xffffff,0x102c25)
      if state=="lost" then win:text(math.max(2,math.floor(width/2)-8),math.floor(height/2),"game over - press/tap",0xffffff,0x9c3f4e) end
      local name,_,a,b=app.pull(.1)
      if name=="key_down" then
        if a==119 or b==200 then steer(0,-1) elseif a==115 or b==208 then steer(0,1)
        elseif a==97 or b==203 then steer(-1,0) elseif a==100 or b==205 then steer(1,0)
        elseif state~="play" then reset() end
      elseif name=="touch" then
        if state~="play" then reset() else
          local dx,dy=a-snake[1].x,b-snake[1].y
          if math.abs(dx)>math.abs(dy) then steer(dx<0 and -1 or 1,0) else steer(0,dy<0 and -1 or 1) end
        end
      end
    end
  end
end
