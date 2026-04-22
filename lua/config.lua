local M = {
  pool = {
    max_contracts = 20,
    generation_interval_minutes = 15,
    default_ttls = {
      cargo = 2,
      pax = 2,
      construction = 6,
      warehouse_delivery = 24,
      urgent = 0.5,
    },
  },
  payouts = {
    owner_percent = 100,
    crew_percent = 40,
    base_rate_per_nm = 50,
    per_crate_bonus = 100,
    per_pax_bonus = 50,
    priority_multipliers = {
      routine = 1.0,
      high = 1.3,
      urgent = 1.6,
    },
  },
  ranks = {
    tiers = {
      { name = "Cadet", threshold = 0 },
      { name = "First Officer", threshold = 500 },
      { name = "Captain", threshold = 2500 },
      { name = "Senior Captain", threshold = 10000 },
      { name = "Chief Pilot", threshold = 25000 },
    },
    weights = {
      hours = 2.0,
      contracts = 1.0,
      tonnage = 0.01,
    },
  },
  srs = {
    enabled = false,
    dispatch_frequency_hz = 251000000,
    modulation = "AM",
    tone_file = "tone_new_dispatch.ogg",
    dispatch_files = {
      "dispatch_new_01.ogg",
      "dispatch_new_02.ogg",
    },
  },
  persistence = {
    save_dir = "Missions/Saves/skyfreight",
    autosave_interval_minutes = 15,
    crash_recovery_return_cargo = true,
    grace_minutes_after_crash = 15,
  },
  relocation = {
    enabled = false,
  },
  airfield_lock = {
    enabled = false,
  },
  economy = {
    enabled = false,
  },
  pax_capacity = {
    ["UH-1H"] = 8,
    ["Mi-8MT"] = 24,
    ["CH-47"] = 33,
    ["C-130"] = 92,
  },
  raffle = {
    enabled_tracking = true,
    enabled_draws = false,
    tickets_per_credits = 1000,
  },
  debug = {
    enabled = true,
    log_level = "info",
    single_player_ucid = "sp_test_pilot",
  },
}

return M
