skyfreight = skyfreight or {}

local function logError(message)
  if env and env.error then
    env.error("[skyfreight] " .. tostring(message))
  end
end

local function loadFile(path, label)
  local ok, result = pcall(dofile, path)

  if not ok then
    logError("failed to load " .. label .. ": " .. tostring(result))
    error(result)
  end

  if type(result) ~= "table" then
    logError("module " .. label .. " did not return a table")
    error("module " .. label .. " did not return a table")
  end

  return result
end

local function resolveLuaPath()
  local info = nil
  local source = ""
  local path = "."

  if debug and debug.getinfo then
    info = debug.getinfo(1, "S")
  end

  if info and info.source then
    source = info.source
  end

  if string.sub(source, 1, 1) == "@" then
    path = string.match(string.sub(source, 2), "^(.*)[/\\][^/\\]+$") or "."
  end

  return path
end

local function loadModule(name, path)
  local module = loadFile(path, name)

  skyfreight[name] = module
  skyfreight.modules[name] = module

  return module
end

local luaPath = resolveLuaPath()

skyfreight.core = loadFile(luaPath .. "/core.lua", "core")
skyfreight.core.bootstrap(skyfreight, luaPath)
skyfreight.modules.core = skyfreight.core

loadModule("config", luaPath .. "/config.lua")
loadModule("util", luaPath .. "/util.lua")
loadModule("events", luaPath .. "/events.lua")
loadModule("timers", luaPath .. "/timers.lua")
loadModule("zones", luaPath .. "/zones.lua")
loadModule("contracts", luaPath .. "/contracts.lua")
loadModule("cargo", luaPath .. "/cargo.lua")
loadModule("pax", luaPath .. "/pax.lua")
loadModule("warehouses", luaPath .. "/warehouses.lua")
loadModule("menu", luaPath .. "/menu.lua")
loadModule("narrative", luaPath .. "/narrative.lua")
loadModule("srs", luaPath .. "/srs.lua")
loadModule("rank", luaPath .. "/rank.lua")
loadModule("leaderboard", luaPath .. "/leaderboard.lua")
loadModule("storage", luaPath .. "/storage.lua")
loadModule("notify", luaPath .. "/notify.lua")
loadModule("identity", luaPath .. "/identity.lua")
loadModule("credits", luaPath .. "/credits.lua")

skyfreight.templates.narratives = loadFile(
  luaPath .. "/templates/narratives.lua",
  "templates.narratives"
)

if env and env.info then
  env.info("[skyfreight] loaded Phase 0 module skeleton")
end

return skyfreight
