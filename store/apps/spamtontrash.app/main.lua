return function(app)
  local unicode=require("unicode")
  local win=app.window{title="SPAMTON TRASH",width=40,height=22,bg=0x000000}
  local rows={
    "........................",
    "........gggggg..........",
    ".......gwwwwwwg.........",
    "......gwwwwwwwwg........",
    "......wwwwwwwwww........",
    ".....wwddddddddww.......",
    ".....wddppddyyddw.......",
    ".....wdpppddyyydw.......",
    ".....wddpddddyddw.......",
    ".....wwwddddddwwwwwgg...",
    "......wwwddddwww........",
    "......wwddddddww........",
    "......wddrrrrddw........",
    ".......wrrrrrrw.........",
    "........wwwwww..........",
    ".........dddd...........",
    "..ww....ddwwdd....ww....",
    ".wwwg..ddwwwwdd..gwww...",
    "wwggg.ddwwwwwwdd.gggww..",
    "wgg...dwwwddwwwd...ggw..",
    "......dwwddddwwd........",
    "......dwwddddwwd........",
    "......dwwddddwwd........",
    "......ddwwddwwdd........",
    "......gddwddwddg........",
    ".....gg.dddd.ddgg.......",
    "....gg..dddd..gg........",
    "...ww...dd.dd...ww......",
    "..www..ddd.ddd..www.....",
    ".wwww.gddd..dddg.wwww...",
    ".wwwwggdd....ddggwwww...",
    "..wwww..........wwww...."
  }
  local palette={w=0xf2f2f2,g=0x9b9b9b,d=0x24242b,p=0xff45b5,y=0xffdf42,r=0xd93443}

  -- decode a bounded palette-row image into upper/lower half-block canvas cells.
  local function paletteImage(logicalRows,colors)
    local width=#logicalRows[1] local height=math.ceil(#logicalRows/2)
    local backgrounds,foregrounds,glyphs={},{},{}
    local half=unicode.char(0x2580)
    for y=1,height do for x=1,width do
      local upper=colors[logicalRows[y*2-1]:sub(x,x)] or 0x000000
      local lowerRow=logicalRows[y*2]
      local lower=lowerRow and colors[lowerRow:sub(x,x)] or 0x000000
      local i=(y-1)*width+x
      backgrounds[i],foregrounds[i],glyphs[i]=lower,upper,half
    end end
    return width,height,{backgrounds=backgrounds,foregrounds=foregrounds,glyphs=glyphs}
  end
  local imageW,imageH,image=paletteImage(rows,palette)
  while true do
    local width,height=win:size()
    win:reset() win:fill(1,1,width,height,0x000000)
    win:text(math.max(1,math.floor((width-13)/2)),1,"SPAMTON TRASH",0xffffff,0x000000)
    local x=math.max(1,math.floor((width-imageW)/2)+1)
    local y=math.max(2,math.floor((height-imageH)/2))
    win:canvas(x,y,imageW,imageH,image)
    win:text(math.max(1,math.floor((width-23)/2)),height,"original native pixel portrait",0x8f8f9d,0x000000)
    app.pull(.5)
  end
end
