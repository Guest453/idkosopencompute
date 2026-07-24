local ui = {}
local unicode = require("unicode")

function ui.framebufferMemory(width,height)
  width,height=tonumber(width),tonumber(height)
  if not width or not height or width<1 or height<1 then return math.huge end
  -- six flat planes plus conservative lua table growth and renderer state.
  return math.floor(width)*math.floor(height)*112+65536
end

function ui.memorySafe(width,height,freeMemory,totalMemory)
  freeMemory,totalMemory=tonumber(freeMemory),tonumber(totalMemory)
  if not freeMemory or not totalMemory or freeMemory<0 or totalMemory<1 then return false end
  local headroom=math.max(384*1024,math.floor(totalMemory*.25))
  local required=ui.framebufferMemory(width,height)+headroom
  return freeMemory>=required,required
end

function ui.startupDisplayMode(maxWidth,maxHeight,freeMemory,totalMemory)
  maxWidth,maxHeight=tonumber(maxWidth),tonumber(maxHeight)
  if not maxWidth or not maxHeight then return "compact" end
  if ui.memorySafe(maxWidth,maxHeight,freeMemory,totalMemory) then return "native" end
  local balancedW,balancedH=math.min(maxWidth,80),math.min(maxHeight,25)
  if ui.memorySafe(balancedW,balancedH,freeMemory,totalMemory) then return "balanced" end
  return "compact"
end

-- a compact cell compositor. planes are flat to avoid thousands of row tables.
function ui.renderer(gpu, width, height, mirrors, mirrorFailed)
  local r = {width=width, height=height, fg=0xffffff, bg=0x000000}
  local chars, foregrounds, backgrounds = {}, {}, {}
  local oldChars, oldForegrounds, oldBackgrounds = {}, {}, {}
  local gpuFg, gpuBg = nil, nil
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
    chars[i],foregrounds[i],backgrounds[i]=char,fg,bg
  end

  function r.beginFrame()
    clips={{x1=1,y1=1,x2=width,y2=height}}
    for i=1,width*height do chars[i],foregrounds[i],backgrounds[i]=nil,nil,nil end
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
        chars[i],foregrounds[i],backgrounds[i]=char,r.fg,r.bg
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
        local drawn=chars[i]~=nil
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
            drawn=chars[i]~=nil
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
        local drawn=chars[i]~=nil
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

-- readable 7x5 icon tiles. shapes provide silhouettes while small ascii marks
-- stay legible on opencomputers fonts and low-depth gpus.
local function icon(palette,rows,glyphs,mark,markColor)
  return {palette=palette,rows=rows,glyphs=glyphs or {},mark=mark,markColor=markColor}
end

