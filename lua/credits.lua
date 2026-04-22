local M = {}

local getPlayerRecord
local getRaffleRate
local logInfo
local logWarning
local normalizeAmount

function M.getBalance(ucid)
  local player = getPlayerRecord(ucid, true)

  if not player then
    return 0
  end

  return player.credits
end

function M.setBalance(ucid, amount)
  local player = getPlayerRecord(ucid, true)
  local normalized = normalizeAmount(amount)

  if not player then
    return nil
  end

  if normalized < 0 then
    normalized = 0
  end

  player.credits = normalized
  return player.credits
end

function M.canAfford(ucid, amount)
  local normalized = normalizeAmount(amount)

  if normalized <= 0 then
    return true
  end

  return M.getBalance(ucid) >= normalized
end

function M.add(ucid, amount)
  local player = getPlayerRecord(ucid, true)
  local normalized = normalizeAmount(amount)
  local previousBalance = 0
  local raffleRate = 0

  if not player then
    return nil
  end

  previousBalance = player.credits
  player.credits = previousBalance + normalized

  if player.credits < 0 then
    player.credits = 0
  end

  if normalized > 0 then
    player.session_earnings = player.session_earnings + normalized
    raffleRate = getRaffleRate()

    if raffleRate > 0 then
      player.raffle_tickets = player.raffle_tickets + math.floor(normalized / raffleRate)
    end
  end

  return player.credits
end

function M.spend(ucid, amount)
  local normalized = normalizeAmount(amount)

  if normalized <= 0 then
    return M.getBalance(ucid)
  end

  if not M.canAfford(ucid, normalized) then
    logWarning("insufficient credits for UCID " .. tostring(ucid))
    return nil
  end

  return M.add(ucid, -normalized)
end

function M.getSessionEarnings(ucid)
  local player = getPlayerRecord(ucid, true)

  if not player then
    return 0
  end

  return player.session_earnings
end

function M.getRaffleTickets(ucid)
  local player = getPlayerRecord(ucid, true)

  if not player then
    return 0
  end

  return player.raffle_tickets
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

normalizeAmount = function(amount)
  local numeric = tonumber(amount)

  if not numeric then
    return 0
  end

  if numeric >= 0 then
    return math.floor(numeric)
  end

  return math.ceil(numeric)
end

getPlayerRecord = function(ucid, createIfMissing)
  local state = nil
  local players = nil
  local player = nil

  if type(ucid) ~= "string" or ucid == "" then
    logWarning("credits operation missing UCID")
    return nil
  end

  if not skyfreight then
    logWarning("skyfreight namespace is unavailable in credits module")
    return nil
  end

  skyfreight.state = skyfreight.state or {}
  state = skyfreight.state

  state.players = state.players or {}
  players = state.players
  player = players[ucid]

  if not player and createIfMissing then
    player = {
      ucid = ucid,
      credits = 0,
      session_earnings = 0,
      raffle_tickets = 0,
    }
    players[ucid] = player
  end

  if not player then
    return nil
  end

  if type(player.credits) ~= "number" then
    player.credits = normalizeAmount(player.credits)
  end

  if type(player.session_earnings) ~= "number" then
    player.session_earnings = normalizeAmount(player.session_earnings)
  end

  if type(player.raffle_tickets) ~= "number" then
    player.raffle_tickets = normalizeAmount(player.raffle_tickets)
  end

  if type(player.ucid) ~= "string" or player.ucid == "" then
    player.ucid = ucid
  end

  return player
end

getRaffleRate = function()
  local raffle = nil

  if not skyfreight or not skyfreight.config then
    return 0
  end

  raffle = skyfreight.config.raffle
  if not raffle or raffle.enabled_tracking ~= true then
    return 0
  end

  return normalizeAmount(raffle.tickets_per_credits)
end

return M
