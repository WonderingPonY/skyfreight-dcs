local M = {}

local DEFAULT_SAVE_DIR = "Missions/Saves/skyfreight"

local codepointToUtf8
local copyFile
local decodeObjectKey
local decodeValue
local dirname
local encodeValue
local ensureDirectory
local escapeString
local fileExists
local getPath
local isRootPath
local isArray
local joinPath
local loadJsonFile
local logError
local logInfo
local logWarning
local parseArray
local parseLiteral
local parseNumber
local parseObject
local parseString
local readFile
local skipWhitespace
local writeFile

function M.getSaveDir()
  local config = nil
  local persistence = nil
  local saveDir = nil

  if skyfreight and skyfreight.config then
    config = skyfreight.config
  end

  if config then
    persistence = config.persistence
  end

  if persistence and persistence.save_dir then
    saveDir = persistence.save_dir
  end

  if type(saveDir) ~= "string" or saveDir == "" then
    saveDir = DEFAULT_SAVE_DIR
  end

  return saveDir
end

function M.getPath(fileName)
  return getPath(fileName)
end

function M.encode(value)
  return encodeValue(value)
end

function M.decode(text)
  local value = nil
  local nextIndex = nil

  if type(text) ~= "string" then
    error("json text must be a string")
  end

  value, nextIndex = decodeValue(text, 1)
  nextIndex = skipWhitespace(text, nextIndex)

  if nextIndex <= #text then
    error("unexpected trailing content at byte " .. tostring(nextIndex))
  end

  return value
end

function M.read(fileName, defaultValue)
  local value = loadJsonFile(getPath(fileName), fileName)

  if value == nil then
    return defaultValue
  end

  return value
end

function M.write(fileName, value)
  local finalPath = getPath(fileName)
  local tempPath = finalPath .. ".tmp"
  local backupPath = finalPath .. ".bak"
  local encoded = nil
  local ok = false
  local err = nil

  if not ensureDirectory(M.getSaveDir()) then
    return false
  end

  ok, encoded = pcall(M.encode, value)
  if not ok then
    logError("failed to encode " .. tostring(fileName) .. ": " .. tostring(encoded))
    return false
  end

  if fileExists(finalPath) then
    copyFile(finalPath, backupPath)
  end

  if not writeFile(tempPath, encoded) then
    return false
  end

  ok, err = pcall(os.rename, tempPath, finalPath)
  if ok and err then
    logInfo("saved " .. tostring(fileName) .. " to " .. finalPath)
    return true
  end

  if fileExists(finalPath) then
    pcall(os.remove, finalPath)
  end

  ok, err = pcall(os.rename, tempPath, finalPath)
  if ok and err then
    logInfo("saved " .. tostring(fileName) .. " to " .. finalPath)
    return true
  end

  logWarning(
    "failed to promote temp file for "
      .. tostring(fileName)
      .. ": "
      .. tostring(err)
  )
  return false
end

function M.exists(fileName)
  return fileExists(getPath(fileName))
end

logInfo = function(message)
  if env and env.info then
    env.info("[skyfreight] " .. tostring(message))
  end
end

logWarning = function(message)
  if env and env.warning then
    env.warning("[skyfreight] " .. tostring(message))
    return
  end

  logInfo(message)
end

logError = function(message)
  if env and env.error then
    env.error("[skyfreight] " .. tostring(message))
    return
  end

  logWarning(message)
end

joinPath = function(basePath, childName)
  if type(basePath) ~= "string" or basePath == "" then
    return childName
  end

  if string.sub(basePath, -1) == "/" or string.sub(basePath, -1) == "\\" then
    return basePath .. childName
  end

  return basePath .. "/" .. childName
end

