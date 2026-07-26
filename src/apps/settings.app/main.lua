return function(app)
  local win = app.window{title="settings", width=52, height=17}
  local configPath = "/home/.idkos/theme.cfg"
  local appearance = "light"
  local status = "ready"

  local function loadAppearance()
    local file = io.open(configPath, "r")
    if file then
      appearance = tostring(file:read("*l") or "light"):lower() == "dark" and "dark" or "light"
      file:close()
    end
  end

  local function saveAppearance(value)
    value = value == "dark" and "dark" or "light"
    app.fs.makeDirectory("/home/.idkos")
    local file, reason = io.open(configPath, "w")
    if not file then status = "theme save failed: " .. tostring(reason) return end
    file:write(value .. "\n")
    file:close()
    appearance = value
    status = value .. " theme applied to shell and apps"
    app.notify(status)
  end

  loadAppearance()

  while true do
    win:reset()
    win:fill(1, 1, win.width, win.height - 1, 0xf4f7fa)
    win:text(2, 2, "appearance", 0x21384a, 0xf4f7fa)
    win:text(2, 4, "system theme", 0x617487, 0xf4f7fa)
    win:button("light", 2, 5, 14, "light", appearance == "light")
    win:button("dark", 18, 5, 14, "dark", appearance == "dark")
    win:text(2, 7, "the theme remaps every app, including older apps", 0x617487, 0xf4f7fa)

    win:text(2, 10, "display size", 0x617487, 0xf4f7fa)
    win:button("compact", 2, 11, 14, "compact")
    win:button("balanced", 18, 11, 14, "balanced")
    win:button("native", 34, 11, 14, "native/max")

    win:text(2, 14, status, 0x397fca, 0xf4f7fa)
    win:text(2, 16, "idk os settings", 0x617487, 0xf4f7fa)

    local name, _, id = app.pull()
    if name == "idk_button" then
      if id == "light" or id == "dark" then
        saveAppearance(id)
      elseif id == "compact" or id == "balanced" or id == "native" then
        local ok, reason = app.display(id)
        if not ok then status = tostring(reason) app.notify(reason) else status = "display mode: " .. id end
      end
    end
  end
end
