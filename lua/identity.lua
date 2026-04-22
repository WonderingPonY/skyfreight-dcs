local M = {}

local state = {
  by_ucid = {},
  player_to_ucid = {},
  group_to_ucid = {},
  unit_to_ucid = {},
}

local cloneRecord
local getGroupId
local getNetField
local getPlayerIdList
local getSinglePlayerUcid
local getUnitKey
local isPlayerSlot
local isValidUnit
local logInfo
local logWarning
local rememberRecord
local removeRecord
local resolveFromCache
local resolveFromNetByGroup
local resolveFromNetByUnit
local safeGetGroup

function M.refresh()
  local playerIds = getPlayerIdList()
  local _, playerId = nil, nil

  if not playerIds then
    if getSinglePlayerUcid() then
      return true
    end

    return false
  end

  for _, playerId in ipairs(playerIds) do
    M.rememberPlayerId(playerId)
  end

  return true
end

function M.rememberPlayerId(playerId)
  local ucid = nil
  local name = nil
  local slot = nil

  if type(playerId) ~= "number" then
    return getSinglePlayerUcid()
  end

  ucid = getNetField(playerId, "ucid")
  if type(ucid) ~= "string" or ucid == "" then
    return getSinglePlayerUcid()
  end

  name = getNetField(playerId, "name")
  slot = getNetField(playerId, "slot")

  rememberRecord(ucid, {
    player_id = playerId,
    player_name = name,
    slot = slot,
  })

  return ucid
end

function M.rememberUnit(unit, ucid)
  local groupId = nil
  local unitKey = nil

  if type(ucid) ~= "string" or ucid == "" then
    return false
  end

  if not isValidUnit(unit) then
    return false
  end

  groupId = getGroupId(unit)
  unitKey = getUnitKey(unit)

  rememberRecord(ucid, {
    group_id = groupId,
    unit_key = unitKey,
  })

  return true
end

function M.rememberPlayerUnit(playerId, unit)
  local ucid = M.rememberPlayerId(playerId)

  if not ucid then
    return nil
  end

  M.rememberUnit(unit, ucid)
  return ucid
end

function M.forgetUcid(ucid)
  removeRecord(ucid)
end

function M.forgetPlayerId(playerId)
  local ucid = state.player_to_ucid[playerId]

  if ucid then
    removeRecord(ucid)
  end
end

function M.forgetUnit(unit)
  local unitKey = getUnitKey(unit)
  local ucid = nil

  if not unitKey then
    return
  end

  ucid = state.unit_to_ucid[unitKey]
  if ucid then
    removeRecord(ucid)
  end
end

function M.getPlayer(ucid)
  return cloneRecord(state.by_ucid[ucid])
end

function M.getPlayerByPlayerId(playerId)
  local ucid = M.getUcidByPlayerId(playerId)

  if not ucid then
    return nil
  end

  return M.getPlayer(ucid)
end

function M.getPlayerByGroupId(groupId)
  local ucid = M.getUcidByGroupId(groupId)

  if not ucid then
    return nil
  end

  return M.getPlayer(ucid)
end

function M.getUcidByPlayerId(playerId)
  local fallbackUcid = getSinglePlayerUcid()

  if fallbackUcid then
    return fallbackUcid
  end

  if type(playerId) ~= "number" then
    return nil
  end

  if state.player_to_ucid[playerId] then
    return state.player_to_ucid[playerId]
  end

  return M.rememberPlayerId(playerId)
end

function M.getUcidByGroupId(groupId)
  local ucid = resolveFromCache(nil, groupId, nil)
  local fallbackUcid = nil

  if ucid then
    return ucid
  end

  ucid = resolveFromNetByGroup(groupId)
  if ucid then
    return ucid
  end

  fallbackUcid = getSinglePlayerUcid()
  if fallbackUcid and type(groupId) == "number" then
    rememberRecord(fallbackUcid, {
      group_id = groupId,
    })
    return fallbackUcid
  end

  return nil
end

