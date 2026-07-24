return function(app)
  local ID = "recoveryupdater"
  local win = app.window{title="idk os recovery updater",width=62,height=18,bg=0xf7f9fc}
  local status = "ready to install recovery mode"
  local confirm = false
  local busy = false

  local function draw()
    local width, height = win.width, math.max(1, win.height - 1)
    win:reset()
    win:fill(1,1,width,2,0x26394d)
    win:text(2,1,"idk os recovery updater",0xffffff,0x26394d)
    win:text(2,2,"safe full-system updates outside the desktop",0xbdd7ea,0x26394d)
    win:text(3,4,"the updater is loaded fully into ram before files change.",0x1d2b3a)
    win:text(3,6,"it stages every file from the official image manifest,",0x617487)
    win:text(3,7,"backs up existing system files, updates /init.lua last,",0x617487)
    win:text(3,8,"and rolls back if applying the update fails.",0x617487)
    win:fill(3,10,math.max(1,width-5),3,0xe7eef5)
    win:text(4,11,status,busy and 0xb06b16 or 0x397fca,0xe7eef5)
    win:button("update",3,height-2,22,confirm and "confirm update + reboot" or "enter recovery updater")
    win:button("cancel",math.max(28,width-12),height-2,10,"close")
  end

  local function readFile(path)
    local file, reason = io.open(path, "r")
    if not file then return nil, reason end
    local data, readReason = file:read("*a")
    file:close()
    return data, readReason
  end

  local function ensureDirectory(path)
    if app.fs.isDirectory(path) then return true end
    local ok, reason = app.fs.makeDirectory(path)
    if ok or app.fs.isDirectory(path) then return true end
    return nil, reason
  end

  local function writeFile(path, data)
    local previous
    if app.fs.exists(path) then
      local previousReason
      previous, previousReason = readFile(path)
      if previous == nil then return nil, "cannot preserve existing file: " .. tostring(previousReason) end
    end
    local temp = path .. ".new"
    if app.fs.exists(temp) then pcall(app.fs.remove, temp) end
    local file, reason = io.open(temp, "w")
    if not file then return nil, reason end
    local ok, writeReason = file:write(data)
    file:close()
    if not ok then pcall(app.fs.remove, temp) return nil, writeReason end
    if app.fs.exists(path) then
      local removed, removeReason = app.fs.remove(path)
      if not removed and app.fs.exists(path) then pcall(app.fs.remove, temp) return nil, removeReason end
    end
    local renamed, renameReason = app.fs.rename(temp, path)
    if not renamed then
      pcall(app.fs.remove, temp)
      if previous ~= nil then
        local restore = io.open(path, "w")
        if restore then restore:write(previous) restore:close() end
      end
      return nil, renameReason
    end
    return true
  end

  local function prepareRecovery()
    busy = true
    status = "checking package files..."
    draw()
    app.yield()

    local internetOk, internetAvailable = pcall(function()
      if type(app.component.isAvailable) == "function" then return app.component.isAvailable("internet") end
      return app.component.internet ~= nil
    end)
    if not internetOk or not internetAvailable then
      busy, status, confirm = false, "internet card is required", false
      return
    end

    local packagePath = "/home/Apps/" .. ID .. ".app"
    if not app.fs.isDirectory(packagePath) and type(app.apps) == "function" then
      local known = app.apps()[ID]
      if known and known.path then packagePath = known.path end
    end
    if not app.fs.isDirectory(packagePath) then
      busy, status, confirm = false, "cannot locate the installed updater package", false
      return
    end

    local bridge, bridgeReason = readFile(packagePath .. "/bridge.lua")
    local updater, updaterReason = readFile(packagePath .. "/updater.lua")
    if not bridge or not updater then
      busy, status, confirm = false, "package read failed: " .. tostring(bridgeReason or updaterReason), false
      return
    end
    local function isBridge(data) return type(data) == "string" and data:match("^%-%- idk recovery bridge v1") ~= nil end
    if not isBridge(bridge) then
      busy, status, confirm = false, "invalid recovery bridge package", false
      return
    end
    local bridgeChunk, bridgeSyntax = load(bridge, "=bridge.lua", "t", {})
    local updaterChunk, updaterSyntax = load(updater, "=updater.lua", "t", {})
    if not bridgeChunk or not updaterChunk then
      busy, status, confirm = false, "package syntax: " .. tostring(bridgeSyntax or updaterSyntax), false
      return
    end

    local made, makeReason = ensureDirectory("/idkos/recovery")
    if not made then busy, status, confirm = false, "recovery directory: " .. tostring(makeReason), false return end

    local currentInit, initReason = readFile("/init.lua")
    if not currentInit then busy, status, confirm = false, "cannot read /init.lua: " .. tostring(initReason), false return end

    if not isBridge(currentInit) then
      local saved, saveReason = writeFile("/idkos/recovery/original_init.lua", currentInit)
      if not saved then busy, status, confirm = false, "cannot save original init: " .. tostring(saveReason), false return end
    elseif not app.fs.exists("/idkos/recovery/original_init.lua") then
      busy, status, confirm = false, "recovery bridge exists but its original init is missing", false
      return
    end

    status = "installing ram updater..."
    draw()
    app.yield()
    local savedUpdater, updaterSaveReason = writeFile("/idkos/recovery/updater.lua", updater)
    if not savedUpdater then busy, status, confirm = false, "cannot install updater: " .. tostring(updaterSaveReason), false return end

    local savedBridge, bridgeSaveReason = writeFile("/init.lua", bridge)
    if not savedBridge then busy, status, confirm = false, "cannot install boot bridge: " .. tostring(bridgeSaveReason), false return end

    local marker, markerReason = writeFile("/idkos/recovery/next_boot", "update\n")
    if not marker then
      local original = readFile("/idkos/recovery/original_init.lua")
      if original then pcall(writeFile, "/init.lua", original) end
      busy, status, confirm = false, "cannot arm recovery boot: " .. tostring(markerReason), false
      return
    end

    status = "rebooting into recovery updater..."
    draw()
    app.sleep(0.35)
    app.computer.shutdown(true)
  end

  while true do
    draw()
    local name, _, id = app.pull()
    if name == "idk_button" and not busy then
      if id == "cancel" then return end
      if id == "update" then
        if confirm then prepareRecovery()
        else confirm = true status = "click again to reboot and update every idk os file" end
      else
        confirm = false
      end
    end
  end
end