local iconArt={
  files=icon(
    {0x4d9de0,0xf4c451,0x96d2ff,0xffffff},
    {".222...","211111.","133333.","134443.",".11111."},
    {{3,4,"=",4},{4,4,"=",4}},"F",4),
  store=icon(
    {0x31a46d,0x8ce2bd,0xffffff,0x1d6c4d},
    {"..222..",".21112.","1111111","1333331",".11111."},
    {{4,3,"+",3}},"+",3),
  terminal=icon(
    {0x172331,0x26394d,0x5ee0a4,0xeaf4ff},
    {".11111.","1222221","1222221","1222221",".11111."},
    {{2,3,">",3},{4,3,"_",4}},">",3),
  settings=icon(
    {0x60738a,0xaac1d4,0x45a8e8,0xf1f6fa},
    {".11211.","1111111","1223221","1111111",".11211."},
    {{4,3,"o",4}},"o",4),
  calculator=icon(
    {0x3979bd,0xd9efff,0x64d49b,0x173957},
    {".11111.","1222221","1111111","1331331",".11111."},
    {{2,2,"7",4},{4,2,"8",4},{2,4,"+",4},{5,4,"=",4}},"+",4),
  systeminfo=icon(
    {0x665bc5,0xbab4ff,0xffffff,0x363078},
    {"..222..",".21112.",".21312.",".21112.","..222.."},
    {{4,3,"i",3}},"i",3),
  taskmanager=icon(
    {0x26394d,0x50cbea,0xf16f7c,0xeaf6ff},
    {".11111.","1222221","1232231","1242431",".12231."},
    {{2,2,"-",4},{3,3,"|",4},{5,2,"|",4}},"|",4),
  notes=icon(
    {0xf1f4f7,0x568bd3,0xf2bd4d,0x25384a},
    {".11111.","1222221","1333331","1333331",".11111."},
    {{3,3,"-",2},{4,3,"-",2},{3,4,"-",2},{4,4,"-",2}},"N",2),
  timer=icon(
    {0x7962be,0xc8baff,0xffffff,0x493b83},
    {"..222..",".21112.","1213121",".21112.","..222.."},
    {{4,3,"+",3}},"T",3),
  todo=icon(
    {0x31a46d,0xe9fff5,0x3579bd,0x174d39},
    {".11111.","1222221","1222221","1222221",".11111."},
    {{2,2,"x",2},{4,2,"-",2},{2,3,"x",2},{4,3,"-",2},{2,4,"x",2},{4,4,"-",2}},"x",2),
  diskusage=icon(
    {0x347da5,0x72c8df,0xf3ca55,0xffffff},
    {"..111..",".12221.","1233211","1233311",".11111."},
    {{4,3,"%",4}},"%",4),
  calendar=icon(
    {0xd75961,0xffffff,0x5794d0,0x26384a},
    {".11111.","1222221","3333333","3444443",".33333."},
    {{3,4,"2",4},{4,4,"4",4}},"2",4),
  components=icon(
    {0x496b84,0x76d6c1,0xf1c552,0xeaf7ff},
    {".2.2.2.","2111112","2113112","2111112",".2.2.2."},
    {{3,3,"C",4},{4,3,"P",4},{5,3,"U",4}},"C",4),
  inferno=icon(
    {0x2a1718,0xd45a37,0xf4a43c,0xffe2a3},
    {".11111.","1122211","1223221","1233321",".13331."},
    {},"^",4),
  chicken3d=icon(
    {0x65a44e,0xffffff,0xf0c44a,0xd84b43},
    {".11111.","122221.","122234.","112244.",".33333."},
    {{3,3,"o",4}},"o",2),
  snake=icon(
    {0x163d33,0x55d98b,0xf3ce53,0xb6f4c9},
    {".11111.","1222211","1111211","1333211",".11111."},
    {{4,3,"S",4}},"S",4),
  pong=icon(
    {0x162a4b,0x65c8ff,0xffffff,0xff6fae},
    {".11111.","1211121","1213121","1211121",".11111."},
    {{2,3,"|",2},{4,3,"o",3},{6,3,"|",4}},"o",3),
  minesweeper=icon(
    {0x34495e,0x9aabc0,0xe95662,0xf2c94c},
    {".11111.","1222221","1232321","1223221",".11111."},
    {{4,3,"*",3}},"*",3),
  breakout=icon(
    {0x17284a,0x55c8ff,0xff6f91,0xf4cf58},
    {".11111.","1334431","1443341","1112111",".12221."},
    {{4,4,"o",2}},"=",2),
  spamtontrash=icon(
    {0x141414,0xf2f2f2,0xff4db8,0xffdf42,0xd93443},
    {".11111.","1222221","1232421","1255521",".11111."},
    {{4,4,"$",2}},"$",3),
  sketch=icon(
    {0x6b5fc7,0xffca5c,0x53c6a2,0xffffff},
    {".11111.","1222311","1123311","1112311",".11121."},
    {{4,3,"/",4}},"/",4),
  game=icon(
    {0x394a62,0x68d391,0xf36f76,0xffffff},
    {".11111.","1222221","1233321","1243421",".11111."},
    {{2,3,"+",4},{5,3,"o",4}},"+",4)
}

