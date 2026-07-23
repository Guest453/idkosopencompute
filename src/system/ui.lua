local ui = {}
local unicode = require("unicode")

-- a compact cell compositor. planes are flat to avoid thousands of row tables.
function ui.renderer(gpu, width, height, mirrors, mirrorFailed)
  local r = {width=width, height=height, fg=0xffffff, bg=0x000000}
  local chars, foregrounds, backgrounds, marks = {}, {}, {}, {}
  local oldChars, oldForegrounds, oldBackgrounds = {}, {}, {}
  local frame, gpuFg, gpuBg = 0, nil, nil
  mirrors=mirrors or {}
  local clips = {{x1=1,y1=1,x2=width,y2=height}}
  local depthOk, depth = pcall(gpu.getDepth)
  r.depth=depthOk and depth or 1
  local upperOk,upperHalf=pcall(unicode.char,0x2580)
  local lowerOk,lowerHalf=pcall(unicode.char,0x2584)
  r.semiPixels = depthOk and depth >= 4 and upperOk and lowerOk and type(upperHalf)=="string" and type(lowerHalf)=="string" and unicode.len(upperHalf)==1 and unicode.len(lowerHalf)==1

  local function index(x,y) return (y-1)*width+x end
  local function clip() return clips[#clips] end
  local function visible(x,y)
    local c=clip()
    return x>=c.x1 and x<=c.x2 and y>=c.y1 and y<=c.y2
  end
  local function put(x,y,char,fg,bg)
    if not visible(x,y) then return end
    local i=index(x,y)
    chars[i],foregrounds[i],backgrounds[i],marks[i]=char,fg,bg,frame
  end

  function r.beginFrame()
    frame=frame+1
    clips={{x1=1,y1=1,x2=width,y2=height}}
  end
  function r.setForeground(color) r.fg=color end
  function r.setBackground(color) r.bg=color end

  function r.pushClip(x,y,w,h)
    local c=clip()
    clips[#clips+1]={
      x1=math.max(c.x1,x),y1=math.max(c.y1,y),
      x2=math.min(c.x2,x+w-1),y2=math.min(c.y2,y+h-1)
    }
  end
  function r.popClip() if #clips>1 then clips[#clips]=nil end end

  function r.fill(x,y,w,h,char)
    if w<1 or h<1 then return end
    char=unicode.sub(tostring(char or " "),1,1)
    local c=clip()
    local x1,x2=math.max(c.x1,x),math.min(c.x2,x+w-1)
    local y1,y2=math.max(c.y1,y),math.min(c.y2,y+h-1)
    for py=y1,y2 do
      local offset=(py-1)*width
      for px=x1,x2 do
        local i=offset+px
        chars[i],foregrounds[i],backgrounds[i],marks[i]=char,r.fg,r.bg,frame
      end
    end
  end

  function r.set(x,y,value)
    if y<1 or y>height then return end
    value=tostring(value)
    for n=1,unicode.len(value) do
      local px=x+n-1
      if visible(px,y) then put(px,y,unicode.sub(value,n,n),r.fg,r.bg) end
    end
  end

  function r.cell(x,y,char,fg,bg)
    put(x,y,unicode.sub(tostring(char or " "),1,1),fg or r.fg,bg or r.bg)
  end

  -- one character cell represents two vertical color samples when available.
  function r.semi(x,y,upper,lower)
    if r.semiPixels then put(x,y,upperHalf,upper,lower) else put(x,y," ",r.fg,upper or lower or r.bg) end
  end

  function r.flush()
    for y=1,height do
      local x=1
      while x<=width do
        local i=index(x,y)
        local drawn=marks[i]==frame
        local ch=drawn and chars[i] or " "
        local fg=drawn and foregrounds[i] or r.fg
        local bg=drawn and backgrounds[i] or r.bg
        if oldChars[i]==ch and oldForegrounds[i]==fg and oldBackgrounds[i]==bg then
          x=x+1
        else
          local start,text=x,{ch}
          x=x+1
          while x<=width do
            i=index(x,y)
            drawn=marks[i]==frame
            ch=drawn and chars[i] or " "
            local nextFg=drawn and foregrounds[i] or r.fg
            local nextBg=drawn and backgrounds[i] or r.bg
            if nextFg~=fg or nextBg~=bg or (oldChars[i]==ch and oldForegrounds[i]==nextFg and oldBackgrounds[i]==nextBg) then break end
            text[#text+1]=ch
            x=x+1
          end
          local run=table.concat(text)
          if gpuBg~=bg then gpu.setBackground(bg) gpuBg=bg end
          if gpuFg~=fg then gpu.setForeground(fg) gpuFg=fg end
          gpu.set(start,y,run)
          for mirrorIndex=#mirrors,1,-1 do
            local mirror=mirrors[mirrorIndex]
            local ok=pcall(function()
              if mirror.bg~=bg then mirror.gpu.setBackground(bg) mirror.bg=bg end
              if mirror.fg~=fg then mirror.gpu.setForeground(fg) mirror.fg=fg end
              mirror.gpu.set(start,y,run)
            end)
            if not ok then
              table.remove(mirrors,mirrorIndex)
              if mirrorFailed then pcall(mirrorFailed,mirror) end
            end
          end
        end
      end
      local offset=(y-1)*width
      for px=1,width do
        local i=offset+px
        local drawn=marks[i]==frame
        oldChars[i]=drawn and chars[i] or " "
        oldForegrounds[i]=drawn and foregrounds[i] or r.fg
        oldBackgrounds[i]=drawn and backgrounds[i] or r.bg
      end
    end
  end

  function r.invalidate()
    oldChars,oldForegrounds,oldBackgrounds={},{},{}
    gpuFg,gpuBg=nil,nil
    for _,mirror in ipairs(mirrors) do mirror.fg,mirror.bg=nil,nil end
  end
  return r
end

function ui.clip(value, low, high) return math.max(low, math.min(high, value)) end
function ui.fill(gpu,x,y,w,h,bg,char)
  if w<1 or h<1 then return end
  gpu.setBackground(bg) gpu.fill(x,y,w,h,char or " ")
end
function ui.text(gpu,x,y,text,fg,bg)
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
  gpu.set(x,y,tostring(text))
end
function ui.center(gpu,x,y,w,text,fg,bg)
  text=tostring(text)
  ui.text(gpu,x+math.max(0,math.floor((w-unicode.len(text))/2)),y,text,fg,bg)
end
function ui.button(gpu,x,y,w,label,active,activeBg,inactiveBg)
  if w<1 then return end
  local bg=active and (activeBg or 0x3b82f6) or (inactiveBg or 0x30343b)
  ui.fill(gpu,x,y,w,1,bg)
  ui.center(gpu,x,y,w,unicode.sub(tostring(label),1,w),0xffffff,bg)
end
function ui.inside(px,py,x,y,w,h) return px>=x and py>=y and px<x+w and py<y+h end

-- compact cell art: each seven-character row indexes a small per-image palette;
-- dots are transparent. this retains shape and color without large pixel tables.
local iconArt={
  files={{0xf5b942,0xffd66b,0x4c8bd9},{".111...","122222.","133332.","133332.",".11111."}},
  store={{0x36b37e,0x7ee2b8,0xffffff},{"..333..",".31113.","1111111","1222221",".11111."}},
  terminal={{0x202a38,0x4fd1a1,0xe8f0f7},{"1111111","1222221","1232221","1223321","1111111"}},
  settings={{0x65758b,0xa9b8c9,0x49a4e8},{"1.111.1",".12321.","1123211",".12321.","1.111.1"}},
  calculator={{0x3e78bd,0xdceaff,0x67d2a5},{"1111111","1222221","1111111","1331331","1111111"}},
  systeminfo={{0x6b62c9,0xbab5ff,0xffffff},{"..111..",".12221.","..131..","..131..",".11111."}},
  taskmanager={{0x29384a,0x52c7ea,0xf06f7d},{"1111111","1222231","1213231","1231211","1111111"}},
  notes={{0xf2f4f7,0x5d8ed6,0xf0b84b},{".11111.",".12221.",".13331.",".12221.",".11111."}},
  timer={{0x7d65c1,0xc9baff,0xffffff},{"..111..",".12221.","1233321",".12321.","..111.."}},
  todo={{0x35a870,0xe7fff5,0x2d6ca8},{".11111.",".12221.",".13221.",".12231.",".11111."}},
  diskusage={{0x377fa8,0x73c6df,0xf4c95d},{"..111..",".12221.","1222221","1333321",".11111."}},
  calendar={{0xd85b62,0xffffff,0x5794d0},{".11111.","1222221","1331331","1323331",".11111."}},
  components={{0x4c6f87,0x7dd8c3,0xf1c75b},{"..121..",".11211.","1212121",".11311.","..121.."}},
  chicken3d={{0x66a84f,0xffffff,0xf2c84b,0xd94b45},{"..222..",".22223.",".222444",".3.3...","1111111"}},
  snake={{0x173f35,0x55d98b,0xf4cf55},{"1111111","12222.1","1...2.1","1.322.1","1111111"}},
  pong={{0x172b4d,0x65c8ff,0xffffff},{"1111111","12...21","12.3.21","12...21","1111111"}},
  sketch={{0x6b5fc7,0xffca5c,0x53c6a2},{".....11","...1121",".11221.","12221..","111...."}},
  game={{0x394a62,0x68d391,0xf36f76},{".11111.","1221221","1232221","1221321",".11111."}}
}
local iconColors={0x4f8fe8,0x40b887,0xa06ee1,0xe0874c,0xd95f70,0x3fa7b5}
local iconCache,iconCacheSize={},0

local function fallbackArt(name,color)
  local hash=0 for i=1,#name do hash=(hash*33+name:byte(i))%65521 end
  local rows={}
  for y=1,5 do
    local row={}
    for x=1,7 do
      local edge=x==1 or x==7 or y==1 or y==5
      row[x]=edge and "1" or (((hash+17*x+31*y)%(4+x+y)<2) and "2" or ".")
    end
    rows[y]=table.concat(row)
  end
  return {{color,0xffffff,0x26384a},rows}
end

function ui.icon(name,color,size)
  name=tostring(name or "app"):lower()
  local cacheKey=name..":"..tostring(color or "")..":"..tostring(size or "full")
  if iconCache[cacheKey] then return iconCache[cacheKey] end
  local hash=0 for i=1,#name do hash=(hash+name:byte(i)*i)%997 end
  local suppliedColor=tonumber(color)
  local art=iconArt[name] or fallbackArt(name,suppliedColor or iconColors[(hash%#iconColors)+1])
  local palette={table.unpack(art[1])}
  if suppliedColor and suppliedColor>=0 and suppliedColor<=0xffffff then palette[1]=suppliedColor end
  local small=size=="small" or tonumber(size)==3
  local image={width=small and 5 or 7,height=small and 3 or 5,cells={}}
  for y=1,image.height do
    local sy=small and ({1,3,5})[y] or y
    for x=1,image.width do
      local sx=small and ({1,2,4,6,7})[x] or x
      local key=art[2][sy]:sub(sx,sx)
      local index=tonumber(key)
      if index and palette[index] then image.cells[(y-1)*image.width+x]={char=" ",bg=palette[index],fg=palette[index]} end
    end
  end
  if #cacheKey<96 and iconCacheSize<128 then iconCache[cacheKey]=image iconCacheSize=iconCacheSize+1 end
  return image
end

function ui.image(gpu,x,y,image)
  if type(image)~="table" or type(image.cells)~="table" then return end
  for py=1,(image.height or 0) do
    for px=1,(image.width or 0) do
      local cell=image.cells[(py-1)*image.width+px]
      if cell then
        local fg,bg=cell.fg,cell.bg
        if gpu.depth and gpu.depth<4 then
          local color=tonumber(bg) or 0
          local luminance=math.floor(color/0x10000)*3+math.floor(color/0x100)%0x100*6+color%0x100
          bg=luminance>=1275 and 0xffffff or 0x202020
          fg=bg
        end
        gpu.cell(x+px-1,y+py-1,cell.char or " ",fg,bg)
      end
    end
  end
end

function ui.semiRect(gpu,x,semiY,w,semiH,color,base)
  if w<1 or semiH<1 then return end
  local first,last=math.floor((semiY+1)/2),math.floor((semiY+semiH)/2)
  if not gpu.semiPixels then ui.fill(gpu,x,first,w,last-first+1,color) return end
  for cy=first,last do
    local upper=(cy*2-1>=semiY and cy*2-1<semiY+semiH) and color or base
    local lower=(cy*2>=semiY and cy*2<semiY+semiH) and color or base
    for px=x,x+w-1 do gpu.semi(px,cy,upper or base,lower or base) end
  end
end

return ui
