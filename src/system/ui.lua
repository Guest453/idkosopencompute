local ui = {}

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
  ui.text(gpu, x + math.max(0, math.floor((w - #text) / 2)), y, text, fg, bg)
end

function ui.button(gpu, x, y, w, label, active)
  local bg = active and 0x3b82f6 or 0x30343b
  ui.fill(gpu, x, y, w, 1, bg)
  ui.center(gpu, x, y, w, label, 0xffffff, bg)
end

function ui.inside(px, py, x, y, w, h)
  return px >= x and py >= y and px < x + w and py < y + h
end

return ui