local iconColors={0x4f8fe8,0x40b887,0xa06ee1,0xe0874c,0xd95f70,0x3fa7b5}
local iconCache,iconCacheSize={},0

local function fallbackArt(name,color)
  local letter=tostring(name or "app"):match("[%w]") or "?"
  letter=letter:upper()
  return icon(
    {color,0xffffff,0x1d2b3a},
    {".11111.","1111111","1111111","1111111",".11111."},
    {{4,3,letter,2}},letter,2)
end

local function paletteColor(palette,value)
  if type(value)~="number" then return 0xffffff end
  return palette[value] or value
end

function ui.icon(name,color,size)
  name=tostring(name or "app"):lower()
  local cacheKey=name..":"..tostring(color or "")..":"..tostring(size or "full")
  if iconCache[cacheKey] then return iconCache[cacheKey] end
  local hash=0 for i=1,#name do hash=(hash+name:byte(i)*i)%997 end
  local suppliedColor=tonumber(color)
  local art=iconArt[name] or fallbackArt(name,suppliedColor or iconColors[(hash%#iconColors)+1])
  local palette={table.unpack(art.palette)}
  if suppliedColor and suppliedColor>=0 and suppliedColor<=0xffffff then palette[1]=suppliedColor end
  local small=size=="small" or tonumber(size)==3
  local image={width=small and 5 or 7,height=small and 3 or 5,cells={}}
  local xs=small and {1,2,4,6,7} or {1,2,3,4,5,6,7}
  local ys=small and {1,3,5} or {1,2,3,4,5}

  for y=1,image.height do
    local sy=ys[y]
    for x=1,image.width do
      local sx=xs[x]
      local key=art.rows[sy]:sub(sx,sx)
      local index=tonumber(key)
      if index and palette[index] then
        image.cells[(y-1)*image.width+x]={char=" ",bg=palette[index],fg=palette[index]}
      end
    end
  end

  if small then
    local center=(2-1)*image.width+3
    local cell=image.cells[center] or {bg=palette[1]}
    image.cells[center]={char=unicode.sub(tostring(art.mark or "?"),1,1),fg=paletteColor(palette,art.markColor or 2),bg=cell.bg or palette[1]}
  else
    for _,glyph in ipairs(art.glyphs) do
      local x,y,char,fg=glyph[1],glyph[2],glyph[3],glyph[4]
      if x>=1 and x<=image.width and y>=1 and y<=image.height then
        local index=(y-1)*image.width+x
        local cell=image.cells[index] or {bg=palette[1]}
        image.cells[index]={char=unicode.sub(tostring(char or " "),1,1),fg=paletteColor(palette,fg),bg=cell.bg or palette[1]}
      end
    end
  end

  if #cacheKey<96 and iconCacheSize<128 then iconCache[cacheKey]=image iconCacheSize=iconCacheSize+1 end
  return image
end

local function monochrome(color)
  color=tonumber(color) or 0
  local red=math.floor(color/0x10000)%0x100
  local green=math.floor(color/0x100)%0x100
  local blue=color%0x100
  return red*3+green*6+blue>=1275 and 0xffffff or 0x202020
end

function ui.image(gpu,x,y,image)
  if type(image)~="table" or type(image.cells)~="table" then return end
  for py=1,(image.height or 0) do
    for px=1,(image.width or 0) do
      local cell=image.cells[(py-1)*image.width+px]
      if cell then
        local char=cell.char or " "
        local fg,bg=cell.fg,cell.bg
        if gpu.depth and gpu.depth<4 then
          bg=monochrome(bg)
          if char~=" " then
            fg=monochrome(fg)
            if fg==bg then fg=bg==0xffffff and 0x202020 or 0xffffff end
          else
            fg=bg
          end
        end
        gpu.cell(x+px-1,y+py-1,char,fg,bg)
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
