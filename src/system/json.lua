local json = {}

local escapes = {['"']='\\"', ['\\']='\\\\', ['\b']='\\b', ['\f']='\\f', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t'}
local function encodeString(s)
  return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

function json.encode(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" or t == "number" then return tostring(v) end
  if t == "string" then return encodeString(v) end
  if t ~= "table" then error("cannot encode " .. t) end
  local isArray, n = true, 0
  for k in pairs(v) do
    if type(k) ~= "number" then isArray = false break end
    n = math.max(n, k)
  end
  local out = {}
  if isArray then
    for i = 1, n do out[#out + 1] = json.encode(v[i]) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  for k, value in pairs(v) do
    out[#out + 1] = encodeString(tostring(k)) .. ":" .. json.encode(value)
  end
  return "{" .. table.concat(out, ",") .. "}"
end

return json
