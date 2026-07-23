local ui = {}
local unicode = require("unicode")

-- builds frames in memory and only sends changed runs to the real gpu.
function ui.renderer(gpu, width, height)
  local r = {width=width, height=height, fg=0xffffff, bg=0x000000}
  local chars, foregrounds, backgrounds, marks = {}, {}, {}, {}
  local oldChars, oldForegrounds, oldBackgrounds = {}, {}, {}
  local frame = 0
  local gpuFg, gpuBg

  for y=1,height do
    chars[y],foregrounds[y],backgrounds[y],marks[y]={},{},{},{}
    oldChars[y],oldForegrounds[y],oldBackgrounds[y]={},{},{}
  end

  function r.beginFrame()
    frame=frame+1
  end

  function r.setForeground(color)
    r.fg=color
  end

  function r.setBackground(color)
    r.bg=color
  end

  function r.fill(x,y,w,h,char)
    char=unicode.sub(tostring(char or " "),1,1)
    local x1,x2=math.max(1,x),math.min(width,x+w-1)
    local y1,y2=math.max(1,y),math.min(height,y+h-1)
    for py=y1,y2 do
      for px=x1,x2 do
        chars[py][px],foregrounds[py][px],backgrounds[py][px]=char,r.fg,r.bg
        marks[py][px]=frame
      end
    end
  end

  function r.set(x,y,value)
    if y<1 or y>height then return end
    value=tostring(value)
    for i=1,unicode.len(value) do
      local px=x+i-1
      if px>=1 and px<=width then
        chars[y][px],foregrounds[y][px],backgrounds[y][px]=unicode.sub(value,i,i),r.fg,r.bg
        marks[y][px]=frame
      end
    end
  end

  function r.flush()
    for y=1,height do
      local x=1
      while x<=width do
        local drawn=marks[y][x]==frame
        local ch=drawn and chars[y][x] or " "
        local fg=drawn and foregrounds[y][x] or r.fg
        local bg=drawn and backgrounds[y][x] or r.bg
        if oldChars[y][x]==ch and oldForegrounds[y][x]==fg and oldBackgrounds[y][x]==bg then
          x=x+1
        else
          local start=x
          local text={ch}
          x=x+1
          while x<=width do
            drawn=marks[y][x]==frame
            ch=drawn and chars[y][x] or " "
            local nextFg=drawn and foregrounds[y][x] or r.fg
            local nextBg=drawn and backgrounds[y][x] or r.bg
            if nextFg~=fg or nextBg~=bg or (oldChars[y][x]==ch and oldForegrounds[y][x]==nextFg and oldBackgrounds[y][x]==nextBg) then break end
            text[#text+1]=ch
            x=x+1
          end
          if gpuBg~=bg then gpu.setBackground(bg) gpuBg=bg end
          if gpuFg~=fg then gpu.setForeground(fg) gpuFg=fg end
          gpu.set(start,y,table.concat(text))
        end
      end
      for px=1,width do
        local drawn=marks[y][px]==frame
        oldChars[y][px]=drawn and chars[y][px] or " "
        oldForegrounds[y][px]=drawn and foregrounds[y][px] or r.fg
        oldBackgrounds[y][px]=drawn and backgrounds[y][px] or r.bg
      end
    end
  end

  function r.invalidate()
    for y=1,height do
      oldChars[y],oldForegrounds[y],oldBackgrounds[y]={},{},{}
    end
    gpuFg,gpuBg=nil,nil
  end

  return r
end

function ui.clip(value, low, high)
  return math.max(low, math.min(high, value))
end

function ui.fill(gpu, x, y, w, h, bg, char)
  if w < 1 or h < 1 then return end
  gpu.setBackground(bg)
  gpu.fill(x, y, w, h, char or " ")
end

function ui.text(gpu, x, y, text, fg, bg)
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
  gpu.set(x, y, tostring(text))
end

function ui.center(gpu, x, y, w, text, fg, bg)
  text = tostring(text)
  ui.text(gpu, x + math.max(0, math.floor((w - unicode.len(text)) / 2)), y, text, fg, bg)
end

function ui.button(gpu, x, y, w, label, active, activeBg, inactiveBg)
  if w < 1 then return end
  local bg = active and (activeBg or 0x3b82f6) or (inactiveBg or 0x30343b)
  ui.fill(gpu, x, y, w, 1, bg)
  ui.center(gpu, x, y, w, unicode.sub(tostring(label),1,w), 0xffffff, bg)
end

function ui.inside(px, py, x, y, w, h)
  return px >= x and py >= y and px < x + w and py < y + h
end

return ui
