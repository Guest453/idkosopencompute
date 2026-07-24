return function(app)
  local keyboard=require("keyboard")
  local win=app.window{title="block merge",width=43,height=19}
  local board,score,best,status={},0,0,"use arrows or buttons"

  local colors={
    [0]=0xdce6ee,[2]=0xeef2f5,[4]=0xdcebf2,[8]=0xf2d39a,[16]=0xf0b36c,
    [32]=0xeb8b64,[64]=0xe66355,[128]=0xe6c85a,[256]=0xd7b83f,[512]=0xc99d2e,
    [1024]=0x9c7ce3,[2048]=0x6d5bd0
  }

  local function index(x,y) return (y-1)*4+x end
  local function reset()
    board={} for i=1,16 do board[i]=0 end
    score,status=0,"new game"
    local function add()
      local empty={} for i=1,16 do if board[i]==0 then empty[#empty+1]=i end end
      if #empty>0 then board[empty[math.random(1,#empty)]]=math.random(1,10)==1 and 4 or 2 end
    end
    add() add()
  end

  local function addTile()
    local empty={} for i=1,16 do if board[i]==0 then empty[#empty+1]=i end end
    if #empty>0 then board[empty[math.random(1,#empty)]]=math.random(1,10)==1 and 4 or 2 end
  end

  local function compress(line)
    local values={}
    for _,value in ipairs(line) do if value~=0 then values[#values+1]=value end end
    local out={} local gained=0 local i=1
    while i<=#values do
      if values[i+1] and values[i]==values[i+1] then
        local merged=values[i]*2 out[#out+1]=merged gained=gained+merged i=i+2
      else out[#out+1]=values[i] i=i+1 end
    end
    while #out<4 do out[#out+1]=0 end
    return out,gained
  end

  local function canMove()
    for i=1,16 do if board[i]==0 then return true end end
    for y=1,4 do for x=1,4 do
      local value=board[index(x,y)]
      if x<4 and board[index(x+1,y)]==value then return true end
      if y<4 and board[index(x,y+1)]==value then return true end
    end end
    return false
  end

  local function move(direction)
    local before={} for i=1,16 do before[i]=board[i] end
    local gained=0
    for lineIndex=1,4 do
      local line={}
      for pos=1,4 do
        local x,y
        if direction=="left" then x,y=pos,lineIndex
        elseif direction=="right" then x,y=5-pos,lineIndex
        elseif direction=="up" then x,y=lineIndex,pos
        else x,y=lineIndex,5-pos end
        line[pos]=board[index(x,y)]
      end
      local merged,points=compress(line) gained=gained+points
      for pos=1,4 do
        local x,y
        if direction=="left" then x,y=pos,lineIndex
        elseif direction=="right" then x,y=5-pos,lineIndex
        elseif direction=="up" then x,y=lineIndex,pos
        else x,y=lineIndex,5-pos end
        board[index(x,y)]=merged[pos]
      end
    end
    local changed=false for i=1,16 do if board[i]~=before[i] then changed=true break end end
    if changed then score=score+gained best=math.max(best,score) addTile() status="merged +"..gained
    else status=canMove() and "that direction is blocked" or "game over - press new" end
  end

  local function draw()
    win:reset()
    win:fill(1,1,win.width,2,0xe8eef4)
    win:text(2,1,"block merge",0x1d2b3a,0xe8eef4)
    win:text(20,1,"score "..score.."  best "..best,0x617487,0xe8eef4)
    local ox,oy=3,4
    for y=1,4 do for x=1,4 do
      local value=board[index(x,y)]
      local px=ox+(x-1)*9 local py=oy+(y-1)*3
      local bg=colors[value] or 0x5d4ab4
      win:fill(px,py,8,2,bg)
      local text=value==0 and "" or tostring(value)
      win:text(px+math.max(0,math.floor((8-#text)/2)),py+1,text,value>=128 and 0xffffff or 0x25384a,bg)
    end end
    local by=win.height-3
    win:button("left",3,by,8,"< left")
    win:button("up",12,by,8,"^ up")
    win:button("down",21,by,8,"v down")
    win:button("right",30,by,9,"right >")
    win:button("new",3,by+1,8,"new")
    win:text(12,by+1,status,0x617487)
  end

  math.randomseed(math.floor(app.computer.uptime()*1000)%2147483647)
  reset()
  while true do
    draw()
    local name,address,char,code=app.pull()
    if name=="idk_button" then
      if char=="left" or char=="right" or char=="up" or char=="down" then move(char)
      elseif char=="new" then reset() end
    elseif name=="key_down" then
      if code==keyboard.keys.left then move("left")
      elseif code==keyboard.keys.right then move("right")
      elseif code==keyboard.keys.up then move("up")
      elseif code==keyboard.keys.down then move("down")
      elseif code==keyboard.keys.n then reset() end
    end
  end
end
