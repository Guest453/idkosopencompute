-- idk VM virtual hard disk: single-file, bounded, versioned container.
-- Guest paths NEVER resolve against the host filesystem.
local M = {}
local MAGIC = "IDKVHD1\n"
local MAX_IMAGE = 512 * 1024
local MAX_FILES = 128
local MAX_PATH = 128

local function canon(path)
  if type(path) ~= "string" then return nil end
  if #path < 1 or #path > MAX_PATH or path:find("%z") or path:find("\\", 1, true) then return nil end
  local stack = {}
  for part in ("/" .. path):gmatch("[^/]+") do
    if part == ".." then
      if #stack == 0 then return nil end
      stack[#stack] = nil
    elseif part ~= "" and part ~= "." then
      if not part:match("^[%w%._%-]+$") then return nil end
      stack[#stack + 1] = part
    end
  end
  return "/" .. table.concat(stack, "/")
end
M.canon = canon

local function parent(path)
  -- "/init.lua" matches the empty string, not nil. Lua considers "" true,
  -- so 'or "/"' alone incorrectly rejects files directly in the VHD root.
  local dir = path:match("^(.*)/[^/]+$")
  return dir and dir ~= "" and dir or "/"
end
M.parent = parent

local function capacity(d)
  local total = 0
  for path, data in pairs(d.files) do total = total + #path + #data + 24 end
  for path in pairs(d.dirs) do total = total + #path + 24 end
  return total
end

function M.new(path, kb)
  local d = {path = path, limit = math.min(MAX_IMAGE, math.max(32 * 1024, (tonumber(kb) or 128) * 1024)),
    files = {}, dirs = {["/"] = true}}
  return d
end
function M.used(d) return capacity(d) end
function M.exists(d, path)
  path = canon(path)
  return path and (d.dirs[path] or d.files[path] ~= nil) and true or false
end
function M.isDirectory(d, path)
  path = canon(path)
  return path and d.dirs[path] and true or false
end
function M.makeDirectory(d, path)
  path = canon(path)
  if not path then return nil, "invalid path" end
  if d.files[path] then return nil, "file exists" end
  local current = ""
  for part in path:gmatch("[^/]+") do
    current = current .. "/" .. part
    if d.files[current] then return nil, "a parent is a file" end
    d.dirs[current] = true
  end
  return true
end
function M.read(d, path)
  path = canon(path)
  if not path then return nil, "invalid path" end
  return d.files[path], d.files[path] == nil and "no such file" or nil
end
function M.write(d, path, data)
  path = canon(path)
  if not path or path == "/" or type(data) ~= "string" then return nil, "invalid file" end
  if d.dirs[path] then return nil, "path is a directory" end
  if not d.dirs[parent(path)] then return nil, "parent directory missing" end
  local previous = d.files[path]
  d.files[path] = data
  if capacity(d) > d.limit or capacity(d) > MAX_IMAGE then
    d.files[path] = previous
    return nil, "virtual hard disk is full"
  end
  return true
end
function M.remove(d, path)
  path = canon(path)
  if not path or path == "/" then return nil, "invalid path" end
  if d.files[path] ~= nil then d.files[path] = nil return true end
  if d.dirs[path] then
    for name in pairs(d.files) do
      if name:sub(1, #path + 1) == path .. "/" then return nil, "directory not empty" end
    end
    for name in pairs(d.dirs) do
      if name ~= path and name:sub(1, #path + 1) == path .. "/" then return nil, "directory not empty" end
    end
    d.dirs[path] = nil
    return true
  end
  return nil, "not found"
end
function M.list(d, path)
  path = canon(path)
  if not path or not d.dirs[path] then return nil, "not a directory" end
  local names, prefix = {}, path == "/" and "/" or path .. "/"
  for name in pairs(d.dirs) do
    if name ~= path and name:sub(1, #prefix) == prefix then
      local tail = name:sub(#prefix + 1)
      if tail ~= "" and not tail:find("/", 1, true) then names[#names + 1] = tail .. "/" end
    end
  end
  for name in pairs(d.files) do
    if name:sub(1, #prefix) == prefix then
      local tail = name:sub(#prefix + 1)
      if tail ~= "" and not tail:find("/", 1, true) then names[#names + 1] = tail end
    end
  end
  table.sort(names)
  return names
end
function M.rename(d, old, new)
  old, new = canon(old), canon(new)
  if not old or not new or old == "/" or new == "/" or M.exists(d,new) then return nil, "bad rename" end
  if not d.dirs[parent(new)] then return nil, "new parent missing" end
  if d.files[old] ~= nil then
    local data = d.files[old]
    local ok, err = M.write(d, new, data)
    if not ok then return nil, err end
    d.files[old] = nil
    return true
  end
  return nil, "renaming directories is not supported"
end
function M.save(d)
  local entries = {}
  for name, data in pairs(d.files) do entries[#entries + 1] = {"F", name, data} end
  for name in pairs(d.dirs) do
    if name ~= "/" then entries[#entries + 1] = {"D", name, ""} end
  end
  if #entries > MAX_FILES or capacity(d) > d.limit then return nil, "virtual disk limit exceeded" end
  table.sort(entries, function(a,b) return a[2] < b[2] end)
  local parts = {MAGIC, tostring(d.limit), "\n"}
  for _, e in ipairs(entries) do
    parts[#parts + 1] = e[1] .. tostring(#e[2]) .. ":" .. tostring(#e[3]) .. ":"
    parts[#parts + 1] = e[2]
    parts[#parts + 1] = e[3]
  end
  local result = table.concat(parts)
  if #result > MAX_IMAGE + 8192 then return nil, "disk file exceeds image limit" end
  local temp = d.path .. ".new"
  local file, reason = io.open(temp, "w")
  if not file then return nil, reason end
  local ok, err = file:write(result)
  file:close()
  if not ok then return nil, err end
  local fs = require("filesystem")
  -- Keep the original until the new image has been completely written.
  local old = d.path .. ".bak"
  if fs.exists(old) then fs.remove(old) end
  if fs.exists(d.path) then
    local moved, why = fs.rename(d.path, old)
    if not moved then fs.remove(temp) return nil, why end
  end
  local moved, why = fs.rename(temp, d.path)
  if not moved then
    if fs.exists(old) then fs.rename(old, d.path) end
    return nil, why
  end
  return true
end
function M.load(path)
  local f, reason = io.open(path, "r")
  if not f then return nil, reason end
  local src = f:read("*a")
  f:close()
  if type(src) ~= "string" or #src > MAX_IMAGE + 8192 or src:sub(1,#MAGIC) ~= MAGIC then
    return nil, "invalid or oversized VHD"
  end
  local pos = #MAGIC + 1
  local nl = src:find("\n", pos, true)
  if not nl then return nil, "missing capacity" end
  local size = tonumber(src:sub(pos,nl-1))
  if not size or size < 32768 or size > MAX_IMAGE then return nil, "invalid VHD capacity" end
  local d = M.new(path, size/1024)
  pos = nl + 1
  local count = 0
  while pos <= #src do
    count = count + 1
    if count > MAX_FILES then return nil, "too many files" end
    local kind = src:sub(pos,pos)
    local a = src:find(":",pos+1,true)
    local b = a and src:find(":",a+1,true)
    if not b or (kind ~= "D" and kind ~= "F") then return nil, "bad VHD entry" end
    local plen = tonumber(src:sub(pos+1,a-1))
    local length = tonumber(src:sub(a+1,b-1))
    if not plen or plen < 1 or plen > MAX_PATH or not length or length < 0 or length > MAX_IMAGE then
      return nil, "bad VHD lengths"
    end
    if b + plen + length > #src then return nil, "truncated VHD entry" end
    local name = src:sub(b+1,b+plen)
    local data = src:sub(b+plen+1,b+plen+length)
    if canon(name) ~= name then return nil, "unsafe VHD path" end
    if kind == "D" then d.dirs[name] = true else d.files[name] = data end
    pos = b + plen + length + 1
  end
  if capacity(d) > d.limit then return nil, "VHD exceeds its declared capacity" end
  for name in pairs(d.files) do
    if not d.dirs[parent(name)] then return nil, "VHD has a missing parent directory" end
  end
  return d
end
return M
