return function(app)
  local win=app.window{title="pocket mines",width=42,height=18,bg=0x182536}
  local boardW,boardH,mineCount=12,10,18
  local cells,cursor,state,startedAt,elapsed,flags,lastBeep

  local function beep(frequency,duration)
    local now=app.computer.uptime()
    if now-(lastBeep or 0)>=.06 then pcall(app.computer.beep,frequency,duration or .035) lastBeep=now end
  end
  local function at(x,y) return cells[(y-1)*boardW+x] end
  local function reset()
    cells={}
    for i=1,boardW*boardH do cells[i]={mine=false,revealed=false,flagged=false,count=0} end
    cursor={x=1,y=1} state,startedAt,elapsed,flags="ready",nil,0,0
  end
  local function neighbors(x,y,callback)
    for ny=math.max(1,y-1),math.min(boardH,y+1) do
      for nx=math.max(1,x-1),math.min(boardW,x+1) do
        if nx~=x or ny~=y then callback(nx,ny,at(nx,ny)) end
      end
    end
  end
  local function plant(safeX,safeY)
    local choices={}
    for y=1,boardH do for x=1,boardW do
      if math.abs(x-safeX)>1 or math.abs(y-safeY)>1 then choices[#choices+1]={x=x,y=y} end
    end end
    for i=#choices,2,-1 do local j=math.random(i) choices[i],choices[j]=choices[j],choices[i] end
    for i=1,mineCount do at(choices[i].x,choices[i].y).mine=true end
    for y=1,boardH do for x=1,boardW do
      local count=0 neighbors(x,y,function(_,_,cell) if cell.mine then count=count+1 end end) at(x,y).count=count
    end end
    state,startedAt="play",app.computer.uptime()
  end
  local function finishIfClear()
    local hidden=0
    for _,cell in ipairs(cells) do if not cell.mine and not cell.revealed then hidden=hidden+1 end end
    if hidden==0 then
      state="won" elapsed=math.floor(elapsed)
      for _,cell in ipairs(cells) do if cell.mine then cell.flagged=true end end
      flags=mineCount beep(1250,.12)
    end
  end
  local function reveal(x,y)
    if state=="won" or state=="lost" then reset() return end
    local first=at(x,y)
    if first.flagged then return end
    if state=="ready" then plant(x,y) end
    if first.mine then
      first.revealed=true state="lost" elapsed=math.floor(elapsed)
      for _,cell in ipairs(cells) do if cell.mine then cell.revealed=true end end
      beep(145,.16) return
    end
    local queue={{x=x,y=y}} local head=1
    while head<=#queue do
      local item=queue[head] head=head+1
      local cell=at(item.x,item.y)
      if not cell.revealed and not cell.flagged and not cell.mine then
        cell.revealed=true
        if cell.count==0 then neighbors(item.x,item.y,function(nx,ny,nextCell)
          if not nextCell.revealed and not nextCell.flagged then queue[#queue+1]={x=nx,y=ny} end
        end) end
      end
    end
    beep(620,.025) finishIfClear()
  end
  local function toggleFlag(x,y)
    if state=="won" or state=="lost" then reset() return end
    local cell=at(x,y)
    if not cell.revealed then cell.flagged=not cell.flagged flags=flags+(cell.flagged and 1 or -1) beep(cell.flagged and 430 or 330,.025) end
  end
  local colors={0x55c8ff,0x72d69b,0xf2c94c,0xff8b61,0xc78cff,0x53d4d0,0xffffff,0xff6b77}
  local function draw()
    local width,height=win:size()
    local ox=math.max(2,math.floor((width-boardW*2)/2)+1) local oy=3
    local backgrounds,foregrounds,glyphs={},{},{}
    for y=1,boardH do for x=1,boardW do
      local cell=at(x,y) local base=(y-1)*boardW*2+(x-1)*2+1
      local bg=cell.revealed and 0x26384c or 0x52677e
      backgrounds[base],backgrounds[base+1]=bg,bg
      if cell.revealed and cell.mine then glyphs[base],foregrounds[base]="*",0xff6470
      elseif cell.flagged then glyphs[base],foregrounds[base]="!",0xf2c94c
      elseif cell.revealed and cell.count>0 then glyphs[base],foregrounds[base]=tostring(cell.count),colors[cell.count] end
      if cursor.x==x and cursor.y==y then backgrounds[base+1]=0x3b91c8 glyphs[base+1],foregrounds[base+1]="<",0xffffff end
    end end
    win:reset()
    win:fill(1,1,width,height,0x182536)
    local time=math.floor(elapsed)
    win:text(2,1,string.format("mines %02d   flags %02d   time %03d",mineCount,flags,time),0xeaf4ff,0x182536)
    win:canvas(ox,oy,boardW*2,boardH,{backgrounds=backgrounds,foregrounds=foregrounds,glyphs=glyphs})
    if state=="won" then win:text(ox,oy+boardH,"cleared! press or tap to play again",0x72d69b)
    elseif state=="lost" then win:text(ox,oy+boardH,"mine hit - press or tap to retry",0xff7b84)
    else win:text(2,height,"arrows move | space reveal | f flag | touch reveals",0xb9c8d8) end
  end
  reset()
  while true do
    local focused,now=app.focused(),app.computer.uptime()
    if state=="play" then
      if focused then elapsed=elapsed+math.max(0,now-startedAt) end
      startedAt=now
    end
    draw()
    local name,_,a,b=app.pull(focused and .12 or .2)
    if app.focused() then
      if name=="key_down" then
        if state=="won" or state=="lost" then reset()
        elseif a==97 or b==203 then cursor.x=math.max(1,cursor.x-1)
        elseif a==100 or b==205 then cursor.x=math.min(boardW,cursor.x+1)
        elseif a==119 or b==200 then cursor.y=math.max(1,cursor.y-1)
        elseif a==115 or b==208 then cursor.y=math.min(boardH,cursor.y+1)
        elseif a==102 then toggleFlag(cursor.x,cursor.y)
        elseif a==32 or b==28 then reveal(cursor.x,cursor.y) end
      elseif name=="touch" then
        local width=win:size() local ox=math.max(2,math.floor((width-boardW*2)/2)+1)
        local x,y=math.floor((a-ox)/2)+1,b-3+1
        if state=="won" or state=="lost" then reset()
        elseif x>=1 and x<=boardW and y>=1 and y<=boardH then cursor.x,cursor.y=x,y reveal(x,y) end
      end
    end
  end
end
