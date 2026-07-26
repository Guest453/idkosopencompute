return function(app)
  local unicode = require("unicode")
  local keyboard = require("keyboard")
  local component = app.component
  local win = app.window{title="music", width=112, height=34}

  local builtinSongs = {
    {
      kind="builtin", name="night drive", bpm=112, instrument=2,
      events={
        {{60,67},1}, {{64,71},1}, {{67,72},1}, {{64,71},1},
        {{57,64},1}, {{60,67},1}, {{64,69},1}, {{60,67},1},
        {{55,62},1}, {{59,67},1}, {{62,71},1}, {{59,67},1},
        {{53,60},1}, {{57,64},1}, {{60,69},1}, {{57,64},1}
      }
    },
    {
      kind="builtin", name="blue terminal", bpm=128, instrument=3,
      events={
        {{72},0.5}, {{76},0.5}, {{79},0.5}, {{84},0.5},
        {{79},0.5}, {{76},0.5}, {{74},0.5}, {{71},0.5},
        {{72,60},1}, {{76,64},1}, {{79,67},1}, {{76,64},1},
        {{69,57},1}, {{72,60},1}, {{76,64},1}, {{72,60},1}
      }
    },
    {
      kind="builtin", name="quiet boot", bpm=86, instrument=1,
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
      oscillators={{wave=3, ratio=1.00, level=0.76}, {wave=2, ratio=2.00, level=0.16}, {wave=2, ratio=3.00, level=0.07}},
      adsr={4, 210, 0.16, 310}
    },
    {
      name="electric",
      oscillators={{wave=2, ratio=1.00, level=0.68}, {wave=3, ratio=2.00, level=0.22}},
      adsr={8, 310, 0.28, 460}
    },
    {
      name="organ",
      oscillators={{wave=2, ratio=1.00, level=0.58}, {wave=1, ratio=2.00, level=0.15}},
      adsr={20, 75, 0.82, 150}
    },
    {
      name="bell",
      oscillators={{wave=2, ratio=1.00, level=0.68}, {wave=2, ratio=2.01, level=0.24}, {wave=3, ratio=3.99, level=0.08}},
      adsr={1, 640, 0.05, 900}
    },
    {
      name="bass",
      oscillators={{wave=3, ratio=0.50, level=0.72}, {wave=1, ratio=1.00, level=0.16}},
      adsr={3, 130, 0.34, 180}
    },
    {
      name="lead",
      oscillators={{wave=4, ratio=1.00, level=0.54}, {wave=2, ratio=2.00, level=0.14}},
      adsr={5, 95, 0.42, 160}
    }
  }

  local TRACK_COUNT = 4
  local PAGE_STEPS = 16
  local MIN_LENGTH = 16
  local MAX_LENGTH = 256
  local SONG_DIR = "/home/Music"

  local mode = "library"
  local selectedLibrary = 1
  local library = {}
  local selectedTrack = 1
  local volume = 0.70
  local playingMode = nil
  local playbackIndex = 1
  local nextAt = 0
  local status = "looking for computronics sound card"
  local soundAddress, soundProxy, channelCount

  local songName = "new song"
  local studioBpm = 120
  local songLength = 64
  local studioStep = 1
  local studioPage = 1
  local studioOctave = 4
  local studioLoop = true
  local studioRecord = true
  local naming = false
  local nameBuffer = ""

  local function newTrack(index)
    return {
      name = "track " .. tostring(index),
      instrument = math.min(index, #instruments),
      muted = false,
      steps = {}
    }
  end

  local function newProject()
    local result = {}
    for index = 1, TRACK_COUNT do result[index] = newTrack(index) end
    return result
  end

  local project = newProject()

  local noteNames = {"c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b"}
  local keyboardNotes = {
    a=0, w=1, s=2, e=3, d=4, f=5, t=6,
    g=7, y=8, h=9, u=10, j=11, k=12
  }

  local function short(value, limit)
    return unicode.sub(tostring(value or ""), 1, math.max(0, limit or 1))
  end

  local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
  end

  local function safeFilename(value)
    local name = trim(value):lower()
    name = name:gsub("[^%w _%-]", ""):gsub("%s+", "-"):gsub("%-+", "-")
    name = name:gsub("^%-+", ""):gsub("%-+$", "")
    if name == "" then name = "untitled" end
    return short(name, 40) .. ".song"
  end

  local function songPath(value)
    return app.fs.concat(SONG_DIR, safeFilename(value))
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

  local function queueVoices(voices, duration)
    duration = math.max(40, math.floor(tonumber(duration) or 250))
    if #voices == 0 then return duration end
    if not prepareSound() then return nil end

    invoke("clear")
    local channel = 1
    local used = {}
    local available = channelCount or 1
    local notesTotal = #voices

    for _, voice in ipairs(voices) do
      local instrument = instruments[voice.instrument] or instruments[1]
      local maxLayers = math.max(1, math.floor(available / math.max(1, notesTotal)))
      local layers = math.min(#instrument.oscillators, maxLayers)
      for layer = 1, layers do
        if channel > available then break end
        local oscillator = instrument.oscillators[layer]
        local adsr = instrument.adsr
        invoke("resetEnvelope", channel)
        invoke("setWave", channel, oscillator.wave)
        invoke("setFrequency", channel, noteFrequency(voice.note) * oscillator.ratio)
        invoke("setVolume", channel, math.min(1, volume * oscillator.level * (voice.level or 1)))
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

  local function queueChord(notes, duration, instrumentIndex)
    local voices = {}
    for _, note in ipairs(notes) do
      voices[#voices + 1] = {note=note, instrument=instrumentIndex, level=1}
    end
    return queueVoices(voices, duration)
  end

  local function stepVoices(step)
    local voices = {}
    for trackIndex, track in ipairs(project) do
      if not track.muted then
        for _, note in ipairs(sortedNotes(track.steps[step])) do
          voices[#voices + 1] = {note=note, instrument=track.instrument, level=trackIndex == 1 and 1 or 0.82}
        end
      end
    end
    return voices
  end

  local function ensureStep(track, step)
    if not track.steps[step] then track.steps[step] = {} end
    return track.steps[step]
  end

  local function previewNote(note, record)
    stopSound()
    local instrumentIndex = project[selectedTrack].instrument
    local duration = instrumentIndex == 4 and 620 or 360
    queueChord({note}, duration, instrumentIndex)
    status = "piano " .. noteName(note)
    if record and studioRecord then
      ensureStep(project[selectedTrack], studioStep)[note] = true
      studioStep = studioStep % songLength + 1
      studioPage = math.floor((studioStep - 1) / PAGE_STEPS) + 1
    end
  end

  local function beginLibrary()
    local item = library[selectedLibrary]
    if not item then status = "library is empty" return end
    if item.kind == "song" then
      status = "load the song before playing it"
      return
    end
    selectedTrack = 1
    project[1].instrument = item.instrument or project[1].instrument
    playingMode = "library"
    playbackIndex = 1
    nextAt = 0
    status = "playing " .. item.name
  end

  local function beginStudio()
    playingMode = "studio"
    playbackIndex = studioStep
    nextAt = 0
    status = "playing " .. songName
  end

  local function togglePattern(trackIndex, step, note)
    local set = ensureStep(project[trackIndex], step)
    set[note] = not set[note]
    studioStep = step
    selectedTrack = trackIndex
    status = (set[note] and "added " or "removed ") .. noteName(note) .. " at step " .. tostring(step)
  end

  local function clearProject()
    project = newProject()
    studioStep = 1
    studioPage = 1
    status = "project cleared"
  end

  local function setLength(value)
    local nextLength = math.max(MIN_LENGTH, math.min(MAX_LENGTH, math.floor((tonumber(value) or songLength) / 16) * 16))
    if nextLength < songLength then
      for _, track in ipairs(project) do
        for step in pairs(track.steps) do if step > nextLength then track.steps[step] = nil end end
      end
    end
    songLength = nextLength
    studioStep = math.min(studioStep, songLength)
    local maxPage = math.ceil(songLength / PAGE_STEPS)
    studioPage = math.min(studioPage, maxPage)
    status = "song length: " .. tostring(songLength) .. " steps"
  end

  local function writeSong(path)
    app.fs.makeDirectory(SONG_DIR)
    local file, reason = io.open(path, "w")
    if not file then return nil, reason end
    file:write("idk-music-maker-2\n")
    file:write("name=" .. songName:gsub("[\r\n]", " ") .. "\n")
    file:write("bpm=" .. tostring(studioBpm) .. "\n")
    file:write("length=" .. tostring(songLength) .. "\n")
    file:write("octave=" .. tostring(studioOctave) .. "\n")
    file:write("loop=" .. (studioLoop and "1" or "0") .. "\n")
    file:write("tracks=" .. tostring(TRACK_COUNT) .. "\n")
    for trackIndex, track in ipairs(project) do
      file:write("track" .. trackIndex .. "name=" .. track.name:gsub("[\r\n]", " ") .. "\n")
      file:write("track" .. trackIndex .. "instrument=" .. tostring(track.instrument) .. "\n")
      file:write("track" .. trackIndex .. "muted=" .. (track.muted and "1" or "0") .. "\n")
      for step = 1, songLength do
        local notes = sortedNotes(track.steps[step])
        if #notes > 0 then
          local values = {}
          for _, note in ipairs(notes) do values[#values + 1] = tostring(note) end
          file:write("t" .. trackIndex .. "s" .. step .. "=" .. table.concat(values, ",") .. "\n")
        end
      end
    end
    file:close()
    return true
  end

  local function scanLibrary()
    library = {}
    for _, item in ipairs(builtinSongs) do library[#library + 1] = item end
    if app.fs.exists(SONG_DIR) and app.fs.isDirectory(SONG_DIR) then
      local iterator = app.fs.list(SONG_DIR)
      for raw in iterator or function() end do
        local filename = tostring(raw):gsub("/$", "")
        if filename:sub(-5) == ".song" then
          local path = app.fs.concat(SONG_DIR, filename)
          local displayName = filename:sub(1, -6):gsub("%-", " ")
          local bpm, length = nil, nil
          local file = io.open(path, "r")
          if file then
            local first = file:read("*l")
            if first == "idk-music-maker-2" or first == "idk-music-maker-1" then
              for _ = 1, 8 do
                local line = file:read("*l")
                if not line then break end
                local key, value = line:match("^([%w]+)=(.*)$")
                if key == "name" and trim(value) ~= "" then displayName = trim(value)
                elseif key == "bpm" then bpm = tonumber(value)
                elseif key == "length" then length = tonumber(value) end
              end
            end
            file:close()
          end
          library[#library + 1] = {kind="song", name=displayName, bpm=bpm or 120, length=length or 16, path=path}
        end
      end
    end
    table.sort(library, function(a, b)
      if a.kind ~= b.kind then return a.kind == "builtin" end
      return a.name:lower() < b.name:lower()
    end)
    selectedLibrary = math.max(1, math.min(selectedLibrary, math.max(1, #library)))
  end

  local function saveProject()
    songName = trim(songName)
    if songName == "" then songName = "untitled" end
    local path = songPath(songName)
    local ok, reason = writeSong(path)
    if not ok then status = "save failed: " .. tostring(reason) return end
    status = "saved " .. path
    scanLibrary()
  end

  local function parseSong(path)
    local file, reason = io.open(path, "r")
    if not file then return nil, reason end
    local first = file:read("*l")
    if first ~= "idk-music-maker-2" and first ~= "idk-music-maker-1" then
      file:close()
      return nil, "unsupported song file"
    end

    if first == "idk-music-maker-1" then
      local nextProject = newProject()
      local nextBpm, nextOctave, nextLoop = 120, 4, true
      for line in file:lines() do
        local key, value = line:match("^([%w]+)=(.*)$")
        if key == "bpm" then nextBpm = math.max(50, math.min(220, tonumber(value) or nextBpm))
        elseif key == "instrument" then nextProject[1].instrument = math.max(1, math.min(#instruments, math.floor(tonumber(value) or 1)))
        elseif key == "octave" then nextOctave = math.max(2, math.min(6, math.floor(tonumber(value) or nextOctave)))
        elseif key == "loop" then nextLoop = value == "1"
        else
          local step = tonumber(tostring(key):match("^step(%d+)$"))
          if step and step >= 1 and step <= 16 then
            local set = ensureStep(nextProject[1], step)
            for raw in tostring(value):gmatch("[^,]+") do
              local note = tonumber(raw)
              if note and note >= 24 and note <= 108 then set[math.floor(note)] = true end
            end
          end
        end
      end
      file:close()
      return {name=path:match("([^/]+)%.song$") or "imported song", bpm=nextBpm, length=16, octave=nextOctave, loop=nextLoop, project=nextProject}
    end

    local result = {name="untitled", bpm=120, length=64, octave=4, loop=true, project=newProject()}
    for line in file:lines() do
      local key, value = line:match("^([%w]+)=(.*)$")
      if key == "name" then result.name = trim(value) ~= "" and trim(value) or result.name
      elseif key == "bpm" then result.bpm = math.max(50, math.min(220, tonumber(value) or result.bpm))
      elseif key == "length" then result.length = math.max(MIN_LENGTH, math.min(MAX_LENGTH, math.floor((tonumber(value) or result.length) / 16) * 16))
      elseif key == "octave" then result.octave = math.max(2, math.min(6, math.floor(tonumber(value) or result.octave)))
      elseif key == "loop" then result.loop = value == "1"
      else
        local trackName = tonumber(tostring(key):match("^track(%d+)name$"))
        local trackInstrument = tonumber(tostring(key):match("^track(%d+)instrument$"))
        local trackMuted = tonumber(tostring(key):match("^track(%d+)muted$"))
        local trackIndex, step = tostring(key):match("^t(%d+)s(%d+)$")
        trackIndex, step = tonumber(trackIndex), tonumber(step)
        if trackName and result.project[trackName] then
          result.project[trackName].name = short(trim(value), 24)
        elseif trackInstrument and result.project[trackInstrument] then
          result.project[trackInstrument].instrument = math.max(1, math.min(#instruments, math.floor(tonumber(value) or 1)))
        elseif trackMuted and result.project[trackMuted] then
          result.project[trackMuted].muted = value == "1"
        elseif trackIndex and step and result.project[trackIndex] and step >= 1 and step <= MAX_LENGTH then
          local set = ensureStep(result.project[trackIndex], step)
          for raw in tostring(value):gmatch("[^,]+") do
            local note = tonumber(raw)
            if note and note >= 24 and note <= 108 then set[math.floor(note)] = true end
          end
        end
      end
    end
    file:close()
    return result
  end

  local function loadSelectedSong()
    local item = library[selectedLibrary]
    if not item or item.kind ~= "song" then status = "select a saved song" return end
    local loaded, reason = parseSong(item.path)
    if not loaded then status = "load failed: " .. tostring(reason) return end
    stopSound()
    songName = loaded.name
    studioBpm = loaded.bpm
    songLength = loaded.length
    studioOctave = loaded.octave
    studioLoop = loaded.loop
    project = loaded.project
    selectedTrack = 1
    studioStep = 1
    studioPage = 1
    mode = "studio"
    status = "loaded " .. songName
  end

  local function deleteSelectedSong()
    local item = library[selectedLibrary]
    if not item or item.kind ~= "song" then status = "select a saved song" return end
    local ok, reason = app.fs.remove(item.path)
    if not ok and app.fs.exists(item.path) then status = "delete failed: " .. tostring(reason) return end
    status = "deleted " .. item.name
    scanLibrary()
  end

  local function drawHeader(width)
    win:fill(1, 1, width, 3, 0x15263b)
    win:text(3, 1, "music", 0xffffff, 0x15263b)
    win:text(3, 2, short(status, width - 6), 0x9fc7da, 0x15263b)
    win:button("mode:library", 3, 3, 11, "library", mode == "library")
    win:button("mode:studio", 15, 3, 11, "studio", mode == "studio")
  end

  local function drawLibrary(width, height)
    local sidebarWidth = math.min(31, math.max(24, math.floor(width * 0.30)))
    win:fill(3, 5, sidebarWidth, height - 8, 0xe8eef3)
    win:text(5, 5, "library", 0x5f7485, 0xe8eef3)

    local visibleRows = math.max(3, math.floor((height - 10) / 2))
    local libraryOffset = math.max(0, math.min(#library - visibleRows, selectedLibrary - visibleRows))
    for row = 1, visibleRows do
      local index = libraryOffset + row
      local item = library[index]
      if item then
        local y = 7 + (row - 1) * 2
        local active = index == selectedLibrary
        local background = active and 0xb9ddf5 or 0xe8eef3
        win:fill(4, y, sidebarWidth - 2, 2, background)
        win:text(5, y, short(item.name, sidebarWidth - 4), active and 0x173247 or 0x294052, background)
        local detail = item.kind == "builtin" and (tostring(item.bpm) .. " bpm  built in") or (tostring(item.bpm or 120) .. " bpm  " .. tostring(item.length or 16) .. " steps")
        win:text(5, y + 1, short(detail, sidebarWidth - 4), 0x617487, background)
        win:hit("library:" .. index, 4, y, sidebarWidth - 2, 2)
      end
    end

    local panelX = sidebarWidth + 5
    local panelWidth = width - panelX - 2
    local item = library[selectedLibrary]
    win:fill(panelX, 5, panelWidth, height - 8, 0xffffff)
    if item then
      win:text(panelX + 2, 5, short(item.name, panelWidth - 4), 0x1d2b3a, 0xffffff)
      win:text(panelX + 2, 6, item.kind == "builtin" and "built-in track" or "saved studio project", 0x617487, 0xffffff)
      win:text(panelX + 2, 8, tostring(item.bpm or 120) .. " bpm", 0x617487, 0xffffff)
      if item.kind == "builtin" then
        local progress = playingMode == "library" and math.max(0, math.min(1, (playbackIndex - 1) / math.max(1, #item.events))) or 0
        win:fill(panelX + 2, 10, math.max(1, panelWidth - 4), 1, 0xd8e2e9)
        if progress > 0 then win:fill(panelX + 2, 10, math.max(1, math.floor((panelWidth - 4) * progress)), 1, 0x4ec7e8) end
        win:button("library:play", panelX + 2, 12, 10, playingMode == "library" and "restart" or "play")
      else
        win:text(panelX + 2, 10, tostring(item.length or 16) .. " steps", 0x617487, 0xffffff)
        win:button("library:load", panelX + 2, 12, 10, "open")
        win:button("library:delete", panelX + 13, 12, 10, "delete")
      end
      win:button("stop", panelX + 24, 12, 9, "stop")
      win:button("rescan", panelX + 34, 12, 10, "rescan")
    end
    win:text(panelX + 2, height - 5, "saved songs from /home/Music appear here", 0x617487, 0xffffff)
  end

  local function drawGrid(width, topY)
    local baseNote = (studioOctave + 1) * 12
    local pageStart = (studioPage - 1) * PAGE_STEPS + 1
    local gridX = 5
    local labelWidth = 4
    local cellWidth = 2
    local gridWidth = labelWidth + PAGE_STEPS * cellWidth

    win:text(gridX, topY, "note", 0x607487, 0xf5f8fa)
    for column = 1, PAGE_STEPS do
      local step = pageStart + column - 1
      local x = gridX + labelWidth + (column - 1) * cellWidth
      local background = step == studioStep and 0xb9ddf5 or 0xe8eef3
      win:fill(x, topY, cellWidth, 1, background)
      win:text(x, topY, tostring((step - 1) % 10 + 1), 0x506678, background)
    end

    local track = project[selectedTrack]
    for row = 0, 11 do
      local note = baseNote + (11 - row)
      local y = topY + 1 + row
      win:text(gridX, y, short(noteName(note), 4), 0x506678, 0xf5f8fa)
      for column = 1, PAGE_STEPS do
        local step = pageStart + column - 1
        local x = gridX + labelWidth + (column - 1) * cellWidth
        local active = step <= songLength and track.steps[step] and track.steps[step][note] == true
        local current = step == studioStep
        local background
        if step > songLength then background = 0xc5cbd0
        elseif active and current then background = 0x2f9fc1
        elseif active then background = 0x57c5df
        elseif current then background = 0xd7eaf4
        else background = (column % 4 == 0) and 0xdde5ea or 0xedf2f5 end
        win:fill(x, y, cellWidth, 1, background)
        if step <= songLength then win:hit("cell:" .. selectedTrack .. ":" .. step .. ":" .. note, x, y, cellWidth, 1) end
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
    local keyWidth = math.max(4, math.min(7, math.floor((width - 10) / #whiteNotes)))
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

  local function drawTrackStrip(x, y, width)
    for index, track in ipairs(project) do
      local rowY = y + (index - 1) * 3
      local active = index == selectedTrack
      local background = active and 0xb9ddf5 or 0xe8eef3
      win:fill(x, rowY, width, 2, background)
      win:text(x + 1, rowY, short(track.name, width - 2), active and 0x173247 or 0x294052, background)
      win:text(x + 1, rowY + 1, instruments[track.instrument].name .. (track.muted and "  muted" or ""), 0x617487, background)
      win:hit("trackselect:" .. index, x, rowY, width, 2)
      win:button("trackmute:" .. index, x + width - 7, rowY + 1, 6, track.muted and "unmute" or "mute", track.muted)
    end
  end

  local function drawStudio(width, height)
    win:fill(1, 4, width, height - 4, 0xf5f8fa)
    local panelX = drawGrid(width, 5)
    local panelWidth = width - panelX - 3

    if panelWidth >= 24 then
      win:fill(panelX, 5, panelWidth, 22, 0xe8eef3)
      win:text(panelX + 2, 5, "project", 0x526a7c, 0xe8eef3)
      local displayName = naming and (nameBuffer .. "_") or songName
      win:text(panelX + 2, 6, short(displayName, panelWidth - 12), 0x1d2b3a, 0xe8eef3)
      win:button("name", panelX + panelWidth - 9, 6, 7, naming and "done" or "name", naming)

      win:text(panelX + 2, 8, "bpm " .. tostring(studioBpm), 0x526a7c, 0xe8eef3)
      win:button("bpm:down", panelX + 11, 8, 7, "slower")
      win:button("bpm:up", panelX + 19, 8, 7, "faster")

      win:text(panelX + 2, 10, "length " .. tostring(songLength), 0x526a7c, 0xe8eef3)
      win:button("length:down", panelX + 13, 10, 6, "less")
      win:button("length:up", panelX + 20, 10, 6, "more")

      local maxPage = math.ceil(songLength / PAGE_STEPS)
      win:text(panelX + 2, 12, "page " .. tostring(studioPage) .. "/" .. tostring(maxPage), 0x526a7c, 0xe8eef3)
      win:button("page:previous", panelX + 13, 12, 8, "previous")
      win:button("page:next", panelX + 22, 12, 6, "next")

      win:text(panelX + 2, 14, "octave " .. tostring(studioOctave), 0x526a7c, 0xe8eef3)
      win:button("octave:down", panelX + 13, 14, 6, "down")
      win:button("octave:up", panelX + 20, 14, 6, "up")

      win:text(panelX + 2, 16, "instrument", 0x526a7c, 0xe8eef3)
      win:text(panelX + 13, 16, instruments[project[selectedTrack].instrument].name, 0x1d2b3a, 0xe8eef3)
      win:button("instrument:previous", panelX + 2, 17, 8, "previous")
      win:button("instrument:next", panelX + 11, 17, 8, "next")

      win:button("studio:play", panelX + 2, 19, 8, playingMode == "studio" and "restart" or "play")
      win:button("stop", panelX + 11, 19, 7, "stop")
      win:button("loop", panelX + 19, 19, 6, studioLoop and "loop" or "once", studioLoop)
      win:button("record", panelX + 2, 21, 8, studioRecord and "record" or "listen", studioRecord)
      win:button("clear", panelX + 11, 21, 7, "clear")
      win:button("save", panelX + 19, 21, 6, "save")

      drawTrackStrip(panelX + 2, 24, math.max(18, panelWidth - 4))
    end

    local pianoY = math.max(20, height - 6)
    win:text(4, pianoY - 1, "piano keys: a w s e d f t g y h u j k", 0x607487, 0xf5f8fa)
    drawPiano(pianoY, math.min(width, panelX - 2))
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
      local item = library[selectedLibrary]
      if not item or item.kind ~= "builtin" then stopSound("library item unavailable") return end
      if playbackIndex > #item.events then stopSound("finished " .. item.name) return end
      local event = item.events[playbackIndex]
      local duration = math.max(40, math.floor((60000 / item.bpm) * (tonumber(event[2]) or 1)))
      local queued = queueChord(event[1] or {}, duration, item.instrument or 1)
      if not queued then stopSound("playback stopped") return end
      playbackIndex = playbackIndex + 1
      nextAt = now + queued / 1000
      return
    end

    local duration = math.max(60, math.floor((60000 / studioBpm) / 2))
    local voices = stepVoices(playbackIndex)
    local queued = queueVoices(voices, duration)
    if not queued then stopSound("studio playback stopped") return end
    studioStep = playbackIndex
    studioPage = math.floor((studioStep - 1) / PAGE_STEPS) + 1
    playbackIndex = playbackIndex + 1
    if playbackIndex > songLength then
      if studioLoop then playbackIndex = 1 else stopSound("song finished") return end
    end
    nextAt = now + queued / 1000
  end

  local function cycleInstrument(delta)
    local track = project[selectedTrack]
    track.instrument = ((track.instrument - 1 + delta) % #instruments) + 1
    status = track.name .. " instrument: " .. instruments[track.instrument].name
  end

  local function enterNaming()
    if naming then
      songName = trim(nameBuffer)
      if songName == "" then songName = "untitled" end
      naming = false
      status = "song named " .. songName
    else
      nameBuffer = songName
      naming = true
      status = "type a song name and press enter"
    end
  end

  scanLibrary()
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
      local libraryIndex = tonumber(tostring(id):match("^library:(%d+)$"))
      local pianoNote = tonumber(tostring(id):match("^piano:(%d+)$"))
      local cellTrack, cellStep, cellNote = tostring(id):match("^cell:(%d+):(%d+):(%d+)$")
      local trackSelect = tonumber(tostring(id):match("^trackselect:(%d+)$"))
      local trackMute = tonumber(tostring(id):match("^trackmute:(%d+)$"))

      if nextMode == "library" or nextMode == "studio" then
        stopSound()
        mode = nextMode
        if mode == "library" then scanLibrary() end
        status = mode == "studio" and "music maker ready" or "library ready"
      elseif libraryIndex and library[libraryIndex] then
        stopSound()
        selectedLibrary = libraryIndex
        status = "selected " .. library[libraryIndex].name
      elseif pianoNote then
        previewNote(pianoNote, true)
      elseif cellTrack and cellStep and cellNote then
        togglePattern(tonumber(cellTrack), tonumber(cellStep), tonumber(cellNote))
      elseif trackSelect and project[trackSelect] then
        selectedTrack = trackSelect
        status = "selected " .. project[trackSelect].name
      elseif trackMute and project[trackMute] then
        project[trackMute].muted = not project[trackMute].muted
        status = project[trackMute].name .. (project[trackMute].muted and " muted" or " unmuted")
      elseif id == "library:play" then
        stopSound()
        beginLibrary()
      elseif id == "library:load" then
        loadSelectedSong()
      elseif id == "library:delete" then
        deleteSelectedSong()
      elseif id == "studio:play" then
        stopSound()
        beginStudio()
      elseif id == "stop" then
        stopSound("stopped")
      elseif id == "rescan" then
        stopSound()
        soundAddress, soundProxy = nil, nil
        detectSound()
        scanLibrary()
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
      elseif id == "length:down" then
        setLength(songLength - 16)
      elseif id == "length:up" then
        setLength(songLength + 16)
      elseif id == "page:previous" then
        studioPage = math.max(1, studioPage - 1)
        studioStep = (studioPage - 1) * PAGE_STEPS + 1
      elseif id == "page:next" then
        studioPage = math.min(math.ceil(songLength / PAGE_STEPS), studioPage + 1)
        studioStep = (studioPage - 1) * PAGE_STEPS + 1
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
        clearProject()
      elseif id == "save" then
        saveProject()
      elseif id == "name" then
        enterNaming()
      end
    elseif name == "key_down" and mode == "studio" then
      if naming then
        if code == keyboard.keys.enter then
          enterNaming()
        elseif code == keyboard.keys.back then
          nameBuffer = unicode.sub(nameBuffer, 1, math.max(0, unicode.len(nameBuffer) - 1))
        elseif tonumber(id) and tonumber(id) >= 32 and tonumber(id) <= 126 and unicode.len(nameBuffer) < 36 then
          nameBuffer = nameBuffer .. string.char(tonumber(id))
        end
      else
        local character
        if tonumber(id) and tonumber(id) > 0 and tonumber(id) < 128 then character = string.char(tonumber(id)):lower() end
        local offset = character and keyboardNotes[character]
        if offset then
          local note = (studioOctave + 1) * 12 + offset
          previewNote(note, true)
        elseif code == keyboard.keys.space then
          if playingMode == "studio" then stopSound("stopped") else beginStudio() end
        elseif code == keyboard.keys.left then
          studioStep = math.max(1, studioStep - 1)
          studioPage = math.floor((studioStep - 1) / PAGE_STEPS) + 1
        elseif code == keyboard.keys.right then
          studioStep = math.min(songLength, studioStep + 1)
          studioPage = math.floor((studioStep - 1) / PAGE_STEPS) + 1
        end
      end
    elseif name == "clipboard" and mode == "studio" and naming then
      local pasted = tostring(code or ""):gsub("[%c]", " ")
      nameBuffer = short(nameBuffer .. pasted, 36)
    end
  end
end
