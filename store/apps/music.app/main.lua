return function(app)
  local unicode = require("unicode")
  local keyboard = require("keyboard")
  local component = app.component
  local win = app.window{title="music", width=96, height=31}

  local tracks = {
    {
      name="night drive", bpm=112, instrument=2,
      events={
        {{60,67},1}, {{64,71},1}, {{67,72},1}, {{64,71},1},
        {{57,64},1}, {{60,67},1}, {{64,69},1}, {{60,67},1},
        {{55,62},1}, {{59,67},1}, {{62,71},1}, {{59,67},1},
        {{53,60},1}, {{57,64},1}, {{60,69},1}, {{57,64},1}
      }
    },
    {
      name="blue terminal", bpm=128, instrument=3,
      events={
        {{72},0.5}, {{76},0.5}, {{79},0.5}, {{84},0.5},
        {{79},0.5}, {{76},0.5}, {{74},0.5}, {{71},0.5},
        {{72,60},1}, {{76,64},1}, {{79,67},1}, {{76,64},1},
        {{69,57},1}, {{72,60},1}, {{76,64},1}, {{72,60},1}
      }
    },
    {
      name="quiet boot", bpm=86, instrument=1,
      events={
        {{60},1}, {{64},1}, {{67},2},
        {{59},1}, {{62},1}, {{67},2},
        {{57},1}, {{60},1}, {{64},1}, {{69},1},
        {{55},1}, {{59},1}, {{62},2}
      }
    }
  }

  local instruments = {
    {
      name="piano",
      oscillators={{wave=3, ratio=1.00, level=0.78}, {wave=2, ratio=2.00, level=0.18}},
      adsr={5, 190, 0.18, 280}
    },
    {
      name="electric",
      oscillators={{wave=2, ratio=1.00, level=0.72}, {wave=3, ratio=2.00, level=0.22}},
      adsr={8, 290, 0.30, 430}
    },
    {
      name="organ",
      oscillators={{wave=2, ratio=1.00, level=0.62}, {wave=1, ratio=2.00, level=0.16}},
      adsr={22, 70, 0.82, 140}
    },
    {
      name="bell",
      oscillators={{wave=2, ratio=1.00, level=0.70}, {wave=2, ratio=2.01, level=0.26}},
      adsr={1, 620, 0.05, 850}
    }
  }

  local mode = "library"
  local selectedTrack = 1
  local selectedInstrument = 1
  local volume = 0.70
  local playingMode = nil
  local playbackIndex = 1
  local nextAt = 0
  local status = "looking for computronics sound card"
  local soundAddress, soundProxy, channelCount

  local studioBpm = 120
  local studioStep = 1
  local studioOctave = 4
  local studioLoop = true
  local studioRecord = true
  local studioPath = "/home/Music/idk-studio.song"

  local function newPattern()
    local result = {}
    for step = 1, 16 do result[step] = {} end
    return result
  end

  local pattern = newPattern()

  local noteNames = {"c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b"}
  local keyboardNotes = {
    a=0, w=1, s=2, e=3, d=4, f=5, t=6,
    g=7, y=8, h=9, u=10, j=11, k=12
  }

  local function short(value, limit)
    return unicode.sub(tostring(value or ""), 1, math.max(0, limit or 1))
  end

  local function noteName(note)
    note = math.floor(tonumber(note) or 60)
    local octave = math.floor(note / 12) - 1
    return noteNames[(note % 12) + 1] .. tostring(octave)
  end

  local function noteFrequency(note)
    return 440 * (2 ^ ((note - 69) / 12))
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

  local function prepareSound()
    if not soundAddress and not soundProxy and not detectSound() then return false end
    local count = invoke("channel_count")
    channelCount = math.max(1, math.floor(tonumber(count) or 4))
    invoke("setTotalVolume", volume)
    return true
  end

  local function stopSound(message)
    playingMode = nil
    nextAt = 0
    pcall(invoke, "clear")
    pcall(invoke, "setTotalVolume", 0)
    if message then status = message end
  end

  local function sortedNotes(set)
    local notes = {}
    for note, enabled in pairs(set or {}) do
      if enabled then notes[#notes + 1] = tonumber(note) end
    end
    table.sort(notes)
    return notes
  end

  local function queueChord(notes, duration, instrumentIndex)
    duration = math.max(40, math.floor(tonumber(duration) or 250))
    if #notes == 0 then return duration end
    if not prepareSound() then return nil end

    local instrument = instruments[instrumentIndex] or instruments[1]
    invoke("clear")

    local layers = math.max(1, math.min(#instrument.oscillators, math.floor((channelCount or 1) / math.max(1, #notes))))
    local channel = 1
    local used = {}

    for _, note in ipairs(notes) do
      for layer = 1, layers do
        if channel > (channelCount or 1) then break end
        local oscillator = instrument.oscillators[layer]
        local adsr = instrument.adsr
        invoke("resetEnvelope", channel)
        invoke("setWave", channel, oscillator.wave)
        invoke("setFrequency", channel, noteFrequency(note) * oscillator.ratio)
        invoke("setVolume", channel, math.min(1, volume * oscillator.level))
        invoke("setADSR", channel, adsr[1], adsr[2], adsr[3], adsr[4])
        invoke("open", channel)
        used[#used + 1] = channel
        channel = channel + 1
      end
    end

    invoke("delay", math.max(20, duration - 12))
    for _, usedChannel in ipairs(used) do invoke("close", usedChannel) end
    local started, reason = invoke("process")
    if started == false then
      status = "sound card busy: " .. short(reason, 42)
      return 120
    end
    return duration
  end

  local function previewNote(note, record)
    stopSound()
    local duration = selectedInstrument == 4 and 620 or 360
    queueChord({note}, duration, selectedInstrument)
    status = "piano " .. noteName(note)
    if record and studioRecord then
      pattern[studioStep][note] = true
      studioStep = studioStep % 16 + 1
    end
  end

  local function beginLibrary()
    local track = tracks[selectedTrack]
    selectedInstrument = track.instrument or selectedInstrument
    playingMode = "library"
    playbackIndex = 1
    nextAt = 0
    status = "playing " .. track.name
  end

  local function beginStudio()
    playingMode = "studio"
    playbackIndex = studioStep
    nextAt = 0
    status = "playing studio pattern"
  end

  local function togglePattern(step, note)
    local set = pattern[step]
    set[note] = not set[note]
    studioStep = step
    status = (set[note] and "added " or "removed ") .. noteName(note) .. " at step " .. tostring(step)
  end

  local function clearPattern()
    pattern = newPattern()
    studioStep = 1
    status = "studio pattern cleared"
  end

  local function savePattern()
    app.fs.makeDirectory("/home/Music")
    local file, reason = io.open(studioPath, "w")
    if not file then status = "save failed: " .. tostring(reason) return end
    file:write("idk-music-maker-1\n")
    file:write("bpm=" .. tostring(studioBpm) .. "\n")
    file:write("instrument=" .. tostring(selectedInstrument) .. "\n")
    file:write("octave=" .. tostring(studioOctave) .. "\n")
    file:write("loop=" .. (studioLoop and "1" or "0") .. "\n")
    for step = 1, 16 do
      local values = {}
      for _, note in ipairs(sortedNotes(pattern[step])) do values[#values + 1] = tostring(note) end
      file:write("step" .. tostring(step) .. "=" .. table.concat(values, ",") .. "\n")
    end
    file:close()
    status = "saved " .. studioPath
  end

  local function loadPattern()
    local file, reason = io.open(studioPath, "r")
    if not file then status = "load failed: " .. tostring(reason) return end
    local first = file:read("*l")
    if first ~= "idk-music-maker-1" then file:close() status = "unsupported song file" return end
    local nextPattern = newPattern()
    for line in file:lines() do
      local key, value = line:match("^([%w]+)=(.*)$")
      if key == "bpm" then
        studioBpm = math.max(50, math.min(220, tonumber(value) or studioBpm))
      elseif key == "instrument" then
        selectedInstrument = math.max(1, math.min(#instruments, math.floor(tonumber(value) or selectedInstrument)))
      elseif key == "octave" then
        studioOctave = math.max(2, math.min(6, math.floor(tonumber(value) or studioOctave)))
      elseif key == "loop" then
        studioLoop = value == "1"
      else
        local step = tonumber(tostring(key):match("^step(%d+)$"))
        if step and step >= 1 and step <= 16 then
          for raw in tostring(value):gmatch("[^,]+") do
            local note = tonumber(raw)
            if note and note >= 24 and note <= 96 then nextPattern[step][math.floor(note)] = true end
          end
        end
      end
    end
    file:close()
    pattern = nextPattern
    studioStep = 1
    status = "loaded " .. studioPath
  end

  local function drawHeader(width)
    win:fill(1, 1, width, 3, 0x15263b)
    win:text(3, 1, "music", 0xffffff, 0x15263b)
    win:text(3, 2, short(status, width - 6), 0x9fc7da, 0x15263b)
    win:button("mode:library", 3, 3, 11, "library", mode == "library")
    win:button("mode:studio", 15, 3, 11, "studio", mode == "studio")
  end

  local function drawLibrary(width, height)
    local track = tracks[selectedTrack]
    local sidebarWidth = math.min(22, math.max(18, math.floor(width * 0.28)))
    win:fill(3, 5, sidebarWidth, height - 8, 0xe8eef3)
    win:text(5, 5, "library", 0x5f7485, 0xe8eef3)

    for index, item in ipairs(tracks) do
      local y = 7 + (index - 1) * 3
      local active = index == selectedTrack
      local background = active and 0xb9ddf5 or 0xe8eef3
      win:fill(4, y, sidebarWidth - 2, 2, background)
      win:text(5, y, short(item.name, sidebarWidth - 4), active and 0x173247 or 0x294052, background)
      win:text(5, y + 1, tostring(item.bpm) .. " bpm", 0x617487, background)
      win:hit("track:" .. index, 4, y, sidebarWidth - 2, 2)
    end

    local panelX = sidebarWidth + 5
    local panelWidth = width - panelX - 2
    win:fill(panelX, 5, panelWidth, height - 8, 0xffffff)
    win:text(panelX + 2, 5, short(track.name, panelWidth - 4), 0x1d2b3a, 0xffffff)
    win:text(panelX + 2, 6, tostring(track.bpm) .. " bpm", 0x617487, 0xffffff)

    local progress = 0
    if playingMode == "library" then progress = math.max(0, math.min(1, (playbackIndex - 1) / math.max(1, #track.events))) end
    win:fill(panelX + 2, 8, math.max(1, panelWidth - 4), 1, 0xd8e2e9)
    if progress > 0 then win:fill(panelX + 2, 8, math.max(1, math.floor((panelWidth - 4) * progress)), 1, 0x4ec7e8) end

    win:button("library:play", panelX + 2, 10, 10, playingMode == "library" and "restart" or "play")
    win:button("stop", panelX + 13, 10, 9, "stop")
    win:button("rescan", panelX + 23, 10, 10, "rescan")

    win:text(panelX + 2, 13, "instrument", 0x617487, 0xffffff)
    win:button("instrument:previous", panelX + 14, 13, 8, "previous")
    win:button("instrument:next", panelX + 23, 13, 8, "next")
    win:text(panelX + 33, 13, instruments[selectedInstrument].name, 0x1d2b3a, 0xffffff)

    win:text(panelX + 2, 15, "volume " .. tostring(math.floor(volume * 100)) .. "%", 0x617487, 0xffffff)
    win:button("quieter", panelX + 15, 15, 9, "quieter")
    win:button("louder", panelX + 25, 15, 8, "louder")

    win:text(panelX + 2, 18, "open studio for the piano and sequencer", 0x617487, 0xffffff)
  end

  local function drawGrid(width, topY)
    local baseNote = (studioOctave + 1) * 12
    local gridX = 5
    local labelWidth = 4
    local cellWidth = 2
    local gridWidth = labelWidth + 16 * cellWidth

    win:text(gridX, topY, "note", 0x607487, 0xf5f8fa)
    for step = 1, 16 do
      local x = gridX + labelWidth + (step - 1) * cellWidth
      local bg = step == studioStep and 0xb9ddf5 or 0xe8eef3
      win:fill(x, topY, cellWidth, 1, bg)
      win:text(x, topY, tostring((step - 1) % 10 + 1), 0x506678, bg)
    end

    for row = 0, 11 do
      local note = baseNote + (11 - row)
      local y = topY + 1 + row
      win:text(gridX, y, short(noteName(note), 4), 0x506678, 0xf5f8fa)
      for step = 1, 16 do
        local x = gridX + labelWidth + (step - 1) * cellWidth
        local active = pattern[step][note] == true
        local current = step == studioStep
        local bg
        if active and current then bg = 0x2f9fc1
        elseif active then bg = 0x57c5df
        elseif current then bg = 0xd7eaf4
        else bg = (step % 4 == 0) and 0xdde5ea or 0xedf2f5 end
        win:fill(x, y, cellWidth, 1, bg)
        win:hit("cell:" .. step .. ":" .. note, x, y, cellWidth, 1)
      end
    end

    return gridX + gridWidth + 2
  end

  local function drawPiano(y, width)
    local baseNote = (studioOctave + 1) * 12
    local whiteNotes = {0, 2, 4, 5, 7, 9, 11, 12}
    local blackNotes = {
      {note=1, after=1}, {note=3, after=2}, {note=6, after=4}, {note=8, after=5}, {note=10, after=6}
    }
    local keyWidth = math.max(4, math.min(6, math.floor((width - 10) / #whiteNotes)))
    local totalWidth = keyWidth * #whiteNotes
    local startX = math.max(3, math.floor((width - totalWidth) / 2) + 1)

    for index, offset in ipairs(whiteNotes) do
      local x = startX + (index - 1) * keyWidth
      local note = baseNote + offset
      win:fill(x, y, keyWidth - 1, 4, 0xf7f8fa)
      win:fill(x, y + 3, keyWidth - 1, 1, 0xdce4e9)
      win:text(x + 1, y + 3, short(noteName(note), keyWidth - 2), 0x40566a, 0xdce4e9)
      win:hit("piano:" .. note, x, y + 2, keyWidth - 1, 2)
    end

    for _, black in ipairs(blackNotes) do
      local x = startX + black.after * keyWidth - 1
      local note = baseNote + black.note
      win:fill(x, y, 3, 2, 0x1c2a38)
      win:hit("piano:" .. note, x, y, 3, 2)
    end
  end

  local function drawStudio(width, height)
    win:fill(1, 4, width, height - 4, 0xf5f8fa)
    local panelX = drawGrid(width, 5)
    local panelWidth = width - panelX - 3

    if panelWidth >= 18 then
      win:fill(panelX, 5, panelWidth, 13, 0xe8eef3)
      win:text(panelX + 2, 5, "studio", 0x526a7c, 0xe8eef3)
      win:text(panelX + 2, 7, "bpm " .. tostring(studioBpm), 0x294052, 0xe8eef3)
      win:button("bpm:down", panelX + 10, 7, 7, "slower")
      if panelWidth >= 27 then win:button("bpm:up", panelX + 18, 7, 7, "faster") end

      win:text(panelX + 2, 9, "instrument", 0x526a7c, 0xe8eef3)
      win:text(panelX + 2, 10, instruments[selectedInstrument].name, 0x1d2b3a, 0xe8eef3)
      win:button("instrument:previous", panelX + 2, 11, 8, "previous")
      win:button("instrument:next", panelX + 11, 11, 8, "next")

      win:text(panelX + 2, 13, "octave " .. tostring(studioOctave), 0x526a7c, 0xe8eef3)
      win:button("octave:down", panelX + 11, 13, 6, "down")
      if panelWidth >= 25 then win:button("octave:up", panelX + 18, 13, 5, "up") end

      win:button("studio:play", panelX + 2, 15, 8, playingMode == "studio" and "restart" or "play")
      win:button("stop", panelX + 11, 15, 7, "stop")
      win:button("loop", panelX + 19, 15, 6, studioLoop and "loop" or "once", studioLoop)
      win:button("record", panelX + 2, 17, 8, studioRecord and "record" or "listen", studioRecord)
      win:button("clear", panelX + 11, 17, 7, "clear")
      if panelWidth >= 27 then
        win:button("save", panelX + 19, 17, 6, "save")
        win:button("load", panelX + 26, 17, 6, "load")
      end
    end

    local pianoY = math.max(19, height - 6)
    win:text(4, pianoY - 1, "piano: a w s e d f t g y h u j k", 0x607487, 0xf5f8fa)
    drawPiano(pianoY, width)
  end

  local function draw()
    local width, height = win.width, win.height
    win:reset()
    drawHeader(width)
    if mode == "studio" then drawStudio(width, height) else drawLibrary(width, height) end
    win:fill(1, height - 1, width, 2, 0xe7edf2)
    local device = soundAddress and ("sound " .. short(soundAddress, 24)) or "no computronics sound card"
    win:text(3, height - 1, device, 0x617487, 0xe7edf2)
  end

  local function handlePlayback(now)
    if not playingMode or now < nextAt then return end

    if playingMode == "library" then
      local track = tracks[selectedTrack]
      if playbackIndex > #track.events then
        stopSound("finished " .. track.name)
        return
      end
      local event = track.events[playbackIndex]
      local duration = math.max(40, math.floor((60000 / track.bpm) * (tonumber(event[2]) or 1)))
      local queued = queueChord(event[1] or {}, duration, selectedInstrument)
      if not queued then stopSound("playback stopped") return end
      playbackIndex = playbackIndex + 1
      nextAt = now + queued / 1000
      return
    end

    local duration = math.max(80, math.floor((60000 / studioBpm) / 2))
    local notes = sortedNotes(pattern[playbackIndex])
    local queued = queueChord(notes, duration, selectedInstrument)
    if not queued then stopSound("studio playback stopped") return end
    studioStep = playbackIndex
    playbackIndex = playbackIndex + 1
    if playbackIndex > 16 then
      if studioLoop then playbackIndex = 1 else stopSound("studio pattern finished") return end
    end
    nextAt = now + queued / 1000
  end

  local function cycleInstrument(delta)
    selectedInstrument = ((selectedInstrument - 1 + delta) % #instruments) + 1
    status = "instrument: " .. instruments[selectedInstrument].name
  end

  detectSound()

  while true do
    local now = app.computer.uptime()
    handlePlayback(now)
    draw()

    local timeout
    if playingMode then timeout = math.max(0, math.min(0.10, nextAt - app.computer.uptime())) end
    local name, address, id, code, player = app.pull(timeout)

    if name == "idk_button" then
      local nextMode = tostring(id):match("^mode:(%w+)$")
      local track = tonumber(tostring(id):match("^track:(%d+)$"))
      local pianoNote = tonumber(tostring(id):match("^piano:(%d+)$"))
      local cellStep, cellNote = tostring(id):match("^cell:(%d+):(%d+)$")

      if nextMode == "library" or nextMode == "studio" then
        stopSound()
        mode = nextMode
        status = mode == "studio" and "music maker ready" or "library ready"
      elseif track and tracks[track] then
        stopSound()
        selectedTrack = track
        selectedInstrument = tracks[track].instrument or selectedInstrument
        status = "selected " .. tracks[track].name
      elseif pianoNote then
        previewNote(pianoNote, true)
      elseif cellStep and cellNote then
        togglePattern(tonumber(cellStep), tonumber(cellNote))
      elseif id == "library:play" then
        stopSound()
        beginLibrary()
      elseif id == "studio:play" then
        stopSound()
        beginStudio()
      elseif id == "stop" then
        stopSound("stopped")
      elseif id == "rescan" then
        stopSound()
        soundAddress, soundProxy = nil, nil
        detectSound()
      elseif id == "quieter" then
        volume = math.max(0.10, volume - 0.10)
        invoke("setTotalVolume", playingMode and volume or 0)
      elseif id == "louder" then
        volume = math.min(1, volume + 0.10)
        invoke("setTotalVolume", playingMode and volume or 0)
      elseif id == "instrument:previous" then
        cycleInstrument(-1)
      elseif id == "instrument:next" then
        cycleInstrument(1)
      elseif id == "bpm:down" then
        studioBpm = math.max(50, studioBpm - 5)
      elseif id == "bpm:up" then
        studioBpm = math.min(220, studioBpm + 5)
      elseif id == "octave:down" then
        studioOctave = math.max(2, studioOctave - 1)
      elseif id == "octave:up" then
        studioOctave = math.min(6, studioOctave + 1)
      elseif id == "loop" then
        studioLoop = not studioLoop
      elseif id == "record" then
        studioRecord = not studioRecord
      elseif id == "clear" then
        stopSound()
        clearPattern()
      elseif id == "save" then
        savePattern()
      elseif id == "load" then
        stopSound()
        loadPattern()
      end
    elseif name == "key_down" and mode == "studio" then
      local character
      if tonumber(id) and tonumber(id) > 0 and tonumber(id) < 128 then
        character = string.char(tonumber(id)):lower()
      end
      local offset = character and keyboardNotes[character]
      if offset then
        local note = (studioOctave + 1) * 12 + offset
        previewNote(note, true)
      elseif code == keyboard.keys.space then
        if playingMode == "studio" then stopSound("stopped") else beginStudio() end
      end
    end
  end
end
