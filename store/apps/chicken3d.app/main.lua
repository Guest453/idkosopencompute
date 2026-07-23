return function(app)
  local win=app.window{title="chicken run 3d",width=70,height=28,bg=0x74a9d8}
  local near=0.12
  local player={x=0,z=-6,yaw=0}
  local score,goal,deadline,state=0,8,app.computer.uptime()+75,"play"
  local held,chickens={},{}
  local lastBeep=0
  local function beep(frequency,duration,interval)
    local now=app.computer.uptime()
    if now-lastBeep>=(interval or .05) then pcall(app.computer.beep,frequency,duration or .04) lastBeep=now end
  end
  local obstacles={{-3,-1,1.4,1.4},{2,2,1.8,1.2},{-1,4,1.2,1.8}}
  local function atan2(y,x)
    if math.atan2 then return math.atan2(y,x) end
    if x>0 then return math.atan(y/x) elseif x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi)
    elseif y>0 then return math.pi/2 elseif y<0 then return -math.pi/2 end
    return 0
  end

  local function spawn(chicken)
    chicken.x=-7+math.random()*14 chicken.z=-3+math.random()*10
    chicken.dir=math.random()*math.pi*2 chicken.turn=1+math.random()*2
  end
  for i=1,5 do chickens[i]={} spawn(chickens[i]) end

  local function restart()
    player.x,player.z,player.yaw=0,-6,0
    score,deadline,state=0,app.computer.uptime()+75,"play"
    for _,chicken in ipairs(chickens) do spawn(chicken) end
    beep(520,.04)
  end

  local function blocked(x,z)
    if x<-8.4 or x>8.4 or z<-7.4 or z>8.4 then return true end
    for _,o in ipairs(obstacles) do
      if math.abs(x-o[1])<o[3]/2+0.28 and math.abs(z-o[2])<o[4]/2+0.28 then return true end
    end
    return false
  end

  local function move(amount)
    local nx=player.x+math.sin(player.yaw)*amount
    local nz=player.z+math.cos(player.yaw)*amount
    if not blocked(nx,player.z) then player.x=nx end
    if not blocked(player.x,nz) then player.z=nz end
  end

  local function catch()
    if state~="play" then restart() return end
    local best,bestDistance
    for i,chicken in ipairs(chickens) do
      local dx,dz=chicken.x-player.x,chicken.z-player.z
      local distance=math.sqrt(dx*dx+dz*dz)
      local angle=atan2(dx,dz)-player.yaw
      angle=(angle+math.pi)%(math.pi*2)-math.pi
      if distance<2.3 and math.abs(angle)<0.48 and (not bestDistance or distance<bestDistance) then best,bestDistance=i,distance end
    end
    if best then
      score=score+1 spawn(chickens[best])
      if score>=goal then state="won" beep(1400,.12) else beep(900,.05) end
    else beep(220,.03,.12) end
  end

  local function addTriangle(list,a,b,c,color)
    list[#list+1]={a,b,c,color}
  end
  local function box(list,x,y,z,w,h,d,color)
    local x1,x2,z1,z2=x-w/2,x+w/2,z-d/2,z+d/2
    local y1,y2=y,y+h
    local p={{x1,y1,z1},{x2,y1,z1},{x2,y2,z1},{x1,y2,z1},{x1,y1,z2},{x2,y1,z2},{x2,y2,z2},{x1,y2,z2}}
    local faces={{1,2,3,4},{6,5,8,7},{5,1,4,8},{2,6,7,3},{4,3,7,8},{5,6,2,1}}
    for faceIndex,f in ipairs(faces) do
      local shade=faceIndex==5 and math.min(0xffffff,color+0x101010) or (faceIndex==6 and math.max(0,color-0x181818) or color)
      addTriangle(list,p[f[1]],p[f[2]],p[f[3]],shade)
      addTriangle(list,p[f[1]],p[f[3]],p[f[4]],shade)
    end
  end

  local static={}
  addTriangle(static,{-9,0,-8},{9,0,-8},{9,0,9},0x4f943f)
  addTriangle(static,{-9,0,-8},{9,0,9},{-9,0,9},0x4f943f)
  box(static,0,0,-8.1,18,.7,.25,0x93683f) box(static,0,0,8.7,18,.7,.25,0x93683f)
  box(static,-8.7,0,.3,.25,.7,17,0x93683f) box(static,8.7,0,.3,.25,.7,17,0x93683f)
  for _,o in ipairs(obstacles) do box(static,o[1],0,o[2],o[3],1.25,o[4],0x8a704d) end

  local function cameraVertex(vertex)
    local dx,dz=vertex[1]-player.x,vertex[3]-player.z
    local c,s=math.cos(player.yaw),math.sin(player.yaw)
    return {c*dx-s*dz,vertex[2]-1.35,s*dx+c*dz}
  end
  local function intersect(a,b)
    local denominator=b[3]-a[3]
    local t=math.abs(denominator)>1e-9 and (near-a[3])/denominator or 0
    return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,near}
  end
  local function clipNear(poly)
    local output={}
    for i=1,#poly do
      local a,b=poly[i],poly[i%#poly+1]
      local insideA,insideB=a[3]>=near,b[3]>=near
      if insideA then output[#output+1]=a end
      if insideA~=insideB then output[#output+1]=intersect(a,b) end
    end
    return output
  end

  local function render()
    local contentW,contentH=win:size()
    local low=app.computer.totalMemory()<1024*1024
    local rw=math.min(contentW,low and 42 or 56)
    local rh=math.min(contentH,low and 18 or 22)
    if rw<12 or rh<8 then return end
    local backgrounds,depth={},{}
    local horizon=math.floor(rh*.48)
    for y=1,rh do for x=1,rw do local i=(y-1)*rw+x backgrounds[i]=y<=horizon and 0x74a9d8 or 0x477e39 depth[i]=1e30 end end
    local triangles={}
    for _,triangle in ipairs(static) do triangles[#triangles+1]=triangle end
    for _,chicken in ipairs(chickens) do
      box(triangles,chicken.x,.32,chicken.z,.85,.65,1.05,0xf1f0e8)
      local fx,fz=math.sin(chicken.dir),math.cos(chicken.dir)
      box(triangles,chicken.x+fx*.48,.72,chicken.z+fz*.48,.55,.55,.55,0xffffff)
      box(triangles,chicken.x+fx*.82,.83,chicken.z+fz*.82,.28,.18,.35,0xf2c84b)
      box(triangles,chicken.x,.0,chicken.z-.24,.13,.38,.13,0xe6b93f)
      box(triangles,chicken.x,.0,chicken.z+.24,.13,.38,.13,0xe6b93f)
      box(triangles,chicken.x+fx*.48,1.24,chicken.z+fz*.48,.18,.22,.18,0xd94b45)
    end
    local focal=rw*.58
    local fy=focal*.5 -- cells are approximately twice as tall as they are wide.
    local samples,sampleBudget=0,low and 24000 or 48000
    local function raster(a,b,c,color)
      local minX=math.max(1,math.floor(math.min(a[1],b[1],c[1])))
      local maxX=math.min(rw,math.ceil(math.max(a[1],b[1],c[1])))
      local minY=math.max(1,math.floor(math.min(a[2],b[2],c[2])))
      local maxY=math.min(rh,math.ceil(math.max(a[2],b[2],c[2])))
      local work=math.max(0,maxX-minX+1)*math.max(0,maxY-minY+1)
      if samples+work>sampleBudget then return end
      samples=samples+work
      local area=(b[1]-a[1])*(c[2]-a[2])-(b[2]-a[2])*(c[1]-a[1])
      if math.abs(area)<1e-7 then return end
      for y=minY,maxY do for x=minX,maxX do
        local px,py=x+.5,y+.5
        local w1=((b[1]-px)*(c[2]-py)-(b[2]-py)*(c[1]-px))/area
        local w2=((c[1]-px)*(a[2]-py)-(c[2]-py)*(a[1]-px))/area
        local w3=1-w1-w2
        if w1>=-1e-6 and w2>=-1e-6 and w3>=-1e-6 then
          local z=w1*a[3]+w2*b[3]+w3*c[3]
          local index=(y-1)*rw+x
          if z>=near and z<depth[index] then depth[index],backgrounds[index]=z,color end
        end
      end end
    end
    for _,triangle in ipairs(triangles) do
      local poly=clipNear({cameraVertex(triangle[1]),cameraVertex(triangle[2]),cameraVertex(triangle[3])})
      if #poly>=3 then
        local projected={}
        for i,v in ipairs(poly) do projected[i]={rw/2+v[1]/v[3]*focal,rh/2-v[2]/v[3]*fy,v[3]} end
        for i=2,#projected-1 do raster(projected[1],projected[i],projected[i+1],triangle[4]) end
      end
    end
    win:reset()
    win:canvas(1,1,rw,rh,{backgrounds=backgrounds})
    local left=math.max(0,math.ceil(deadline-app.computer.uptime()))
    win:text(2,1,string.format("chickens %d/%d   time %ds",score,goal,left),0xffffff,0x284a32)
    if state=="play" then
      win:text(2,rh,"[wasd/arrows] move/turn  [space/e] catch",0xffffff,0x284a32)
      if rw>=46 then win:text(rw-16,rh-2,"touch: < ^ > catch",0xffffff,0x284a32) end
    else
      local message=state=="won" and "all chickens caught!" or "time is up"
      win:text(math.max(2,math.floor((rw-#message)/2)),math.floor(rh/2),message,0xffffff,0x284a32)
      win:text(math.max(2,math.floor((rw-22)/2)),math.floor(rh/2)+1,"space/touch to restart",0xffffff,0x284a32)
    end
  end

  local last,renderAt=app.computer.uptime(),0
  while true do
    local now=app.computer.uptime()
    local dt=math.min(.2,math.max(0,now-last)) last=now
    if not app.focused() then held={} app.pull(.15)
    else
      if state=="play" then
        if now>=deadline then state="lost" beep(160,.14)
        else
          if held.forward then move(3.2*dt) end if held.back then move(-2.4*dt) end
          if held.left then player.yaw=player.yaw-1.8*dt end if held.right then player.yaw=player.yaw+1.8*dt end
          for _,chicken in ipairs(chickens) do
            chicken.turn=chicken.turn-dt
            if chicken.turn<=0 then chicken.dir=chicken.dir+(math.random()-.5)*1.8 chicken.turn=.8+math.random()*2.2 end
            local nx=chicken.x+math.sin(chicken.dir)*dt*.7 local nz=chicken.z+math.cos(chicken.dir)*dt*.7
            if nx>-8 and nx<8 and nz>-7 and nz<8 then chicken.x,chicken.z=nx,nz else chicken.dir=chicken.dir+math.pi end
          end
        end
      end
      if now>=renderAt then render() renderAt=now+.14 end
      local name,_,char,code=app.pull(.05)
      if name=="key_down" or name=="key_up" then
        local down=name=="key_down"
        if char==119 or code==200 then held.forward=down elseif char==115 or code==208 then held.back=down
        elseif char==97 or code==203 then held.left=down elseif char==100 or code==205 then held.right=down end
        if down and (char==32 or char==101 or code==28) then catch() end
      elseif name=="touch" then
        local x,y=char,code
        local width,height=win:size()
        if state~="play" then restart()
        elseif y>=height-4 then
          if x<width*.25 then player.yaw=player.yaw-.28 elseif x<width*.5 then move(.6)
          elseif x<width*.75 then player.yaw=player.yaw+.28 else catch() end
        else catch() end
      end
    end
  end
end
