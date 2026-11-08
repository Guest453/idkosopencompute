return function(app)
  local win = app.window{title="settings", width=54, height=17}
  local themePath = "/home/.idkos/theme.cfg"
  local displayPath = "/home/.idkos/display.cfg"
  local appearance = "light"
  local status = "ready"
  local editing = nil
  local currentW, currentH = app.screen()
  local widthText, heightText = tostring(currentW), tostring(currentH)

  local maxOk, maxW, maxH = pcall(app.component.gpu.maxResolution)
  if not maxOk then maxW, maxH = 80, 25 end

  local function loadAppearance()
    local file = io.open(themePath, "r")
    if file then
      appearance = tostring(file:read("*l") or "light"):lower() == "dark" and "dark" or "light"
      file:close()
    end
  end

  local function saveAppearance(value)
    value = value == "dark" and "dark" or "light"
    app.fs.makeDirectory("/home/.idkos")
    local file, reason = io.open(themePath, "w")
    if not file then status = "theme save failed: " .. tostring(reason) return end
    file:write(value .. "\n")
    file:close()
    appearance = value
    status = value .. " theme applied"
    app.notify(status)
  end

  local function rememberDisplay(width, height)
    local ok, reason = app.fs.makeDirectory("/home/.idkos")
    if not ok and not app.fs.exists("/home/.idkos") then
      return nil, "cannot create settings directory: " .. tostring(reason)
    end
    local file, openReason = io.open(displayPath, "w")
    if not file then return nil, openReason end
    local written, writeReason = file:write(string.format("%dx%d\n", width, height))
    file:close()
    if not written then return nil, writeReason end
    return true
  end

  local function applyDisplay(mode)
    local ok, reason = app.display(mode)
    if not ok then
      status = "display unchanged: " .. tostring(reason)
      app.notify(status)
      return
    end
    currentW, currentH = app.screen()
    widthText, heightText = tostring(currentW), tostring(currentH)
    editing = nil
    local saved, saveReason = rememberDisplay(currentW, currentH)
    status = saved and string.format("display: %dx%d (saved)", currentW, currentH)
      or ("display applied, save failed: " .. tostring(saveReason))
    app.notify(status)
  end

  local function applyCustom()
    local width, height = tonumber(widthText), tonumber(heightText)
    if not width or not height or width % 1 ~= 0 or height % 1 ~= 0 then
      status = "enter whole numbers for width and height"
      return
    end
    applyDisplay({width=width, height=height})
  end

  local function edit(field)
    if editing ~= field then
      editing = field
      if field == "width" then widthText = "" else heightText = "" end
      status = "type numbers, then enter (or click apply)"
    end
  end

  loadAppearance()
  while true do
    local w, h = win.width, win.height
    win:reset()
    win:fill(1, 1, w, h-1, 0xf4f7fa)

    win:text(2, 2, "appearance", 0x21384a, 0xf4f7fa)
    win:button("light", 2, 3, 12, "light", appearance == "light")
    win:button("dark", 15, 3, 12, "dark", appearance == "dark")

    local actualW, actualH = app.screen()
    win:text(2, 5, string.format("display: %dx%d cells", actualW, actualH), 0x21384a, 0xf4f7fa)
    win:button("compact", 2, 6, 12, "60x20")
    win:button("openos", 15, 6, 17, "openos 80x25")

    win:text(2, 8, "custom width x height (cells)", 0x617487, 0xf4f7fa)
    win:button("editwidth", 2, 9, 12, "w:" .. (editing=="width" and widthText.."_" or widthText), editing=="width")
    win:button("editheight", 15, 9, 12, "h:" .. (editing=="height" and heightText.."_" or heightText), editing=="height")
    win:button("apply", 28, 9, 10, "apply")

    if h >= 13 then
      win:text(2, 10, string.format("gpu maximum: %dx%d", maxW, maxH), 0x617487, 0xf4f7fa)
    end
    if h >= 14 then
      win:text(2, 11, "select w/h, type digits, enter to continue", 0x617487, 0xf4f7fa)
    end
    win:text(2, h-2, tostring(status):sub(1, math.max(1,w-4)), 0x397fca, 0xf4f7fa)

    local name, _, id, code = app.pull()
    if name == "idk_button" then
      if id == "light" or id == "dark" then
        saveAppearance(id)
      elseif id == "compact" or id == "openos" then
        applyDisplay(id)
      elseif id == "editwidth" then
        edit("width")
      elseif id == "editheight" then
        edit("height")
      elseif id == "apply" then
        applyCustom()
      end
    elseif name == "key_down" and editing then
      if code == 14 or id == 8 then
        if editing == "width" then widthText = widthText:sub(1,-2)
        else heightText = heightText:sub(1,-2) end
      elseif code == 28 or id == 13 then
        if editing == "width" then
          editing = "height"
          heightText = ""
        else
          applyCustom()
        end
      elseif code == 1 then
        widthText, heightText = tostring(actualW), tostring(actualH)
        editing = nil
      elseif type(id) == "number" and id >= 48 and id <= 57 then
        local digit = string.char(id)
        if editing == "width" and #widthText < 4 then widthText = widthText .. digit
        elseif editing == "height" and #heightText < 4 then heightText = heightText .. digit end
      end
    elseif name == "clipboard" and editing and type(id) == "string" then
      local value = id:match("^%s*(%d+)%s*$")
      if value and #value <= 4 then
        if editing == "width" then widthText = value else heightText = value end
      end
    end
  end
end