dirname = function(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  if isRootPath(path) then
    return nil
  end

  if string.match(path, "^%a:[/\\][^/\\]+$") then
    return string.sub(path, 1, 3)
  end

  return string.match(path, "^(.*)[/\\][^/\\]+$")
end

isRootPath = function(path)
  if path == "/" or path == "\\" then
    return true
  end

  if string.match(path, "^%a:[/\\]?$") then
    return true
  end

  return false
end

getPath = function(fileName)
  if type(fileName) ~= "string" or fileName == "" then
    error("file name is required")
  end

  return joinPath(M.getSaveDir(), fileName)
end

fileExists = function(path)
  local handle = nil

  if type(path) ~= "string" or path == "" then
    return false
  end

  handle = io.open(path, "rb")
  if not handle then
    return false
  end

  handle:close()
  return true
end

readFile = function(path)
  local handle = nil
  local content = nil

  handle = io.open(path, "rb")
  if not handle then
    return nil
  end

  content = handle:read("*a")
  handle:close()

  return content
end

writeFile = function(path, content)
  local handle = nil

  handle = io.open(path, "wb")
  if not handle then
    logWarning("failed to open file for write: " .. tostring(path))
    return false
  end

  handle:write(content)
  handle:close()

  return true
end

copyFile = function(sourcePath, destinationPath)
  local content = nil

  content = readFile(sourcePath)
  if content == nil then
    return false
  end

  return writeFile(destinationPath, content)
end

ensureDirectory = function(path)
  local attributes = nil
  local lfsModule = lfs
  local ok = false
  local result = nil
  local parent = nil

  if type(path) ~= "string" or path == "" or path == "." or isRootPath(path) then
    return true
  end

  if not lfsModule then
    logWarning("lfs is unavailable; cannot ensure directory " .. tostring(path))
    return false
  end

  ok, attributes = pcall(lfsModule.attributes, path)
  if ok and attributes and attributes.mode == "directory" then
    return true
  end

  parent = dirname(path)
  if parent and parent ~= path and not ensureDirectory(parent) then
    return false
  end

  ok, result = pcall(lfsModule.mkdir, path)
  if ok and result then
    return true
  end

  ok, attributes = pcall(lfsModule.attributes, path)
  if ok and attributes and attributes.mode == "directory" then
    return true
  end

  logWarning("failed to create directory " .. tostring(path))
  return false
end

loadJsonFile = function(path, label)
  local content = nil
  local ok = false
  local decoded = nil
  local backupPath = path .. ".bak"

  content = readFile(path)
  if content == nil then
    if fileExists(backupPath) then
      return loadJsonFile(backupPath, label .. ".bak")
    end

    return nil
  end

  ok, decoded = pcall(M.decode, content)
  if ok then
    return decoded
  end

  logWarning("failed to decode " .. tostring(label) .. ": " .. tostring(decoded))

  if fileExists(backupPath) and path ~= backupPath then
    logWarning("falling back to backup for " .. tostring(label))
    return loadJsonFile(backupPath, label .. ".bak")
  end

  return nil
end

isArray = function(value)
  local count = 0
  local maxIndex = 0
  local key = nil

  if type(value) ~= "table" then
    return false, 0
  end

  for key in pairs(value) do
    if type(key) ~= "number" then
      return false, 0
    end

    if key < 1 or key ~= math.floor(key) then
      return false, 0
    end

    if key > maxIndex then
      maxIndex = key
    end

    count = count + 1
  end

  if maxIndex ~= count then
    return false, 0
  end

  return true, maxIndex
end

escapeString = function(value)
  local substitutions = {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
  }

  return (string.gsub(value, "[%z\1-\31\\\"]", function(character)
    local replacement = substitutions[character]

    if replacement then
      return replacement
    end

    return string.format("\\u%04x", string.byte(character))
  end))
end

encodeValue = function(value)
  local valueType = type(value)
  local array = false
  local length = 0
  local parts = {}
  local index = 0
  local key = nil
  local keys = {}

  if valueType == "nil" then
    return "null"
  end

  if valueType == "boolean" then
    if value then
      return "true"
    end

    return "false"
  end

  if valueType == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("cannot encode non-finite number")
    end

    return tostring(value)
  end

  if valueType == "string" then
    return "\"" .. escapeString(value) .. "\""
  end

  if valueType ~= "table" then
    error("cannot encode value of type " .. valueType)
  end

  array, length = isArray(value)
  if array then
    for index = 1, length do
      parts[index] = encodeValue(value[index])
    end

    return "[" .. table.concat(parts, ",") .. "]"
  end

  for key in pairs(value) do
    if type(key) ~= "string" and type(key) ~= "number" then
      error("object keys must be strings or numbers")
    end

    keys[#keys + 1] = key
  end

  table.sort(keys, function(left, right)
    return tostring(left) < tostring(right)
  end)

  for index, key in ipairs(keys) do
    parts[index] = "\"" .. escapeString(tostring(key)) .. "\":" .. encodeValue(value[key])
  end

  return "{" .. table.concat(parts, ",") .. "}"
end

skipWhitespace = function(text, index)
  local current = index
  local character = ""

  while current <= #text do
    character = string.sub(text, current, current)
    if character ~= " " and character ~= "\n" and character ~= "\r" and character ~= "\t" then
      break
    end

    current = current + 1
  end

  return current
end

codepointToUtf8 = function(codepoint)
  if codepoint <= 127 then
    return string.char(codepoint)
  end

  if codepoint <= 2047 then
    return string.char(
      192 + math.floor(codepoint / 64),
      128 + (codepoint % 64)
    )
  end

  if codepoint <= 65535 then
    return string.char(
      224 + math.floor(codepoint / 4096),
      128 + (math.floor(codepoint / 64) % 64),
      128 + (codepoint % 64)
    )
  end

  return string.char(
    240 + math.floor(codepoint / 262144),
    128 + (math.floor(codepoint / 4096) % 64),
    128 + (math.floor(codepoint / 64) % 64),
    128 + (codepoint % 64)
  )
end

parseString = function(text, index)
  local current = index + 1
  local parts = {}
  local partIndex = 1
  local character = ""
  local escape = ""
  local hex = ""
  local value = 0

  while current <= #text do
    character = string.sub(text, current, current)

    if character == "\"" then
      return table.concat(parts), current + 1
    end

    if character == "\\" then
      current = current + 1
      escape = string.sub(text, current, current)

      if escape == "\"" or escape == "\\" or escape == "/" then
        parts[partIndex] = escape
      elseif escape == "b" then
        parts[partIndex] = "\b"
      elseif escape == "f" then
        parts[partIndex] = "\f"
      elseif escape == "n" then
        parts[partIndex] = "\n"
      elseif escape == "r" then
        parts[partIndex] = "\r"
      elseif escape == "t" then
        parts[partIndex] = "\t"
      elseif escape == "u" then
        hex = string.sub(text, current + 1, current + 4)
        if #hex < 4 or not string.match(hex, "^[0-9a-fA-F]+$") then
          error("invalid unicode escape at byte " .. tostring(current))
        end

        value = tonumber(hex, 16)
        parts[partIndex] = codepointToUtf8(value)
        current = current + 4
      else
        error("invalid escape at byte " .. tostring(current))
      end

      partIndex = partIndex + 1
      current = current + 1
    else
      parts[partIndex] = character
      partIndex = partIndex + 1
      current = current + 1
    end
  end

  error("unterminated string at byte " .. tostring(index))
end

parseNumber = function(text, index)
  local chunk = string.sub(text, index)
  local numberText = string.match(chunk, "^-?%d+%.?%d*[eE]?[+-]?%d*")
  local value = nil

  if not numberText or numberText == "" or numberText == "-" then
    error("invalid number at byte " .. tostring(index))
  end

  value = tonumber(numberText)
  if value == nil then
    error("invalid number at byte " .. tostring(index))
  end

  return value, index + #numberText
end

parseLiteral = function(text, index, literal, value)
  if string.sub(text, index, index + #literal - 1) ~= literal then
    error("invalid literal at byte " .. tostring(index))
  end

  return value, index + #literal
end

decodeObjectKey = function(key)
  local numberValue = nil

  if string.match(key, "^%-?0%d+$") then
    return key
  end

  if string.match(key, "^%-?%d+$") then
    numberValue = tonumber(key)
    if numberValue ~= nil then
      return numberValue
    end
  end

  return key
end

parseArray = function(text, index)
  local result = {}
  local current = skipWhitespace(text, index + 1)
  local value = nil

  if string.sub(text, current, current) == "]" then
    return result, current + 1
  end

  while current <= #text do
    value, current = decodeValue(text, current)
    result[#result + 1] = value
    current = skipWhitespace(text, current)

    if string.sub(text, current, current) == "]" then
      return result, current + 1
    end

    if string.sub(text, current, current) ~= "," then
      error("expected ',' or ']' at byte " .. tostring(current))
    end

    current = skipWhitespace(text, current + 1)
  end

  error("unterminated array at byte " .. tostring(index))
end

parseObject = function(text, index)
  local result = {}
  local current = skipWhitespace(text, index + 1)
  local key = nil
  local value = nil

  if string.sub(text, current, current) == "}" then
    return result, current + 1
  end

  while current <= #text do
    if string.sub(text, current, current) ~= "\"" then
      error("expected string key at byte " .. tostring(current))
    end

    key, current = parseString(text, current)
    current = skipWhitespace(text, current)

    if string.sub(text, current, current) ~= ":" then
      error("expected ':' at byte " .. tostring(current))
    end

    current = skipWhitespace(text, current + 1)
    value, current = decodeValue(text, current)
    result[decodeObjectKey(key)] = value
    current = skipWhitespace(text, current)

    if string.sub(text, current, current) == "}" then
      return result, current + 1
    end

    if string.sub(text, current, current) ~= "," then
      error("expected ',' or '}' at byte " .. tostring(current))
    end

    current = skipWhitespace(text, current + 1)
  end

  error("unterminated object at byte " .. tostring(index))
end

decodeValue = function(text, index)
  local current = skipWhitespace(text, index)
  local character = string.sub(text, current, current)

  if character == "{" then
    return parseObject(text, current)
  end

  if character == "[" then
    return parseArray(text, current)
  end

  if character == "\"" then
    return parseString(text, current)
  end

  if character == "-" or string.match(character, "%d") then
    return parseNumber(text, current)
  end

  if character == "t" then
    return parseLiteral(text, current, "true", true)
  end

  if character == "f" then
    return parseLiteral(text, current, "false", false)
  end

  if character == "n" then
    return parseLiteral(text, current, "null", nil)
  end

  error("unexpected character at byte " .. tostring(current))
end

return M
