local ui = {}
local unicode = require("unicode")

-- a compact cell compositor. planes are flat to avoid thousands of row tables.
function ui.renderer(gpu, width, height)
  local r = {width=width, height=height, fg=0xffffff, bg=0x000000}
  local chars, foregrounds, backgrounds, marks = {}, {}, {}, {}
  local oldChars, oldForegrounds, oldBackgrounds = {}, {}, {}
  local frame, gpuFg, gpuBg = 0, nil, nil
  local clips = {{x1=1,y1=1,x2=width,y2=height}}
  local depthOk, depth = pcall(gpu.getDepth)
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
          if gpuBg~=bg then gpu.setBackground(bg) gpuBg=bg end
          if gpuFg~=fg then gpu.setForeground(fg) gpuFg=fg end
          gpu.set(start,y,table.concat(text))
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

local iconPatterns={
  files={"11110","10001","11111"}, store={"01110","11111","10101"},
  terminal={"10000","01000","00111"}, settings={"10101","01110","10101"},
  calculator={"11111","10101","11111"}, notes={"11110","10100","11110"},
  todo={"10010","10100","01000"}, timer={"01110","10101","01110"},
  systeminfo={"00100","11111","01110"}, taskmanager={"10101","11111","01010"},
  diskusage={"01110","11111","01110"}
}
local iconColors={0x4f8fe8,0x40b887,0xa06ee1,0xe0874c,0xd95f70,0x3fa7b5}

-- images are tiny row-major tables; absent cells are transparent.
function ui.icon(name,color)
  name=tostring(name or "app")
  local hash=0 for i=1,#name do hash=(hash+name:byte(i)*i)%997 end
  local pattern=iconPatterns[name] or {"01110","1"..((hash%2==0) and "010" or "101").."1","01110"}
  color=tonumber(color) or iconColors[(hash%#iconColors)+1]
  local image={width=5,height=3,cells={}}
  for y,row in ipairs(pattern) do
    for x=1,5 do
      if row:sub(x,x)=="1" then image.cells[(y-1)*5+x]={char=" ",bg=color,fg=0xffffff} end
    end
  end
  return image
end

function ui.image(gpu,x,y,image)
  if type(image)~="table" or type(image.cells)~="table" then return end
  for py=1,(image.height or 0) do
    for px=1,(image.width or 0) do
      local cell=image.cells[(py-1)*image.width+px]
      if cell then gpu.cell(x+px-1,y+py-1,cell.char or " ",cell.fg,cell.bg) end
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