function M.getUcidByUnit(unit)
  local ucid = resolveFromCache(unit, nil, nil)
  local fallbackUcid = nil
  local groupId = nil
  local unitKey = nil

  if ucid then
    return ucid
  end

  ucid = resolveFromNetByUnit(unit)
  if ucid then
    return ucid
  end

  fallbackUcid = getSinglePlayerUcid()
  if fallbackUcid then
    groupId = getGroupId(unit)
    unitKey = getUnitKey(unit)
    rememberRecord(fallbackUcid, {
      group_id = groupId,
      unit_key = unitKey,
    })
    return fallbackUcid
  end

  return nil
end

function M.getGroupIdByUcid(ucid)
  local record = state.by_ucid[ucid]

  if record then
    return record.group_id
  end

  return nil
end

function M.getPlayerIdByUcid(ucid)
  local record = state.by_ucid[ucid]

  if record then
    return record.player_id
  end

  return nil
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

cloneRecord = function(record)
  local result = {}
  local key, value = nil, nil

  if type(record) ~= "table" then
    return nil
  end

  for key, value in pairs(record) do
    result[key] = value
  end

  return result
end

isValidUnit = function(unit)
  local ok = false
  local exists = false

  if type(unit) ~= "table" and type(unit) ~= "userdata" then
    return false
  end

  if type(unit.isExist) ~= "function" then
    return false
  end

  ok, exists = pcall(unit.isExist, unit)
  if not ok or not exists then
    return false
  end

  return true
end

safeGetGroup = function(unit)
  local ok = false
  local group = nil

  if not isValidUnit(unit) then
    return nil
  end

  if type(unit.getGroup) ~= "function" then
    return nil
  end

  ok, group = pcall(unit.getGroup, unit)
  if not ok then
    return nil
  end

  return group
end

getGroupId = function(unit)
  local group = safeGetGroup(unit)
  local ok = false
  local groupId = nil

  if not group or type(group.getID) ~= "function" then
    return nil
  end

  ok, groupId = pcall(group.getID, group)
  if not ok then
    return nil
  end

  return groupId
end

getUnitKey = function(unit)
  local ok = false
  local unitName = nil

  if not isValidUnit(unit) then
    return nil
  end

  if type(unit.getName) == "function" then
    ok, unitName = pcall(unit.getName, unit)
    if ok and type(unitName) == "string" and unitName ~= "" then
      return unitName
    end
  end

  if type(unit.getID) == "function" then
    ok, unitName = pcall(unit.getID, unit)
    if ok and unitName ~= nil then
      return tostring(unitName)
    end
  end

  return nil
end

getPlayerIdList = function()
  local ok = false
  local playerIds = nil

  if not net or type(net.get_player_list) ~= "function" then
    logWarning("net.get_player_list is unavailable; identity refresh skipped")
    return nil
  end

  ok, playerIds = pcall(net.get_player_list)
  if not ok or type(playerIds) ~= "table" then
    logWarning("net.get_player_list failed during identity refresh")
    return nil
  end

  return playerIds
end

getNetField = function(playerId, fieldName)
  local ok = false
  local value = nil

  if not net or type(net.get_player_info) ~= "function" then
    return nil
  end

  ok, value = pcall(net.get_player_info, playerId, fieldName)
  if ok then
    return value
  end

  return nil
end

getSinglePlayerUcid = function()
  local debugConfig = nil
  local fallbackUcid = nil

  if net and type(net.get_player_list) == "function" then
    return nil
  end

  if not skyfreight or not skyfreight.config then
    return nil
  end

  debugConfig = skyfreight.config.debug
  if not debugConfig or debugConfig.enabled ~= true then
    return nil
  end

  fallbackUcid = debugConfig.single_player_ucid
  if type(fallbackUcid) ~= "string" or fallbackUcid == "" then
    return nil
  end

  rememberRecord(fallbackUcid, {
    player_name = "Single Player",
  })

  return fallbackUcid
end

