return function(app)
  local unicode = require("unicode")
  local component = app.component
  local win = app.window{title="music", width=72, height=23}

  local tracks = {
    {
      name="night drive", bpm=112,
      events={
        {{60,67},1}, {{64,71},1}, {{67,72},1}, {{64,71},1},
        {{57,64},1}, {{60,67},1}, {{64,69},1}, {{60,67},1},
        {{55,62},1}, {{59,67},1}, {{62,71},1}, {{59,67},1},
        {{53,60},1}, {{57,64},1}, {{60,69},1}, {{57,64},1}
      }
    },
    {
      name="blue terminal", bpm=128,
      events={
        {{72},0.5}, {{76},0.5}, {{79},0.5}, {{84},0.5},
        {{79},0.5}, {{76},0.5}, {{74},0.5}, {{71},0.5},
        {{72,60},1}, {{76,64},1}, {{79,67},1}, {{76,64},1},
        {{69,57},1}, {{72,60},1}, {{76,64},1}, {{72,60},1}
      }
    },
    {
      name="quiet boot", bpm=86,
      events={
        {{60},1}, {{64},1}, {{67},2},
        {{59},1}, {{62},1}, {{67},2},
        {{57},1}, {{60},1}, {{64},1}, {{69},1},
        {{55},1}, {{59},1}, {{62},2}
      }
    }
  }

  local waves = {
    {name="square", value=1},
    {name="sine", value=2},
    {name="triangle", value=3},
    {name="saw", value=4}
  }

  local selectedTrack = 1
  local waveIndex = 2
  local volume = 0.65
  local playing = false
  local eventIndex = 1
  local nextAt = 0
  local status = "looking for computronics sound card"
  local soundAddress, soundProxy, channelCount

  local function short(value, limit)
    return unicode.sub(tostring(value or ""), 1, math.max(0, limit or 1))
  end

  local function firstAddress(kind)
    for _, exact in ipairs({false, true}) do
      local ok, listed
      if not exact then ok, listed = pcall(component.list, kind)
      else ok, listed = pcall(component.list, kind, true) end
      if ok then
        if type(listed) == "function" then
          local nextOk, address = pcall(listed)
          if nextOk and address then return address end
        elseif type(listed) == "string" then
          return listed
        elseif type(listed) == "table" then
          for key, value in pairs(listed) do
            if type(key) == "string" and (value == kind or value == true) then return key end
            if type(value) == "string" then return value end
            if type(value) == "table" or type(value) == "userdata" then
              local address
              pcall(function() address = value.address end)
              if address then return address, value end
            end
          end
        end
      end
    end

    local ok, direct = pcall(function() return component[kind] end)
    if ok and direct then
      local address
      pcall(function() address = direct.address end)
      return address, direct
    end
  end

  local function detectSound()
    soundAddress, soundProxy = firstAddress("sound")
    if not soundProxy and soundAddress and type(component.proxy) == "function" then
      local ok, proxy = pcall(component.proxy, soundAddress)
      if ok then soundProxy = proxy end
    end
    if not soundAddress and not soundProxy then
      status = "computronics sound card not found"
      return false
    end
    status = "computronics sound card ready"
    return true
  end

  local function invoke(method, ...)
    if soundAddress and type(component.invoke) == "function" then
      local result = {pcall(component.invoke, soundAddress, method, ...)}
      if result[1] then return table.unpack(result, 2) end
    end
    if soundProxy then
      local fn
      pcall(function() fn = soundProxy[method] end)
      if type(fn) == "function" then
        local result = {pcall(fn, ...)}
        if result[1] then return table.unpack(result, 2) end
      end
    end
    return nil, "sound method unavailable: " .. tostring(method)
  end

  local function noteFrequency(note)
    return 440 * (2 ^ ((note - 69) / 12))
  end

  local function stopSound(message)
    playing = false
    nextAt = 0
    pcall(invoke, "clear")
    pcall(invoke, "setTotalVolume", 0)
    if message then status = message end
  end

  local function prepareSound()
    if not soundAddress and not soundProxy and not detectSound() then return false end
    local count = invoke("channel_count")
    channelCount = math.max(1, math.floor(tonumber(count) or 4))
    invoke("setTotalVolume", volume)
    return true
  end

  local function queueEvent(event, track)
    if not prepareSound() then return nil end
    local notes = event[1] or {}
    local beats = tonumber(event[2]) or 1
    local duration = math.max(40, math.floor((60000 / track.bpm) * beats))
    invoke("clear")
    local used = math.min(#notes, channelCount or 1)
    for channel = 1, used do
      invoke("open", channel)
      invoke("setWave", channel, waves[waveIndex].value)
      invoke("setFrequency", channel, noteFrequency(notes[channel]))
      invoke("setVolume", channel, math.min(1, volume * (channel == 1 and 0.88 or 0.58)))
    end
    invoke("delay", math.max(20, duration - 16))
    for channel = 1, used do invoke("close", channel) end
    local started, reason = invoke("process")
    if started == false then
      status = "sound card busy: " .. short(reason, 42)
      return 120
    end
    return duration
  end

  local function beginTrack()
    if not prepareSound() then return end
    local track = tracks[selectedTrack]
    playing = true
    eventIndex = 1
    nextAt = 0
    status = "playing " .. track.name
  end

  local function previewNote(note)
    if not prepareSound() then return end
    invoke("clear")
    invoke("open", 1)
    invoke("setWave", 1, waves[waveIndex].value)
    invoke("setFrequency", 1, noteFrequency(note))
    invoke("setVolume", 1, volume * 0.85)
    invoke("delay", 180)
    invoke("close", 1)
    invoke("process")
    status = "preview note"
  end

  local function draw()
    local width, height = win.width, win.height
    local track = tracks[selectedTrack]
    win:reset()
    win:fill(1, 1, width, height - 1, 0xf5f8fa)
    win:fill(1, 1, width, 3, 0x17283d)
    win:text(3, 1, "music", 0xffffff, 0x17283d)
    win:text(3, 2, short(status, width - 6), 0x9fc7da, 0x17283d)

    win:fill(3, 5, 20, 13, 0xe8eef3)
    win:text(5, 5, "library", 0x5f7485, 0xe8eef3)
    for index, item in ipairs(tracks) do
      local y = 7 + (index - 1) * 3
      local active = index == selectedTrack
      local bg = active and 0xb9ddf5 or 0xe8eef3
      win:fill(4, y, 18, 2, bg)
      win:text(5, y, short(item.name, 16), active and 0x173247 or 0x294052, bg)
      win:text(5, y + 1, tostring(item.bpm) .. " bpm", 0x617487, bg)
      if type(win.hit) == "function" then win:hit("track:" .. index, 4, y, 18, 2)
      else win:button("track:" .. index, 4, y, 18, item.name) end
    end

    local panelX = 25
    local panelW = width - panelX - 2
    win:fill(panelX, 5, panelW, 13, 0xffffff)
    win:text(panelX + 2, 5, short(track.name, panelW - 4), 0x1d2b3a, 0xffffff)
    win:text(panelX + 2, 6, tostring(track.bpm) .. " bpm  " .. waves[waveIndex].name, 0x617487, 0xffffff)

    local progress = 0
    if playing then progress = math.max(0, math.min(1, (eventIndex - 1) / math.max(1, #track.events))) end
    win:fill(panelX + 2, 8, math.max(1, panelW - 4), 1, 0xd8e2e9)
    if progress > 0 then win:fill(panelX + 2, 8, math.max(1, math.floor((panelW - 4) * progress)), 1, 0x4ec7e8) end

    win:button("play", panelX + 2, 10, 10, playing and "restart" or "play")
    win:button("stop", panelX + 13, 10, 9, "stop")
    win:button("rescan", panelX + 23, 10, 10, "rescan")

    win:text(panelX + 2, 12, "wave", 0x617487, 0xffffff)
    local x = panelX + 2
    for index, wave in ipairs(waves) do
      local buttonWidth = index == 3 and 10 or 8
      win:button("wave:" .. index, x, 13, buttonWidth, wave.name, index == waveIndex)
      x = x + buttonWidth + 1
    end

    win:text(panelX + 2, 15, "volume " .. tostring(math.floor(volume * 100)) .. "%", 0x617487, 0xffffff)
    win:button("quieter", panelX + 15, 15, 9, "quieter")
    win:button("louder", panelX + 25, 15, 8, "louder")

    win:text(panelX + 2, 17, "keys", 0x617487, 0xffffff)
    local notes = {60, 62, 64, 65, 67, 69, 71, 72}
    local labels = {"c", "d", "e", "f", "g", "a", "b", "c2"}
    for index, note in ipairs(notes) do
      win:button("note:" .. note, panelX + 8 + (index - 1) * 5, 17, 4, labels[index])
    end

    win:fill(1, height - 1, width, 2, 0xe7edf2)
    win:text(3, height - 1, soundAddress or "no sound address", 0x617487, 0xe7edf2)
  end

  detectSound()

  while true do
    local now = app.computer.uptime()
    if playing and now >= nextAt then
      local track = tracks[selectedTrack]
      if eventIndex > #track.events then
        stopSound("finished " .. track.name)
      else
        local duration = queueEvent(track.events[eventIndex], track)
        if duration then
          eventIndex = eventIndex + 1
          nextAt = now + duration / 1000
        else
          stopSound("playback stopped")
        end
      end
    end

    draw()
    local timeout
    if playing then timeout = math.max(0, math.min(0.12, nextAt - app.computer.uptime())) end
    local name, address, id, code, player = app.pull(timeout)
    if name == "idk_button" then
      local track = tonumber(tostring(id):match("^track:(%d+)$"))
      local wave = tonumber(tostring(id):match("^wave:(%d+)$"))
      local note = tonumber(tostring(id):match("^note:(%d+)$"))
      if track and tracks[track] then
        stopSound()
        selectedTrack = track
        status = "selected " .. tracks[track].name
      elseif wave and waves[wave] then
        waveIndex = wave
        status = "wave: " .. waves[wave].name
      elseif note then
        stopSound()
        previewNote(note)
      elseif id == "play" then
        stopSound()
        beginTrack()
      elseif id == "stop" then
        stopSound("stopped")
      elseif id == "rescan" then
        stopSound()
        soundAddress, soundProxy = nil, nil
        detectSound()
      elseif id == "quieter" then
        volume = math.max(0.1, volume - 0.1)
        invoke("setTotalVolume", playing and volume or 0)
      elseif id == "louder" then
        volume = math.min(1, volume + 0.1)
        invoke("setTotalVolume", playing and volume or 0)
      end
    end
  end
end
