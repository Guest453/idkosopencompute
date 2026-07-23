return function(app)
  local win=app.window{title="inferno: bfs1h map01 demo",width=78,height=25,bg=0x08090c}
  local clock=app.computer.uptime
  local pi=math.pi
  local function atan2(y,x)
    if math.atan2 then return math.atan2(y,x) end
    if x>0 then return math.atan(y/x) end
    if x<0 then return math.atan(y/x)+(y>=0 and pi or -pi) end
    if y>0 then return pi/2 elseif y<0 then return -pi/2 end
    return 0
  end

  local function fail(message) error(message,0) end
  local function u16(data,position)
    local a,b=data:byte(position,position+1)
    if not b then fail("truncated 16-bit field") end
    return a+b*256
  end
  local function s16(data,position)
    local value=u16(data,position)
    return value>=32768 and value-65536 or value
  end
  local function u32(data,position)
    local a,b,c,d=data:byte(position,position+3)
    if not d then fail("truncated 32-bit field") end
    return a+b*256+c*65536+d*16777216
  end
  local function lumpName(data,position)
    return data:sub(position,position+7):match("^[^%z]*") or ""
  end
  local function checkedCount(lump,recordSize,limit,name)
    if lump.size==0 or lump.size%recordSize~=0 then fail(name.." has an invalid record size") end
    local count=lump.size/recordSize
    if count>limit then fail(name.." exceeds the safe record limit") end
    return count
  end

  local function parseWad(path)
    local file,reason=io.open(path,"r")
    if not file then fail("cannot open BFS1H.wad: "..tostring(reason)) end
    local data,readReason=file:read("*a")
    file:close()
    if not data then fail("cannot read BFS1H.wad: "..tostring(readReason)) end
    if #data~=32635 then fail("BFS1H.wad size does not match the licensed package") end
    if data:sub(1,4)~="PWAD" then fail("BFS1H.wad is not a PWAD") end
    local directoryCount,directoryOffset=u32(data,5),u32(data,9)
    if directoryCount<1 or directoryCount>16384 or directoryOffset<12 or directoryOffset+directoryCount*16>#data then
      fail("BFS1H.wad has an invalid directory")
    end
    local directory={}
    for index=0,directoryCount-1 do
      local position=directoryOffset+index*16+1
      local offset,size=u32(data,position),u32(data,position+4)
      if offset>#data or size>#data-offset then fail("BFS1H.wad contains an out-of-bounds lump") end
      directory[#directory+1]={offset=offset,size=size,name=lumpName(data,position+8)}
    end
    local marker
    for index,lump in ipairs(directory) do if lump.name=="MAP01" then marker=index break end end
    if not marker then fail("MAP01 is missing from BFS1H.wad") end
    local wanted={}
    for index=marker+1,#directory do
      local lump=directory[index]
      if lump.name:match("^MAP%d%d$") or lump.name:match("^E%dM%d$") then break end
      if lump.name=="THINGS" or lump.name=="LINEDEFS" or lump.name=="VERTEXES" then
        if wanted[lump.name] then fail("MAP01 contains a duplicate "..lump.name.." lump") end
        wanted[lump.name]=lump
      end
    end
    if not wanted.THINGS or not wanted.LINEDEFS or not wanted.VERTEXES then fail("MAP01 geometry lumps are incomplete") end
    local vertexCount=checkedCount(wanted.VERTEXES,4,8192,"VERTEXES")
    local lineCount=checkedCount(wanted.LINEDEFS,14,8192,"LINEDEFS")
    local thingCount=checkedCount(wanted.THINGS,10,4096,"THINGS")
    local vertices={}
    local minX,maxX,minY,maxY
    for index=0,vertexCount-1 do
      local position=wanted.VERTEXES.offset+index*4+1
      local x,y=s16(data,position),s16(data,position+2)
      vertices[index]={x=x,y=y}
      minX=not minX and x or math.min(minX,x) maxX=not maxX and x or math.max(maxX,x)
      minY=not minY and y or math.min(minY,y) maxY=not maxY and y or math.max(maxY,y)
    end
    if maxX<=minX or maxY<=minY then fail("MAP01 has degenerate geometry") end
    local lines={}
    for index=0,lineCount-1 do
      local position=wanted.LINEDEFS.offset+index*14+1
      local first,second,flags,back=u16(data,position),u16(data,position+2),u16(data,position+4),u16(data,position+12)
      if first>=vertexCount or second>=vertexCount then fail("LINEDEFS references an invalid vertex") end
      if back==65535 or flags%2==1 then lines[#lines+1]={a=vertices[first],b=vertices[second],kind=index%4+1} end
    end
    if #lines<1 then fail("MAP01 contains no solid linedefs") end
    local things={}
    for index=0,thingCount-1 do
      local position=wanted.THINGS.offset+index*10+1
      things[#things+1]={x=s16(data,position),y=s16(data,position+2),angle=u16(data,position+4),type=u16(data,position+6)}
    end

    local maximum=48
    local scale=math.min((maximum-5)/(maxX-minX),(maximum-5)/(maxY-minY))
    if scale<=0 then fail("MAP01 cannot be scaled safely") end
    local width=math.max(7,math.min(maximum,math.ceil((maxX-minX)*scale)+5))
    local height=math.max(7,math.min(maximum,math.ceil((maxY-minY)*scale)+5))
    local grid={}
    for y=0,height-1 do
      grid[y+1]={}
      for x=0,width-1 do grid[y+1][x+1]=(x==0 or y==0 or x==width-1 or y==height-1) and 1 or 0 end
    end
    local function mapPoint(x,y) return (x-minX)*scale+2,(y-minY)*scale+2 end
    local sampleBudget=0
    for _,line in ipairs(lines) do
      local ax,ay=mapPoint(line.a.x,line.a.y)
      local bx,by=mapPoint(line.b.x,line.b.y)
      local steps=math.max(1,math.ceil(math.max(math.abs(bx-ax),math.abs(by-ay))*5))
      sampleBudget=sampleBudget+steps+1
      if sampleBudget>250000 then fail("MAP01 rasterization exceeds the safe work limit") end
      for step=0,steps do
        local amount=step/steps
        local x,y=math.floor(ax+(bx-ax)*amount),math.floor(ay+(by-ay)*amount)
        if x>=0 and x<width and y>=0 and y<height then grid[y+1][x+1]=line.kind end
      end
    end
    local function open(x,y) return x>=1 and y>=1 and x<width-1 and y<height-1 and grid[y+1][x+1]==0 end
    local function nearestOpen(x,y)
      local cx,cy=math.floor(x),math.floor(y)
      for radius=0,5 do
        for yy=cy-radius,cy+radius do
          for xx=cx-radius,cx+radius do
            if (radius==0 or xx==cx-radius or xx==cx+radius or yy==cy-radius or yy==cy+radius) and open(xx,yy) then return xx,yy end
          end
        end
      end
    end
    local startThing
    for _,thing in ipairs(things) do
      if thing.type>=1 and thing.type<=4 then startThing=thing if thing.type==1 then break end end
    end
    if not startThing then fail("MAP01 has no player start") end
    local startX,startY=mapPoint(startThing.x,startThing.y)
    local startCellX,startCellY=nearestOpen(startX,startY)
    if not startCellX then fail("MAP01 player start is blocked after rasterization") end
    local reachable,queueX,queueY,queueDistance={},{},{},{}
    local function key(x,y) return x..":"..y end
    local first,last=1,1
    queueX[1],queueY[1],queueDistance[1]=startCellX,startCellY,0
    reachable[key(startCellX,startCellY)]=true
    local farX,farY,farDistance=startCellX,startCellY,0
    while first<=last do
      local x,y,distance=queueX[first],queueY[first],queueDistance[first] first=first+1
      if distance>farDistance then farX,farY,farDistance=x,y,distance end
      local neighbors={{x+1,y},{x-1,y},{x,y+1},{x,y-1}}
      for _,neighbor in ipairs(neighbors) do
        local nx,ny=neighbor[1],neighbor[2]
        if open(nx,ny) and not reachable[key(nx,ny)] then
          last=last+1 queueX[last],queueY[last],queueDistance[last]=nx,ny,distance+1 reachable[key(nx,ny)]=true
        end
      end
    end
    if farDistance<3 then fail("MAP01 has no usable reachable area") end
    local monsterTypes={[9]=true,[58]=true,[65]=true,[66]=true,[67]=true,[68]=true,[69]=true,[71]=true,[3001]=true,[3002]=true,[3003]=true,[3004]=true,[3005]=true,[3006]=true}
    local ammoTypes={[17]=true,[2007]=true,[2008]=true,[2010]=true,[2046]=true,[2047]=true,[2048]=true,[2049]=true}
    local healthTypes={[2011]=true,[2012]=true,[2014]=true,[2015]=true}
    local enemies,pickups,occupied={},{},{}
    for _,thing in ipairs(things) do
      local x,y=mapPoint(thing.x,thing.y)
      local cellX,cellY=nearestOpen(x,y)
      local cellKey=cellX and key(cellX,cellY)
      if cellKey and reachable[cellKey] and not occupied[cellKey] then
        if monsterTypes[thing.type] and #enemies<8 and not (cellX==startCellX and cellY==startCellY) then
          enemies[#enemies+1]={x=cellX+.5,y=cellY+.5,hp=2,attack=0} occupied[cellKey]=true
        elseif (ammoTypes[thing.type] or healthTypes[thing.type]) and #pickups<12 then
          pickups[#pickups+1]={x=cellX+.5,y=cellY+.5,kind=ammoTypes[thing.type] and "A" or "H",active=true} occupied[cellKey]=true
        end
      end
    end
    return {grid=grid,width=width,height=height,player={x=startCellX+.5,y=startCellY+.5,a=(startThing.angle%360)*pi/180},
      enemies=enemies,pickups=pickups,exit={x=farX+.5,y=farY+.5},reachable=last,lines=#lines,things=thingCount}
  end

  local manifest=app.apps().inferno
  local packagePath=manifest and manifest.path
  local ok,levelOrError=pcall(function()
    if type(packagePath)~="string" then fail("installed package path is unavailable") end
    return parseWad(app.fs.concat(packagePath,"BFS1H.wad"))
  end)
  if not ok then
    local message=tostring(levelOrError):gsub("[%c]"," ")
    while true do
      win:reset()
      win:text(2,2,"bfs1h transformed map01 demo could not start",0xf06a63,0x08090c)
      win:text(2,4,message:sub(1,math.max(1,win.width-4)),0xf2d2cf,0x08090c)
      win:text(2,6,"verify and reinstall the licensed inferno package",0x9ba4b3,0x08090c)
      app.pull()
    end
  end

  local level=levelOrError
  local wallColors={0x8d392d,0xb77b35,0x47758f,0x68518d}
  local keys,pulses,zbuffer={},{},{}
  local player,enemies,pickups,exit,state,status,flash,deadline
  local function tile(x,y)
    local row=level.grid[math.floor(y)+1]
    return row and row[math.floor(x)+1] or 1
  end
  local function blocked(x,y,r)
    r=r or .18
    return tile(x-r,y-r)~=0 or tile(x+r,y-r)~=0 or tile(x-r,y+r)~=0 or tile(x+r,y+r)~=0
  end
  local function reset()
    player={x=level.player.x,y=level.player.y,a=level.player.a,health=100,ammo=18}
    enemies,pickups={},{}
    for _,enemy in ipairs(level.enemies) do enemies[#enemies+1]={x=enemy.x,y=enemy.y,hp=enemy.hp,attack=0} end
    for _,pickup in ipairs(level.pickups) do pickups[#pickups+1]={x=pickup.x,y=pickup.y,kind=pickup.kind,active=true} end
    exit={x=level.exit.x,y=level.exit.y}
    state,status,flash,deadline="playing","reach the transformed map exit",0,clock()+120
    keys,pulses={},{}
  end
  local function lineClear(ax,ay,bx,by)
    local dx,dy=bx-ax,by-ay
    local distance=math.sqrt(dx*dx+dy*dy)
    local steps=math.min(128,math.ceil(distance/.12))
    for index=1,steps-1 do local amount=index/steps if tile(ax+dx*amount,ay+dy*amount)~=0 then return false end end
    return true
  end
  local function living()
    local count=0
    for _,enemy in ipairs(enemies) do if enemy.hp>0 then count=count+1 end end
    return count
  end
  local function expire(now)
    if state=="playing" and now>=deadline then state,status,keys="timeout","two-minute demo complete",{} return true end
    return false
  end
  local function shoot(now)
    if state~="playing" or expire(now) then return end
    if player.ammo<1 then status="empty - find ammo" return end
    player.ammo=player.ammo-1 flash=now+.10
    local best,bestDistance
    for _,enemy in ipairs(enemies) do
      if enemy.hp>0 then
        local dx,dy=enemy.x-player.x,enemy.y-player.y
        local distance=math.sqrt(dx*dx+dy*dy)
        local difference=(atan2(dy,dx)-player.a+pi)%(2*pi)-pi
        if math.abs(difference)<math.min(.20,.07+.22/distance) and lineClear(player.x,player.y,enemy.x,enemy.y) and (not bestDistance or distance<bestDistance) then best,bestDistance=enemy,distance end
      end
    end
    if best then best.hp=best.hp-1 status=best.hp<=0 and "sentinel down" or "hit" else status="miss" end
  end
  local function shade(color,factor)
    factor=math.max(.18,math.min(1,factor))
    local r,g,b=math.floor(color/0x10000),math.floor(color/0x100)%0x100,color%0x100
    return math.floor(r*factor)*0x10000+math.floor(g*factor)*0x100+math.floor(b*factor)
  end
  local function cast(px,py,rayX,rayY)
    local mapX,mapY=math.floor(px),math.floor(py)
    local deltaX=math.abs(rayX)<1e-8 and 1e8 or math.abs(1/rayX)
    local deltaY=math.abs(rayY)<1e-8 and 1e8 or math.abs(1/rayY)
    local stepX,stepY,sideX,sideY
    if rayX<0 then stepX=-1 sideX=(px-mapX)*deltaX else stepX=1 sideX=(mapX+1-px)*deltaX end
    if rayY<0 then stepY=-1 sideY=(py-mapY)*deltaY else stepY=1 sideY=(mapY+1-py)*deltaY end
    local side,kind=0,1
    for _=1,64 do
      if sideX<sideY then sideX=sideX+deltaX mapX=mapX+stepX side=0 else sideY=sideY+deltaY mapY=mapY+stepY side=1 end
      kind=tile(mapX+.5,mapY+.5)
      if kind~=0 then break end
    end
    local distance
    if side==0 then distance=(mapX-px+(1-stepX)/2)/(math.abs(rayX)<1e-8 and 1e-8 or rayX)
    else distance=(mapY-py+(1-stepY)/2)/(math.abs(rayY)<1e-8 and 1e-8 or rayY) end
    return math.max(.04,math.abs(distance)),kind,side
  end
  local function renderSprite(object,kind,dirX,dirY,planeX,planeY,viewY,viewH,width)
    local relX,relY=object.x-player.x,object.y-player.y
    local determinant=planeX*dirY-dirX*planeY
    if math.abs(determinant)<1e-8 then return end
    local inverse=1/determinant
    local transformX=inverse*(dirY*relX-dirX*relY)
    local depth=inverse*(-planeY*relX+planeX*relY)
    if depth<=.12 then return end
    local center=math.floor(width*(.5+transformX/depth*.5))
    local spriteHeight=math.max(1,math.min(viewH,math.floor(width/(2.6*depth))))
    local spriteWidth=math.max(1,math.floor(spriteHeight*1.4))
    local top=viewY+math.floor((viewH-spriteHeight)/2)
    local left=center-math.floor(spriteWidth/2)
    local color,symbol
    if kind=="enemy" then color,symbol=object.hp==1 and 0xe07535 or 0xb52f3e,"M"
    elseif kind=="ammo" then color,symbol=0xd5a83d,"A"
    elseif kind=="health" then color,symbol=0x3aa565,"+"
    else color,symbol=living()==0 and 0x48b9c7 or 0x59616d,"E" end
    local centerVisible=false
    for sx=math.max(1,left),math.min(width,left+spriteWidth-1) do
      if depth<(zbuffer[sx] or 1e8) then win:fill(sx,top,1,spriteHeight,shade(color,math.min(1,1.3/(depth*.25+1)))," ") if sx==center then centerVisible=true end end
    end
    if centerVisible then win:text(center,top+math.floor(spriteHeight/2),symbol,0xffffff,color) end
  end
  local function render(now)
    local width,height=win.width,win.height
    local viewY,viewH=2,math.max(3,height-7)
    local dirX,dirY=math.cos(player.a),math.sin(player.a)
    local planeX,planeY=-dirY*.66,dirX*.66
    win:reset()
    win:fill(1,viewY,width,math.floor(viewH/2),0x161b2b," ")
    win:fill(1,viewY+math.floor(viewH/2),width,viewH-math.floor(viewH/2),0x29231e," ")
    for x=1,width do
      local camera=2*(x-.5)/width-1
      local distance,kind,side=cast(player.x,player.y,dirX+planeX*camera,dirY+planeY*camera)
      zbuffer[x]=distance
      local wallHeight=math.max(1,math.min(viewH,math.floor(width/(2.6*distance))))
      local top=viewY+math.floor((viewH-wallHeight)/2)
      win:fill(x,top,1,wallHeight,shade(wallColors[kind] or wallColors[1],2.2/(distance+1.5)*(side==1 and .76 or 1))," ")
    end
    local sprites={}
    for _,enemy in ipairs(enemies) do if enemy.hp>0 then sprites[#sprites+1]={object=enemy,kind="enemy"} end end
    for _,pickup in ipairs(pickups) do if pickup.active then sprites[#sprites+1]={object=pickup,kind=pickup.kind=="A" and "ammo" or "health"} end end
    sprites[#sprites+1]={object=exit,kind="exit"}
    for _,sprite in ipairs(sprites) do local dx,dy=sprite.object.x-player.x,sprite.object.y-player.y sprite.distance=dx*dx+dy*dy end
    table.sort(sprites,function(a,b) return a.distance>b.distance end)
    for _,sprite in ipairs(sprites) do renderSprite(sprite.object,sprite.kind,dirX,dirY,planeX,planeY,viewY,viewH,width) end
    win:text(math.max(1,math.floor(width/2)-3),viewY+viewH-1,now<flash and "  *==|>" or "   ==|>",0xe1c4a1,0x29231e)
    local remaining=math.max(0,math.ceil(deadline-now))
    win:text(2,1,string.format("health %3d  ammo %2d  targets %d  time %03d",math.max(0,player.health),player.ammo,living(),remaining),state=="playing" and 0xf2f2f2 or 0xf0bd55,0x08090c)
    win:text(2,height-4,state=="playing" and status or (state=="won" and "map exit reached - restart" or state=="timeout" and "two-minute demo complete - restart" or "signal lost - restart"),0xf0bd55,0x08090c)
    win:text(2,height-5,"transformed bfs1h map01 demo - not doom",0x9ba4b3,0x08090c)
    local controls={{"forward","^"},{"back","v"},{"strafeL","<s"},{"strafeR","s>"},{"turnL","<<"},{"turnR",">>"},{"fire","fire"}}
    local buttonWidth=math.max(3,math.floor((width-8)/#controls))
    local x=2
    if width>=29 then for _,control in ipairs(controls) do win:button(control[1],x,height-2,buttonWidth,control[2]) x=x+buttonWidth+1 end end
    if state~="playing" then win:button("restart",math.max(2,width-10),height-4,9,"restart") end
    win:text(2,height-1,"w/s move | a/d strafe | arrows/q/e turn | space fire",0x9ba4b3,0x08090c)
  end
  local function active(name,now) return keys[name] or (pulses[name] or 0)>now end
  local function update(dt,now)
    if state~="playing" or expire(now) then return end
    local turn=(active("turnR",now) and 1 or 0)-(active("turnL",now) and 1 or 0)
    player.a=(player.a+turn*1.9*dt)%(2*pi)
    local forward=(active("forward",now) and 1 or 0)-(active("back",now) and 1 or 0)
    local strafe=(active("strafeR",now) and 1 or 0)-(active("strafeL",now) and 1 or 0)
    local length=math.sqrt(forward*forward+strafe*strafe)
    if length>0 then
      forward,strafe=forward/length,strafe/length
      local dx=(math.cos(player.a)*forward-math.sin(player.a)*strafe)*2.05*dt
      local dy=(math.sin(player.a)*forward+math.cos(player.a)*strafe)*2.05*dt
      if not blocked(player.x+dx,player.y) then player.x=player.x+dx end
      if not blocked(player.x,player.y+dy) then player.y=player.y+dy end
    end
    for _,pickup in ipairs(pickups) do
      local dx,dy=pickup.x-player.x,pickup.y-player.y
      if pickup.active and dx*dx+dy*dy<.36 then pickup.active=false if pickup.kind=="A" then player.ammo=player.ammo+8 status="ammo +8" else player.health=math.min(100,player.health+25) status="health +25" end end
    end
    for _,enemy in ipairs(enemies) do
      if enemy.hp>0 then
        local dx,dy=player.x-enemy.x,player.y-enemy.y
        local distance=math.sqrt(dx*dx+dy*dy)
        if distance<.9 then
          if now>=enemy.attack then enemy.attack=now+.85 player.health=player.health-9 status="sentinel strike" if player.health<=0 then state,status,keys="dead","signal lost",{} end end
        elseif distance<7 and lineClear(enemy.x,enemy.y,player.x,player.y) then
          local step=.48*dt
          local nx,ny=enemy.x+dx/distance*step,enemy.y+dy/distance*step
          if not blocked(nx,enemy.y,.16) then enemy.x=nx end
          if not blocked(enemy.x,ny,.16) then enemy.y=ny end
        end
      end
    end
    if state=="playing" then
      local dx,dy=exit.x-player.x,exit.y-player.y
      if dx*dx+dy*dy<.45 then if living()==0 then state,status,keys="won","map exit reached",{} else status="exit locked: clear the targets" end end
    end
  end
  local keyMap={[17]="forward",[200]="forward",[31]="back",[208]="back",[30]="strafeL",[32]="strafeR",[203]="turnL",[205]="turnR",[16]="turnL",[18]="turnR"}
  reset()
  local last,nextFrame=clock(),0
  while true do
    local now=clock()
    local frameTime=(win.width>70 or win.height>21) and .10 or .075
    local event={app.pull(math.max(0,math.min(frameTime,nextFrame-now)))}
    now=clock()
    local dt=math.min(.2,math.max(0,now-last)) last=now
    local name,char,code=event[1],event[3],event[4]
    if name=="key_down" then
      local action=keyMap[code]
      if action then keys[action]=true end
      if code==57 and not keys.fire then keys.fire=true shoot(now) end
      if (char==114 or char==82 or code==28) and state~="playing" then reset() end
    elseif name=="key_up" then
      local action=keyMap[code]
      if action then keys[action]=nil end
      if code==57 then keys.fire=nil end
    elseif name=="idk_button" then
      local id=event[3]
      if id=="fire" then shoot(now) elseif id=="restart" then reset() elseif id then pulses[id]=now+.20 end
    end
    if not app.focused() then keys={} nextFrame=now+frameTime
    else update(dt,now) if now>=nextFrame then render(now) nextFrame=now+frameTime end end
  end
end
