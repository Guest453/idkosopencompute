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
    if not visible(x,y) or (upper==nil and lower==nil) then return end
    local requestedUpper,requestedLower=upper,lower
    local i=index(x,y)
    local oldChar,oldFg,oldBg=chars[i] or " ",foregrounds[i] or r.fg,backgrounds[i] or r.bg
    local oldUpper,oldLower=oldBg,oldBg
    if oldChar==upperHalf then oldUpper=oldFg elseif oldChar==lowerHalf then oldLower=oldFg end
    upper,lower=upper or oldUpper,lower or oldLower
    if r.semiPixels then
      if upper==lower then put(x,y," ",upper,upper) else put(x,y,upperHalf,upper,lower) end
    else
      local color=requestedUpper or requestedLower or oldBg
      local red,green,blue=math.floor(color/0x10000)%0x100,math.floor(color/0x100)%0x100,color%0x100
      put(x,y," ",color,(red*3+green*6+blue)>=1275 and 0xffffff or 0x202020)
    end
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

-- native logical-pixel art: each palette-indexed row is eight pixels wide and
-- pairs with its neighbor through a half-block cell. dots preserve the surface.
local iconArt={
  files={{0x73b9f5,0x2585d8,0xdaf1ff,0x173957},{".111111.","11122222","11122222","11122222","11122222","11122222","11122222","11122222","11142242","11122222","11144422","..1111.."}},
  store={{0x35aa78,0x72ddb1,0xffffff,0x246e57},{"..3333..",".333333.",".344443.","11111111","12222221","12233221","12233221","12222221","12222221","12222221",".111111.","..1111.."}},
  terminal={{0x172331,0x31445b,0x5ee0a4,0xeaf4ff},{".111111.","11111111","12222221","12322221","12232221","12223321","12224421","12222221","12222221","12222221","11111111",".111111."}},
  settings={{0x60738a,0xaac1d4,0x45a8e8,0xf1f6fa},{"...11...",".1.11.1.","11211211",".123321.","11244211","12344321","12344321","11244211",".123321.","11211211",".1.11.1.","...11..."}},
  calculator={{0x3979bd,0xd9efff,0x64d49b,0x173957},{".111111.","12222221","12444421","12222221","11111111","13313331","13313331","11111111","13313331","13313331","11111111",".111111."}},
  systeminfo={{0x665bc5,0xbab4ff,0xffffff,0x363078},{"..1111..",".122221.","12222221","12233221","12233221","12222221",".123321.","...33...","...33...","..3333..",".133331.","11111111"}},
  taskmanager={{0x26394d,0x50cbea,0xf16f7c,0xeaf6ff},{"11111111","12222221","12222221","12223221","12423221","12423221","12423221","12423221","12423241","12222221","12222221","11111111"}},
  notes={{0xf1f4f7,0x568bd3,0xf2bd4d,0x8ba3ba},{".111111.","12212221","12212221","11111111","14444441","13333331","14444441","13333331","14444441","13333331","14444441",".111111."}},
  timer={{0x7962be,0xc8baff,0xffffff,0x493b83},{"...11...","..1331..","...11...",".111111.","12222221","12233221","12333221","12343221","12222221","12222221",".111111.","..1111.."}},
  todo={{0x31a46d,0xe9fff5,0x3579bd,0x174d39},{".111111.","12222221","12422221","14322221","12422221","12222221","12422221","14332221","12422221","12222421",".111431.","..1111.."}},
  diskusage={{0x347da5,0x72c8df,0xf3ca55,0xffffff},{"...11...","..1221..",".122221.","12222221","12222221","12222221","12222221","13332221","13333441","13334441",".111111.","..1111.."}},
  calendar={{0xd75961,0xffffff,0x5794d0,0x26384a},{"..1..1..",".141141.","11111111","12222221","13323321","12332321","13323321","12332321","13323321","12222221",".111111.","........"}},
  components={{0x496b84,0x76d6c1,0xf1c552,0xeaf7ff},{"...11...",".1.11.1.","11211211","..1221..","11122111","12233221","12244221","11122111","..1221..","11211211",".1.11.1.","...11..."}},
  inferno={{0x2a1718,0xd45a37,0xf4a43c,0xffe2a3},{".111111.","11222211","12233221","12333321","12344321","12244221","12222221","12211221","12211221","11222211",".122221.","..1111.."}},
  chicken3d={{0x65a44e,0xffffff,0xf0c44a,0xd84b43},{"........","..2222..",".222222.",".2222233","..222333","...2444.","...233..","..2.2...","..3.3...",".33.33..","11111111","11111111"}},
  snake={{0x163d33,0x55d98b,0xf3ce53,0xb6f4c9},{"11111111","12222221","12444221","11111221","13311221","13312221","11112221","12222221","12211111","12222221","11111111","........"}},
  pong={{0x162a4b,0x65c8ff,0xffffff,0xff6fae},{"11111111","12111141","12111141","12133141","12133141","12111141","12111141","12111141","12133141","12133141","12111141","11111111"}},
  minesweeper={{0x34495e,0x9aabc0,0xe95662,0xf2c94c},{"11111111","12212221","12121221","12212121","12122211","11231221","12133321","12234321","12333321","12232221","12222221","11111111"}},
  breakout={{0x17284a,0x55c8ff,0xff6f91,0xf4cf58},{"11111111","13344331","13344331","14433441","14433441","11111111","11122111","11122111","11111111","12222221","12222221","11111111"}},
  spamtontrash={{0x141414,0xf2f2f2,0xff4db8,0xffdf42,0xd93443},{"11111111","11222211","12222221","12322421","12211221","11255211","11522511","15225251","15555551","11211211","12211221","11111111"}},
  sketch={{0x6b5fc7,0xffca5c,0x53c6a2},{".......1","......11",".....121","....1221","...1221.","..1221..",".1221...","1221....","221.....","11......","1.......","........"}},
  game={{0x394a62,0x68d391,0xf36f76},{".111111.","11111111","12211221","12222221","12322321","12333321","12222221","12233221","12211221","11111111",".111111.","........"}}
}
local iconColors={0x4f8fe8,0x40b887,0xa06ee1,0xe0874c,0xd95f70,0x3fa7b5}
local iconCache,iconCacheSize={},0

local function fallbackArt(name,color)
  local hash=0 for i=1,#name do hash=(hash*33+name:byte(i))%65521 end
  local rows={}
  for y=1,12 do
    local row={}
    for x=1,8 do
      local edge=x==1 or x==8 or y==1 or y==12
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
  local image={width=small and 5 or 8,height=small and 3 or 6,cells={},logical=true}
  local xs=small and {1,3,4,6,8} or {1,2,3,4,5,6,7,8}
  for y=1,image.height do
    local sy=small and (y-1)*4+1 or (y-1)*2+1
    for x=1,image.width do
      local sx=xs[x]
      local upper=tonumber(art[2][sy]:sub(sx,sx))
      local lower=tonumber(art[2][sy+(small and 2 or 1)]:sub(sx,sx))
      if upper or lower then image.cells[(y-1)*image.width+x]={upper=upper and palette[upper],lower=lower and palette[lower]} end
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
        if image.logical then gpu.semi(x+px-1,y+py-1,cell.upper,cell.lower)
        else gpu.cell(x+px-1,y+py-1,cell.char or " ",cell.fg,cell.bg) end
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
