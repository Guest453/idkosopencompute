local ui = dofile("/idkos/system/ui.lua")
local unicode = require("unicode")

local sourceIcon = ui.icon
local sourceButton = ui.button
local cache = {}

local custom = {
  finder = {{0x4d9de0,0xffffff,0x9ed7ff,0x173957},{".111.","12221","12321","12221",".111."},{{3,3,"~",2}}},
  launchpad = {{0x65758b,0xeef5fb,0x397fca},{"11111","12221","12321","12221","11111"},{{2,2,"o",2},{4,2,"o",2},{2,4,"o",2},{4,4,"o",2}}},
  recoveryupdater = {{0x397fca,0xffffff,0x55d98b,0x173957},{".111.","12221","12321","12221",".111."},{{3,2,"^",2},{3,3,"|",2},{3,4,"v",3}}},
  blockmerge = {{0x394a62,0xf4c95d,0x68d391,0xffffff},{"11111","12231","12321","13221","11111"},{{2,2,"2",4},{4,2,"4",4},{2,4,"8",4},{4,4,"+",4}}},
  lightsout = {{0x17284a,0xffd84d,0x617487,0xffffff},{"11111","12121","11211","12121","11111"},{{3,3,"*",4}}},
  store = {{0x31a46d,0xffffff,0x8ce2bd,0x174d39},{".222.","21112","11111","13331",".111."},{{3,3,"+",2}}},
  terminal = {{0x172331,0x5ee0a4,0xeaf4ff},{"11111","12221","12221","12221","11111"},{{2,3,">",2},{4,3,"_",3}}},
  settings = {{0x60738a,0xaac1d4,0x45a8e8,0xffffff},{"1.1.1","11211","12321","11211","1.1.1"},{{3,3,"o",4}}},
  game = {{0x394a62,0x68d391,0xf36f76,0xffffff},{".111.","12221","12321","12421",".111."},{{2,3,"+",4},{4,3,"o",4}}},
}

local function makeImage(def, small, color)
  local palette = {table.unpack(def[1])}
  if type(color)=="number" and color>=0 and color<=0xffffff then palette[1]=color end
  local rows, glyphs = def[2], def[3] or {}
  local width,height = small and 3 or 5, small and 3 or 5
  local xs = small and {1,3,5} or {1,2,3,4,5}
  local ys = small and {1,3,5} or {1,2,3,4,5}
  local image={width=width,height=height,cells={}}
  for y=1,height do
    for x=1,width do
      local key=rows[ys[y]]:sub(xs[x],xs[x])
      local p=tonumber(key)
      if p and palette[p] then image.cells[(y-1)*width+x]={char=" ",fg=palette[p],bg=palette[p]} end
    end
  end
  if small then
    local glyph = glyphs[1]
    if glyph then
      local cell=image.cells[5] or {bg=palette[1]}
      image.cells[5]={char=unicode.sub(tostring(glyph[3]),1,1),fg=palette[glyph[4]] or 0xffffff,bg=cell.bg or palette[1]}
    end
  else
    for _,g in ipairs(glyphs) do
      local x,y=g[1],g[2]
      if x>=1 and x<=5 and y>=1 and y<=5 then
        local i=(y-1)*5+x
        local cell=image.cells[i] or {bg=palette[1]}
        image.cells[i]={char=unicode.sub(tostring(g[3]),1,1),fg=palette[g[4]] or 0xffffff,bg=cell.bg or palette[1]}
      end
    end
  end
  return image
end

local function crop(image, small)
  if type(image)~="table" or type(image.cells)~="table" then return image end
  local xs,ys
  if small then
    xs={1,math.max(1,math.ceil((image.width or 1)/2)),image.width or 1}
    ys={1,math.max(1,math.ceil((image.height or 1)/2)),image.height or 1}
  else
    xs={1,2,math.max(1,math.ceil((image.width or 1)/2)),math.max(1,(image.width or 1)-1),image.width or 1}
    ys={1,2,math.max(1,math.ceil((image.height or 1)/2)),math.max(1,(image.height or 1)-1),image.height or 1}
  end
  local out={width=#xs,height=#ys,cells={}}
  for y,sy in ipairs(ys) do
    for x,sx in ipairs(xs) do
      out.cells[(y-1)*out.width+x]=image.cells[(sy-1)*(image.width or 1)+sx]
    end
  end
  return out
end

function ui.icon(name,color,size)
  name=tostring(name or "app"):lower()
  if name=="files" then name="finder" end
  local small=size=="small" or size=="dock" or tonumber(size)==3
  local key=name..":"..tostring(color or "")..":"..(small and "s" or "f")
  if cache[key] then return cache[key] end
  local image
  if custom[name] then image=makeImage(custom[name],small,color)
  else image=crop(sourceIcon(name,color,small and "small" or nil),small) end
  cache[key]=image
  return image
end

function ui.button(gpu,x,y,w,label,active,activeBg,inactiveBg)
  if w<1 then return end
  label=unicode.sub(tostring(label or ""),1,math.max(0,w-2))
  local bg=active and (activeBg or 0x397fca) or (inactiveBg or 0xdbe6ef)
  local fg=active and 0xffffff or 0x1d2b3a
  ui.fill(gpu,x,y,w,1,bg," ")
  if w>=2 then
    ui.text(gpu,x,y,"‹",active and 0xcfe9ff or 0x71869a,bg)
    ui.text(gpu,x+w-1,y,"›",active and 0xcfe9ff or 0x71869a,bg)
  end
  ui.center(gpu,x,y,w,label,fg,bg)
end

return ui
