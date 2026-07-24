return function(app)
  local win=app.window{title="lights out",width=42,height=20}
  local cells,moves,status={},0,"turn every light off"
  local function idx(x,y) return (y-1)*5+x end
  local function toggle(x,y)
    if x>=1 and x<=5 and y>=1 and y<=5 then cells[idx(x,y)]=not cells[idx(x,y)] end
  end
  local function press(x,y,count)
    toggle(x,y) toggle(x-1,y) toggle(x+1,y) toggle(x,y-1) toggle(x,y+1)
    if count then moves=moves+1 end
  end
  local function won()
    for i=1,25 do if cells[i] then return false end end
    return true
  end
  local function reset()
    for i=1,25 do cells[i]=false end
    moves=0 status="turn every light off"
    for i=1,18 do press(math.random(1,5),math.random(1,5),false) end
    if won() then press(3,3,false) end
  end
  local function draw()
    win:reset()
    win:fill(1,1,win.width,2,0xe8eef4)
    win:text(2,1,"lights out",0x1d2b3a,0xe8eef4)
    win:text(23,1,"moves "..moves,0x617487,0xe8eef4)
    local ox,oy=4,4
    for y=1,5 do for x=1,5 do
      local px=ox+(x-1)*7 local py=oy+(y-1)*2
      local on=cells[idx(x,y)]
      local bg=on and 0xffd84d or 0x34495e
      win:fill(px,py,5,1,bg)
      win:text(px+2,py,on and "*" or ".",on and 0x473b12 or 0xb8c7d3,bg)
    end end
    local by=win.height-3
    win:button("new",4,by,9,"new game")
    win:button("solve",14,by,9,"reset")
    win:text(24,by,status,0x617487)
  end
  math.randomseed((math.floor(app.computer.uptime()*1000)+97)%2147483647)
  reset()
  while true do
    draw()
    local name,address,id,y=app.pull()
    if name=="idk_button" then
      if id=="new" or id=="solve" then reset() end
    elseif name=="touch" then
      local gx=math.floor((id-4)/7)+1
      local gy=math.floor((y-4)/2)+1
      local px=4+(gx-1)*7
      local py=4+(gy-1)*2
      if gx>=1 and gx<=5 and gy>=1 and gy<=5 and id>=px and id<px+5 and y==py then
        press(gx,gy,true)
        status=won() and ("solved in "..moves.." moves") or "keep going"
      end
    end
  end
end
