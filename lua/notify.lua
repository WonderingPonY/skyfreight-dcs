local M = {}

local DEFAULT_DURATION = 10
local PREFIX = "[Skyfreight] "

local formatMessage
local getDuration
local getGroupIdFromUnit
local logInfo
local logWarning
local sendToAll
local sendToGroup

function M.all(message, duration, clearView)
  return sendToAll(formatMessage(message), getDuration(duration), clearView)
end

function M.group(groupId, message, duration, clearView)
  return sendToGroup(groupId, formatMessage(message), getDuration(duration), clearView)
end

function M.ucid(ucid, message, duration, clearView)
  local groupId = nil

  if not skyfreight or not skyfreight.identity then
    logWarning("identity module is unavailable for UCID notification")
    return false
  end

  groupId = skyfreight.identity.getGroupIdByUcid(ucid)
  if type(groupId) ~= "number" then
    logWarning("no group is mapped for UCID " .. tostring(ucid))
    return false
  end

  return M.group(groupId, message, duration, clearView)
end

function M.unit(unit, message, duration, clearView)
  local groupId = getGroupIdFromUnit(unit)

  if type(groupId) ~= "number" then
    logWarning("unable to resolve group for unit notification")
    return false
  end

  return M.group(groupId, message, duration, clearView)
end

function M.info(message, duration, clearView)
  return M.all(message, duration, clearView)
end

function M.warning(message, duration, clearView)
  return M.all("Warning: " .. tostring(message), duration, clearView)
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

formatMessage = function(message)
  return PREFIX .. tostring(message or "")
end

getDuration = function(duration)
  if type(duration) ~= "number" or duration <= 0 then
    return DEFAULT_DURATION
  end

  return duration
end

getGroupIdFromUnit = function(unit)
  local group = nil
  local ok = false
  local groupId = nil

  if type(unit) ~= "table" and type(unit) ~= "userdata" then
    return nil
  end

  if type(unit.isExist) ~= "function" then
    return nil
  end

  ok, group = pcall(unit.getGroup, unit)
  if not ok or not group or type(group.getID) ~= "function" then
    return nil
  end

  ok, groupId = pcall(group.getID, group)
  if not ok then
    return nil
  end

  return groupId
end

sendToAll = function(message, duration, clearView)
  local ok = false
  local result = nil

  if not trigger or not trigger.action or type(trigger.action.outText) ~= "function" then
    logWarning("trigger.action.outText is unavailable")
    return false
  end

  ok, result = pcall(trigger.action.outText, message, duration, clearView == true)
  if not ok then
    logWarning("failed to send global notification: " .. tostring(result))
    return false
  end

  return true
end

sendToGroup = function(groupId, message, duration, clearView)
  local ok = false
  local result = nil

  if type(groupId) ~= "number" then
    return false
  end

  if not trigger or not trigger.action or type(trigger.action.outTextForGroup) ~= "function" then
    logWarning("trigger.action.outTextForGroup is unavailable")
    return false
  end

  ok, result = pcall(
    trigger.action.outTextForGroup,
    groupId,
    message,
    duration,
    clearView == true
  )
  if not ok then
    logWarning(
      "failed to send group notification for group "
        .. tostring(groupId)
        .. ": "
        .. tostring(result)
    )
    return false
  end

  return true
end

return M