isPlayerSlot = function(slot)
  if type(slot) == "string" then
    if slot == "" or slot == "spectator" then
      return false
    end

    return true
  end

  if type(slot) == "number" then
    return slot > 0
  end

  return false
end

rememberRecord = function(ucid, fields)
  local record = nil
  local previousPlayerId = nil
  local previousGroupId = nil
  local previousUnitKey = nil
  local key, value = nil, nil

  if type(ucid) ~= "string" or ucid == "" then
    return nil
  end

  record = state.by_ucid[ucid]
  if not record then
    record = {
      ucid = ucid,
    }
    state.by_ucid[ucid] = record
  end

  previousPlayerId = record.player_id
  previousGroupId = record.group_id
  previousUnitKey = record.unit_key

  for key, value in pairs(fields or {}) do
    if value ~= nil and value ~= "" then
      record[key] = value
    end
  end

  if previousPlayerId ~= nil and previousPlayerId ~= record.player_id then
    state.player_to_ucid[previousPlayerId] = nil
  end

  if previousGroupId ~= nil and previousGroupId ~= record.group_id then
    state.group_to_ucid[previousGroupId] = nil
  end

  if previousUnitKey ~= nil and previousUnitKey ~= record.unit_key then
    state.unit_to_ucid[previousUnitKey] = nil
  end

  if record.player_id ~= nil then
    state.player_to_ucid[record.player_id] = ucid
  end

  if record.group_id ~= nil then
    state.group_to_ucid[record.group_id] = ucid
  end

  if record.unit_key ~= nil then
    state.unit_to_ucid[record.unit_key] = ucid
  end

  return record
end

removeRecord = function(ucid)
  local record = state.by_ucid[ucid]

  if not record then
    return
  end

  if record.player_id ~= nil then
    state.player_to_ucid[record.player_id] = nil
  end

  if record.group_id ~= nil then
    state.group_to_ucid[record.group_id] = nil
  end

  if record.unit_key ~= nil then
    state.unit_to_ucid[record.unit_key] = nil
  end

  state.by_ucid[ucid] = nil
end

resolveFromCache = function(unit, groupId, playerId)
  local unitKey = nil

  if type(playerId) == "number" and state.player_to_ucid[playerId] then
    return state.player_to_ucid[playerId]
  end

  if type(groupId) == "number" and state.group_to_ucid[groupId] then
    return state.group_to_ucid[groupId]
  end

  unitKey = getUnitKey(unit)
  if unitKey and state.unit_to_ucid[unitKey] then
    return state.unit_to_ucid[unitKey]
  end

  return nil
end

resolveFromNetByGroup = function(groupId)
  local playerIds = getPlayerIdList()
  local _, playerId = nil, nil
  local slot = nil
  local ucid = nil

  if type(groupId) ~= "number" or not playerIds then
    return nil
  end

  for _, playerId in ipairs(playerIds) do
    slot = getNetField(playerId, "slot")
    if slot == groupId then
      ucid = M.rememberPlayerId(playerId)
      if ucid then
        rememberRecord(ucid, {
          group_id = groupId,
        })
        return ucid
      end
    end
  end

  return nil
end

resolveFromNetByUnit = function(unit)
  local groupId = getGroupId(unit)
  local unitKey = getUnitKey(unit)
  local playerIds = getPlayerIdList()
  local _, playerId = nil, nil
  local ucid = nil
  local slot = nil
  local playerUnitName = nil

  if not unitKey then
    return nil
  end

  if not playerIds then
    return nil
  end

  for _, playerId in ipairs(playerIds) do
    slot = getNetField(playerId, "slot")
    playerUnitName = getNetField(playerId, "unit_name")

    if playerUnitName == unitKey or (groupId and slot == groupId and isPlayerSlot(slot)) then
      ucid = M.rememberPlayerId(playerId)
      if ucid then
        rememberRecord(ucid, {
          group_id = groupId,
          unit_key = unitKey,
        })
        return ucid
      end
    end
  end

  return nil
end

return M
