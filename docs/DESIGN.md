# Skyfreight — Design Document

**A civilian logistics framework for DCS World, built Lua-first with optional Discord integration.**

Version: 0.2 (pre-implementation draft)
Status: Design phase — not yet implemented
Target platform: DCS World 2.9+

---

## Table of contents

1. [Overview](#1-overview)
2. [Terminology](#2-terminology)
3. [Architecture](#3-architecture)
4. [Lua module structure](#4-lua-module-structure)
5. [State model (Phase 0)](#5-state-model-phase-0)
6. [Database schema (Phase 1+)](#6-database-schema-phase-1)
7. [DCS event handler map](#7-dcs-event-handler-map)
8. [Contract lifecycle](#8-contract-lifecycle)
9. [Cargo spawning and detection](#9-cargo-spawning-and-detection)
10. [Passenger mechanics](#10-passenger-mechanics)
11. [F10 menu specification](#11-f10-menu-specification)
12. [Zone properties specification](#12-zone-properties-specification)
13. [Fleet management and airfield lock](#13-fleet-management-and-airfield-lock)
14. [Economy (Phase 2)](#14-economy-phase-2)
15. [Persistence](#15-persistence)
16. [SRS integration](#16-srs-integration)
17. [Rank and progression system](#17-rank-and-progression-system)
18. [Leaderboards and raffles](#18-leaderboards-and-raffles)
19. [Narrative generation](#19-narrative-generation)
20. [Discord integration (Phase 1+)](#20-discord-integration-phase-1)
21. [Configuration](#21-configuration)
22. [Development and deployment](#22-development-and-deployment)
23. [Phased roadmap](#23-phased-roadmap)
24. [Open threads and deferred decisions](#24-open-threads-and-deferred-decisions)

---

## 1. Overview

### 1.1 Mission statement

Skyfreight is a civilian logistics framework for DCS World multiplayer servers. It turns any DCS map into a living freight network where players transport cargo, passengers, and aircraft between airfields, earning credits and rank advancement. It is designed from day one as a reusable, map-agnostic framework so the same scripting model can later power a military logistics server.

### 1.2 Goals

- Provide meaningful civilian gameplay in DCS that scales from solo sessions to multi-crew operations.
- Persist player progression — credits, rank, hours, career statistics — across sessions.
- Be map-agnostic. A new `.miz` on a new map with zones authored correctly should work without code changes.
- Support both sling-loaded cargo (helicopters) and internal cargo (C-130, Chinook) with mixed aircraft crews on the same server.
- Build in Lua first. Keep external dependencies (including DCSServerBot) optional and behind abstractions so the framework can run standalone or augmented.

### 1.3 Non-goals

- **Combat.** Skyfreight is civilian. Hazard zones are parked for future design.
- **Coupling to other DCSServerBot plugins.** Skyfreight is deliberately independent of the Logistics plugin, CreditSystem plugin, SlotBlocking plugin, and any other feature plugins. Their internals may change; we want stability.
- **Full economic simulation in MVP.** Aircraft ownership, fuel pricing, and hangar fees are Phase 2. Phase 0 is pure score tracking.
- **A mission editor replacement.** Scenarios (`.miz` files) are still authored in the DCS Mission Editor.

### 1.4 Phase 0 scope (Lua-first MVP)

Everything runs in-mission. No Python plugin required. State persists via JSON files written through a `storage` abstraction. Discord integration comes in Phase 1.

**What ships in Phase 0:**

- Airfield-to-airfield cargo contracts (dynamic cargo — slung or internal based on what fits; warehouse-based for C-130 fuel/ammo transfers).
- Airfield-to-zone cargo contracts (construction sites, drop zones).
- Airfield-to-airfield passenger contracts with infantry-run pickup/drop mechanic.
- F10 radio menu as primary player interface.
- Contract pool with TTL-based expiration, generating every 15 minutes up to a configurable max of 20.
- Multi-pilot contracts via 4-digit join codes.
- Score tracking: credits earned, rank progression, contracts completed, hours flown, tonnage delivered.
- Persistent player state in JSON files: last airfield, career stats, rank, credits.
- Save/load on mission boundaries plus 15-minute autosave.
- SRS "new dispatch" audio cue when a new contract is available.
- In-game stats display via F10 "My Stats" popup.
- In-game leaderboard via F10 "Leaderboard" popup.

**What is NOT in Phase 0:**

- Discord anything.
- Database — all state is JSON files.
- Aircraft purchase and ownership.
- Fuel costs and hangar storage fees.
- Airfield lock mechanic.
- Hazard zones.
- Web dashboard.
- Cargo size/capacity matching across aircraft types.
- SRS audio beyond "new dispatch."
- Audio narrative briefings.
- Raffle draws.

### 1.5 Phase 1 and beyond

- **Phase 1:** add DCSServerBot plugin as a *light* integration layer — one plugin, one job, Discord I/O. Replaces JSON files with PostgreSQL for cross-session durability and cross-server stats. See §20.
- **Phase 2:** economy (aircraft ownership, fuel, storage, airfield lock, relocation).
- **Phase 3:** hazard zones, cargo capacity matching, squadron support, web dashboard, military variant.

---

## 2. Terminology

Consistent terms to avoid confusion:

| Term | Meaning |
|---|---|
| **Scenario** | A `.miz` file. The DCS mission file loaded by the server. |
| **Contract** | A single player-accepted task: pick up X, deliver to Y. Has an owner, optional crew, state, and payout. |
| **Job** | Synonym for contract. Used in player-facing text when "contract" feels too formal. |
| **Pool** | The set of currently available, unaccepted contracts on the server. |
| **Operation** | A group of contracts tied together by a shared 4-digit join code. One owner, multiple crew. |
| **Fleet** | The set of aircraft available at each airfield. Tracked per airfield, per airframe type, per server. |
| **Construction site** | A persistent zone defined in the scenario that accumulates crate deliveries over time across many contracts. |
| **Hub** | A major airfield with a warehouse, pax building, and generally more contract density. |
| **UCID** | DCS player Unique Client Identifier. Survives name changes, primary key for player data. |
| **Phase 0** | Lua-first standalone build. No Python, no bot, no DB. JSON file persistence. |
| **Phase 1** | Lua + light Python plugin for Discord integration and DB persistence. |

---

## 3. Architecture

### 3.1 Phase 0 architecture (Lua-only)

```
+-----------------------------------------------------------+
|  DCS World (Mission Scripting Engine)                     |
|                                                           |
|  Skyfreight Lua (loaded via .miz trigger "Do Script File")|
|  ├── core           — bootstrap, state, timers            |
|  ├── zones          — discovery, parsing                  |
|  ├── contracts      — pool, generation, lifecycle         |
|  ├── cargo          — spawn, track, detect delivery       |
|  ├── pax            — infantry run mechanic               |
|  ├── warehouses     — read/write/snapshot                 |
|  ├── menu           — F10 radio menu                      |
|  ├── events         — DCS event dispatcher                |
|  ├── narrative      — template composition                |
|  ├── srs            — dispatch audio                      |
|  ├── storage        — JSON read/write (abstraction)       |
|  ├── notify         — player-visible messages             |
|  ├── identity       — UCID / player resolution            |
|  └── credits        — balance tracking                    |
|                                                           |
|  Saved Games/DCS/Missions/Saves/skyfreight/               |
|    ├── players.json                                       |
|    ├── fleet.json                                         |
|    ├── warehouses.json                                    |
|    ├── construction.json                                  |
|    └── state.json   (active contracts, pool)              |
+-----------------------------------------------------------+
```

Everything runs in the mission scripting engine. `storage`, `notify`, `identity`, and `credits` are the four abstraction modules. In Phase 0, they do local/in-game things. In Phase 1, they route to the bot.

### 3.2 Phase 1+ architecture (Lua + light bot)

```
+-----------------------------------------------------------+
|  DCS World                                                |
|  Skyfreight Lua (unchanged from Phase 0)                  |
|                                                           |
|  abstraction modules now also route to bot:               |
|    storage.save() -> writes JSON locally AND calls        |
|                      dcsbot.sendMessage for DB write      |
|    notify.*      -> still outText, PLUS Discord embed     |
|    identity.*   -> pulls UCID from DCS (same as Phase 0)  |
|    credits.*    -> JSON authoritative, DB mirrored        |
+-----------------------------------------------------------+
                        |
                        | dcsbot.sendMessage (custom events)
                        v
+-----------------------------------------------------------+
|  DCSServerBot (infrastructure only — event bus)           |
|    plugins/skyfreight/                                    |
|    - Discord slash commands                               |
|    - PostgreSQL persistence                               |
|    - Nothing else                                         |
|    Does NOT depend on Logistics, CreditSystem, or         |
|    SlotBlocking plugins. Only on core bot infrastructure. |
+-----------------------------------------------------------+
```

**Why this design:** Lua remains authoritative for game state. The bot is a thin I/O layer for Discord and DB. If you ever remove the bot, Phase 0 still runs — nothing in the core Lua knows whether the bot exists.

### 3.3 Independence commitments

- **No dependency on Logistics plugin.** We use our own schema, our own F10 menu conventions, our own contract lifecycle.
- **No dependency on CreditSystem plugin.** We own `credits` in our JSON (Phase 0) or our DB table (Phase 1).
- **No dependency on SlotBlocking plugin.** Airfield lock (Phase 2) uses our own hook-side logic or dynamic slots.
- **Only depends on DCSServerBot core** (Phase 1+) — the event bus, command routing, UCID resolution. Not on any other feature plugins.

If SpecialK ships breaking changes to Logistics, CreditSystem, or SlotBlocking, Skyfreight is unaffected.

---

## 4. Lua module structure

### 4.1 File layout (inside the repo)

```
skyfreight/
├── lua/
│   ├── init.lua              -- entry point; loads all modules
│   ├── core.lua              -- state table, bootstrap, global namespace
│   ├── config.lua            -- config loader and defaults
│   ├── events.lua            -- DCS event handler dispatch
│   ├── timers.lua            -- scheduled function helpers
│   ├── zones.lua             -- zone discovery and parsing
│   ├── contracts.lua         -- pool, generation, lifecycle
│   ├── cargo.lua             -- cargo spawn, track, delivery detection
│   ├── pax.lua               -- passenger pickup and drop mechanics
│   ├── warehouses.lua        -- warehouse snapshot and restore
│   ├── menu.lua              -- F10 menu construction
│   ├── narrative.lua         -- template composition
│   ├── srs.lua               -- SRS audio integration
│   ├── rank.lua              -- rank tier calculation
│   ├── leaderboard.lua       -- in-game leaderboard
│   ├── storage.lua           -- JSON persistence abstraction
│   ├── notify.lua            -- player-visible message abstraction
│   ├── identity.lua          -- UCID / player resolution abstraction
│   ├── credits.lua           -- credit balance abstraction
│   ├── util.lua              -- shared helpers (math, tables, geo)
│   └── templates/
│       └── narratives.lua    -- narrative fragment pools
├── audio/
│   └── tone_new_dispatch.ogg, dispatch_new_XX.ogg, ...
├── scenarios/
│   └── examples/
│       └── skyfreight_caucasus_demo.miz
├── docs/
│   ├── DESIGN.md             -- this document
│   ├── DCS_LUA_GUIDELINES.md -- coding standards for DCS Lua
│   ├── AUTHORING_SCENARIOS.md
│   └── ADMIN_GUIDE.md
├── CLAUDE.md                 -- context file for Claude Code
└── README.md
```

### 4.2 Module conventions

Every module:

- Returns a table (never uses bare globals except the top-level `skyfreight` namespace).
- Declares its public API at the top; helpers below are local.
- Uses `env.info`, `env.warning`, `env.error` for logging (prefixed with `[skyfreight]`).
- Wraps external API calls in `pcall` when failure is recoverable.
- Does not call `io`, `os`, or `lfs` directly — only through `storage`.

Example:

```lua
-- lua/zones.lua
local M = {}

local discovered = {}

function M.discover() ... end
function M.get(name) ... end
function M.getByType(sf_type) ... end

return M
```

Loaded by:

```lua
-- lua/init.lua
skyfreight = skyfreight or {}
skyfreight.zones = require("skyfreight.zones")
-- ...
```

### 4.3 The four abstraction modules

These exist specifically to make Phase 0 → Phase 1 easy:

| Module | Phase 0 behavior | Phase 1 addition |
|---|---|---|
| `storage` | Read/write JSON files in Saved Games | Also sync to PostgreSQL via `dcsbot.sendMessage` |
| `notify` | `trigger.action.outText`, kneeboard pages | Also post Discord embeds |
| `identity` | DCS `getPlayerList()` / `getSlotInfo()` | Same (UCID is DCS-provided either way) |
| `credits` | Reads/writes local balance in state | Reads/writes to DB, JSON is cache |

**Rule:** nothing outside these four modules ever calls `io.*`, `lfs.*`, `dcsbot.*`, or `trigger.action.outText` directly. If a module needs to save, notify, identify, or bill, it goes through the abstraction. This is the single discipline that keeps the bot pluggable.

---

## 5. State model (Phase 0)

All state lives in a global Lua table, persisted to JSON on a cadence.

### 5.1 In-memory state shape

```lua
skyfreight.state = {
  version = "0.2.0",
  server_name = "civ_server_1",

  players = {
    -- keyed by UCID
    ["aabbcc1122"] = {
      ucid = "aabbcc1122",
      display_name = "Maverick",
      rank_tier = 0,                       -- 0..4
      credits = 1250,
      lifetime_hours = 12.5,
      lifetime_contracts = 8,
      lifetime_tonnage = 3200,             -- kg
      session_earnings = 450,
      last_airfield = "Kutaisi",
      last_airframe = "UH-1H",
      raffle_tickets = 1,
      first_seen_at = 1713720000,          -- unix
      last_seen_at = 1713810500,
    },
  },

  fleet = {
    -- keyed by "<airfield>|<airframe_type>"
    ["Kutaisi|UH-1H"] = {
      airfield = "Kutaisi",
      airframe_type = "UH-1H",
      count_available = 10,
      count_total = 10,
    },
  },

  warehouses = {
    -- keyed by airfield name, raw inventory snapshot from DCS
    ["Kutaisi"] = {
      weapons = { ["FAB-250"] = 200 },
      liquids = { jet_fuel = 500000, diesel = 100000 },
      aircraft = { ["UH-1H"] = 10 },
    },
  },

  contracts = {
    -- keyed by contract_id
    [4412] = {
      contract_id = 4412,
      status = "in_flight",                -- pool, accepted, crewed, in_flight, delivered, cancelled, expired
      contract_type = "cargo",             -- cargo, pax, warehouse_fuel, warehouse_ammo, ferry
      source_name = "Batumi",
      source_position = { x = -355145.3, y = 0, z = 617233.8 },
      destination_name = "Kutaisi",
      destination_type = "airfield",       -- airfield, construction_site, drop_zone, farp
      destination_position = { x = -285678.1, y = 0, z = 682901.2 },
      destination_zone_name = nil,         -- for zone-type destinations
      cargo_spec = {
        count = 4,
        items = {
          { type = "iso_container", count = 2, weight_kg = 1500 },
          { type = "ammo_crate",    count = 2, weight_kg = 600 },
        },
        total_weight_kg = 2100,
        description = "Mixed freight — containers and crates",
        pax_count = 0,                     -- for pax contracts
      },
      owner_ucid = "aabbcc1122",
      crew = {
        -- keyed by UCID
        ["aabbcc1122"] = { role = "owner",  joined_at = 1713810500, crates_delivered = 0, earned = 0 },
        ["ddeeff3344"] = { role = "crew",   joined_at = 1713810600, crates_delivered = 1, earned = 0 },
      },
      join_code = "4412",
      base_payout = 2400,
      priority = 0,                        -- 0 routine, 1 high, 2 urgent
      narrative = "Dispatch reports...",
      ttl_hours = 2.0,
      created_at = 1713810000,
      accepted_at = 1713810500,
      expires_at = 1713817200,
      completed_at = nil,
    },
  },

  cargo_registry = {
    -- keyed by cargo static name
    ["Batumi_Kutaisi_4412_1"] = {
      cargo_name = "Batumi_Kutaisi_4412_1",
      contract_id = 4412,
      crate_index = 1,
      carriage = "slung",                  -- slung | internal (by cargo dimensions)
      cargo_type = "iso_container",
      weight_kg = 1500,
      spawn_position = { x = -355140.0, y = 0, z = 617230.0 },
      status = "in_flight",                -- spawned, loaded, in_flight, delivered, destroyed
      carrier_ucid = "aabbcc1122",
    },
  },

  zones = {
    -- keyed by zone name; populated at scenario start
    ["Gori_BridgeConstruction_Alpha"] = {
      zone_name = "Gori_BridgeConstruction_Alpha",
      sf_type = "construction_site",
      center = { x = -234567.0, y = 0, z = 678901.0 },
      radius = 250,
      properties = {
        crates_required = 20,
        cargo_types = { "crates", "pipes", "logs" },
        priority = "routine",
        narrative_tags = { "civilian", "industrial" },
      },
    },
  },

  construction_sites = {
    -- keyed by zone name
    ["Gori_BridgeConstruction_Alpha"] = {
      zone_name = "Gori_BridgeConstruction_Alpha",
      crates_required = 20,
      crates_delivered = 7,
      status = "active",                   -- active, completed
      completed_at = nil,
      contributions = {
        -- keyed by UCID
        ["aabbcc1122"] = 4,
        ["ddeeff3344"] = 3,
      },
    },
  },

  pool_meta = {
    max_contracts = 20,
    generation_interval_s = 900,           -- 15 minutes
    last_generation_at = 1713810000,
  },

  session = {
    mission_started_at = 1713810000,
    last_autosave_at = 1713810000,
  },
}
```

### 5.2 JSON files on disk

State is persisted to `Saved Games/DCS/Missions/Saves/skyfreight/` (or configurable). Files:

| File | Contents | Write cadence |
|---|---|---|
| `players.json` | The `players` table | On any player field change + every autosave |
| `fleet.json` | The `fleet` table | On ferry delivery + every autosave |
| `warehouses.json` | The `warehouses` table | On warehouse change + every autosave |
| `construction.json` | The `construction_sites` table | On crate delivery to site + every autosave |
| `contracts.json` | `contracts`, `cargo_registry`, `pool_meta` | Every autosave + state transitions |
| `meta.json` | Version info, last save, checksum | Every autosave |

Files are split so we can write only what changed (a 50kb players.json is cheaper than a 500kb state.json on every change).

### 5.3 JSON write strategy

To avoid corrupting files if DCS crashes mid-write:

1. Serialize state to a temp file: `players.json.tmp`.
2. `os.rename` to `players.json` (atomic on POSIX, best-effort on Windows).
3. If rename fails, log warning but don't crash — state is still in memory.

On load at mission start:
1. Read each JSON file.
2. Validate version and checksum.
3. If corrupted, fall back to `*.bak` if present; else start fresh with a loud warning.
4. Always write a `*.bak` before overwriting.

---

## 6. Database schema (Phase 1+)

**Phase 0 does not use a database.** This section is forward-looking, for Phase 1 implementation.

All tables live in the DCSServerBot PostgreSQL database under a `skyfreight_` prefix.

### 6.1 Player state

```sql
CREATE TABLE skyfreight_players (
    ucid              TEXT PRIMARY KEY,
    display_name      TEXT,
    rank_tier         INTEGER DEFAULT 0,
    credits           INTEGER DEFAULT 0,
    lifetime_hours    NUMERIC(10,2) DEFAULT 0,
    lifetime_contracts INTEGER DEFAULT 0,
    lifetime_tonnage  NUMERIC(12,2) DEFAULT 0,
    last_airfield     TEXT,
    last_airframe     TEXT,
    session_earnings  INTEGER DEFAULT 0,
    raffle_tickets    INTEGER DEFAULT 0,
    first_seen_at     TIMESTAMPTZ DEFAULT NOW(),
    last_seen_at      TIMESTAMPTZ DEFAULT NOW()
);
```

Note: `credits` lives here. We do NOT depend on the CreditSystem plugin.

### 6.2 Fleet, warehouses, contracts, cargo, construction sites

(Same as earlier draft — all with `skyfreight_` prefix, all owned by us, no foreign keys into other plugins' tables. See previous draft §4.2–§4.7 for schema details; they carry forward unchanged except for removal of CreditSystem references.)

### 6.3 Economy tables (Phase 2)

```sql
CREATE TABLE skyfreight_aircraft_ownership (
    ownership_id      SERIAL PRIMARY KEY,
    ucid              TEXT NOT NULL,
    airframe_type     TEXT NOT NULL,
    home_airfield     TEXT NOT NULL,
    current_location  TEXT NOT NULL,
    storage_prepaid_until TIMESTAMPTZ,
    status            TEXT NOT NULL,
    purchased_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE skyfreight_transactions (
    txn_id            SERIAL PRIMARY KEY,
    ucid              TEXT NOT NULL,
    txn_type          TEXT NOT NULL,
    amount            INTEGER NOT NULL,
    related_contract_id INTEGER,
    related_ownership_id INTEGER,
    notes             TEXT,
    created_at        TIMESTAMPTZ DEFAULT NOW()
);
```

### 6.4 Leaderboard views

Materialized views for Discord `/leaderboard` responses, refreshed periodically.

---

## 7. DCS event handler map

| Event | Used for | Action |
|---|---|---|
| `S_EVENT_BIRTH` | Player spawns into aircraft | Track current slot; prepare for session |
| `S_EVENT_TAKEOFF` | Departure logging | Update player state to `in_flight` |
| `S_EVENT_LAND` | Delivery detection (part) | Check destination zone proximity |
| `S_EVENT_ENGINE_SHUTDOWN` | Finalize airfield assignment | Update `last_airfield` only if landed at an airfield with engines off |
| `S_EVENT_DYNAMIC_CARGO_LOADED` | Chinook cargo load | Update `cargo_registry.status = loaded` |
| `S_EVENT_DYNAMIC_CARGO_UNLOADED` | Chinook cargo unload | If inside destination zone, trigger delivery |
| `S_EVENT_NEW_DYNAMIC_CARGO` | Ground-crew cargo spawn | Log; do not auto-associate |
| `S_EVENT_DYNAMIC_CARGO_REMOVED` | Cleanup notification | Update cargo status |
| `S_EVENT_UNIT_LOST` / `S_EVENT_DEAD` | Cargo or pax destruction | Cancel contract, no penalty |
| `S_EVENT_EJECTION` | Pilot ejection mid-contract | Cancel contract, despawn cargo, no penalty |
| `S_EVENT_CRASH` | Aircraft crash | Same as ejection |
| `S_EVENT_PLAYER_LEAVE_UNIT` | Player disconnects mid-flight | Save state; 15-min grace for reconnection |
| `onPlayerTryChangeSlot` (hook, Phase 2) | Airfield lock | Deny slot if last airfield mismatches |

### 7.1 Proximity polling as backstop

All cargo fires `S_EVENT_DYNAMIC_CARGO_*` events as the primary detection mechanism. Proximity polling runs every 2 seconds as a backstop for edge cases:

- Cargo destroyed off-map or in ways that don't fire `UNIT_LOST` — polling notices the static is gone.
- Cargo unloaded outside a destination zone (e.g., dropped during flight, landed short) — polling tracks position.
- Cargo that lands near but not inside a destination zone — polling can detect "close enough" with configurable tolerance.

For each tracked cargo, the poll:
- Checks if the static exists. If not → cancel contract (cargo destroyed).
- Checks position against destination zone. If inside and landed (vertical speed ≈ 0, position stable over 2 polls) without an event having fired → trigger delivery anyway.

Event-driven is the happy path; polling catches what events miss.

### 7.2 F10 command-driven checks

Events we do NOT poll — we wait for F10 command:
- Door state (for pax operations). When the player clicks "Load Passengers" via F10, we check door open state at that moment. No polling.
- Manual delivery fallback. `-deliver` chat command or F10 "Mark Delivered" runs the delivery checks on demand.

---

## 8. Contract lifecycle

### 8.1 States

```
   generated
      |
      v
   +------+        +---------+
   | POOL |------->| EXPIRED |
   +------+        +---------+
      |
      | F10 accept
      v
  +----------+
  | ACCEPTED |---+
  +----------+   |
      |         join code
      |          |
      v          v
  +----------+   +--------+
  |  CREWED  |<--+        |
  +----------+            |
      |                   |
      v                   |
  +-----------+           |
  | IN_FLIGHT |<----------+
  +-----------+
     /     \
    v       v
+----------+ +-----------+
|DELIVERED | | CANCELLED |
+----------+ +-----------+
```

### 8.2 TTLs by type

| Contract type | Default TTL |
|---|---|
| Routine cargo | 2 hours |
| Passenger service | 2 hours |
| Construction site crate | 6 hours |
| Large warehouse delivery (C-130) | 24 hours |
| Urgent priority | 30 minutes (with payout bonus) |

Configurable per-contract.

### 8.3 Payout rules

- Owner (first-to-accept) receives **100%** of base payout.
- Each non-owner crew member who delivered at least one crate receives **40%** of base payout (their own bonus, not a share).
- Total payout can exceed 100% when crewed up — deliberately incentivizes teamwork.
- No proportional splits in Phase 0. You delivered something or you didn't.

### 8.4 Abandonment (no penalties in Phase 0)

- Owner abandons → contract cancels, cargo despawns, crew notified, no credit penalty.
- Crew member leaves → slot opens, contract continues, no penalty.
- Owner disconnects → 15-minute grace, then cancel if not reconnected.
- Scenario restart mid-flight → cargo/pax return to pickup airfield; contract stays with owner; TTL extended by grace period.

---

## 9. Cargo spawning and detection

### 9.1 Cargo kinds

All physical cargo uses the DCS dynamic cargo system, regardless of aircraft. Whether a given crate is carried internally or slung is determined by cargo dimensions and the aircraft's cabin space — not by which cargo system is in play.

| Carriage | Compatible aircraft | Determined by | Detection |
|---|---|---|---|
| Internal (stowed in cabin) | All helicopters, CH-47, C-130 | Cargo fits in cabin | `S_EVENT_DYNAMIC_CARGO_*` events |
| Slung (external hook) | All helicopters | Cargo too large for any cabin | `S_EVENT_DYNAMIC_CARGO_*` events |
| Warehouse (abstract, no physical cargo) | C-130 | Fuel, ammo, weapons — bulk transfers | Warehouse delta at delivery |

Examples:
- `PIPESLONG`, `SEACAN`, `OILBARREL_LARGE` are too large for helicopter cabins → slung.
- `CRATE_SMALL`, `FUEL_DRUMS_PALLET`, `MED_SUPPLIES` fit internally → stowed.
- Fuel/ammo/weapons bulk transfers via C-130 have no physical cargo — only a warehouse delta.

The cargo's `carriage` field in state is informational (for narrative and payout weighting); code paths do not branch on it. Detection is unified.

### 9.2 Spawn timing

Cargo for active contracts is **pre-spawned at the source airfield** on contract creation (not acceptance). It sits visibly, waiting. Rationale:

- Pilots see the cargo before accepting — visual confirmation of the job.
- No "cargo spawning inside player" edge cases.
- Simpler UX — no F10 "Spawn Cargo" step.

If a contract expires unaccepted, cargo despawns.

### 9.3 Naming convention

```
<source>_<destination>_<contract_id>_<crate_index>
```

Example: `Batumi_Kutaisi_4412_1`, `Batumi_Kutaisi_4412_2`. Human-readable in logs, queryable in state.

### 9.4 Sling / internal detection

All physical cargo fires `S_EVENT_DYNAMIC_CARGO_LOADED` and `S_EVENT_DYNAMIC_CARGO_UNLOADED`. The handler:

1. Looks up the cargo in `state.cargo_registry` by name.
2. On load event: marks cargo as `loaded`, records carrier UCID.
3. On unload event: if the unload position is inside the contract's destination zone, triggers delivery.

Proximity polling (§7.1) runs as a backstop — it catches destruction, out-of-zone drops, and rare event misfires, but is not the primary path.

### 9.5 C-130 warehouse delivery

No physical cargo. Source warehouse decrements on acceptance, destination warehouse increments on delivery, refund on cancellation.

### 9.6 Airdrop to zone

Same as airfield contracts — cargo pre-spawned at source, pilot loads (internal or sling), drops over drop zone. Delivery detection uses cargo-in-zone + velocity-stable (parachute or ground landing). If cargo destroyed on impact, contract cancels.

### 9.7 Destruction handling

Static destroyed → cancel contract (no penalty). Remaining crates stay active — partial delivery is possible if only one of four crates is destroyed; the other three can still complete.

---

## 10. Passenger mechanics

### 10.1 Representation

Passengers are an infantry group spawned near a building in a defined pickup zone. When loaded, they despawn (counter on contract). At destination, they respawn and run to a building inside the destination zone.

### 10.2 Pickup flow

1. Contract accepted by owner.
2. Infantry group spawns at pickup building inside source zone.
3. Pilot lands within pickup zone, shuts down engines (helicopter) or opens cargo ramp (C-130).
4. Pilot clicks F10 "Load Passengers".
5. **At this moment**, we check: is the aircraft in the zone? Is it on the ground? Is the cargo door open (C-130) or engine off (heli)?
6. If all checks pass, infantry group receives "move to aircraft" task.
7. When infantry reach proximity of aircraft (~15m), they despawn. Contract `pax_loaded` counter increments.

**Door state is checked only at this moment, not polled.** The F10 click is the trigger.

### 10.3 Drop flow

Mirror of pickup:

1. Pilot lands within destination zone, engines off / ramp open.
2. Pilot clicks F10 "Unload Passengers".
3. Checks run: in zone, on ground, door state.
4. Infantry spawns at aircraft ramp, receives "move to destination building" task.
5. When infantry reach proximity of destination building, they despawn. Contract is credited as delivered.

### 10.4 Pax capacities (Phase 0 defaults)

| Airframe | Pax capacity |
|---|---|
| UH-1H | 8 |
| Mi-8MT | 24 |
| CH-47 | 33 |
| C-130 | 92 |

Configurable. A contract's `pax_count` may exceed a single aircraft's capacity; delivery requires multiple runs until all pax are delivered. Phase 2 may add minimum-capacity contract requirements.

---

## 11. F10 menu specification

```
Skyfreight/
├── My Current Contract      (popup detail)
├── View Available Contracts (paginated list popup)
├── Accept Contract >
│   ├── Page 1 >
│   │   ├── #4412 URGENT  Med Supplies  Batumi→Kutaisi  $2,400
│   │   ├── #4413          PAX 12       Kobuleti→Senaki $1,800
│   │   └── ...
│   └── Page 2 >
├── Join Contract (by code) >
│   ├── Digit 1 > (0-9 submenu)
│   ├── Digit 2 > (0-9)
│   ├── Digit 3 > (0-9)
│   ├── Digit 4 > (0-9)
│   └── Submit
├── Load Passengers         (active only if in pickup zone, on ground)
├── Unload Passengers       (active only if in destination zone, on ground)
├── Mark Delivered          (manual cargo fallback)
├── Abandon Contract        (confirmation)
├── My Stats                (popup — credits, rank, hours, session)
├── Leaderboard             (popup — top 10)
└── Debug >
    ├── Refresh Menu
    ├── Force State Sync
    └── Report Stuck Cargo
```

### 11.1 Chat command equivalents

| Chat command | Action |
|---|---|
| `-contracts` | List available |
| `-accept <id>` | Accept specific |
| `-join <code>` | Join by 4-digit code |
| `-mycontract` | Show current |
| `-deliver` | Manual deliver |
| `-abandon` | Abandon |
| `-loadpax` / `-unloadpax` | Pax ops |
| `-stats` | My stats |
| `-leaderboard` | Top 10 |

### 11.2 Popup formatting

```
+-- Skyfreight Contracts (5 available) ------------+
| #4412 URGENT                                     |
|   Batumi → Kutaisi (34 nm)                       |
|   4x Medical Supplies (600 kg)                   |
|   Payout: $2,400 | Expires: 0:27                 |
|                                                  |
| #4413                                            |
|   Kobuleti → Senaki (22 nm)                      |
|   12 Passengers                                  |
|   Payout: $1,800 | Expires: 1:45                 |
+--------------------------------------------------+
```

---

## 12. Zone properties specification

### 12.1 Zone property schema

| Property | Required for | Values | Notes |
|---|---|---|---|
| `skyfreight_type` | All Skyfreight zones | `hub`, `pickup_building`, `dropoff_building`, `construction_site`, `drop_zone`, `farp_resupply` | Primary routing key |
| `crates_required` | `construction_site` | Integer | Total crates to complete |
| `cargo_types` | `construction_site`, `drop_zone` | Comma-separated: `crates,fuel_drums,pipes,logs,seacans` | Constrains contract generation |
| `priority` | All | `routine`, `high`, `urgent` | Affects TTL and payout |
| `narrative_tags` | All | Comma-separated: `civilian,medical,industrial,military,remote` | Feeds narrative |
| `pax_capacity_building` | Pax buildings | Integer | Building concurrency |
| `source_weight` | `hub` | 0..10 | Higher = more contracts originate here |

### 12.2 Example zones

**Hub:**
```
Zone name: Kutaisi_Hub
Properties:
  skyfreight_type = hub
  priority = routine
  narrative_tags = civilian,commercial
  source_weight = 8
```

**Construction site:**
```
Zone name: Gori_BridgeConstruction_Alpha
Properties:
  skyfreight_type = construction_site
  crates_required = 20
  cargo_types = crates,pipes,logs
  priority = routine
  narrative_tags = civilian,industrial
```

**Pax pickup building:**
```
Zone name: Batumi_Terminal_A
Properties:
  skyfreight_type = pickup_building
  pax_capacity_building = 40
  narrative_tags = civilian
```

### 12.3 Discovery

On mission start, `zones.lua` iterates all trigger zones, parses `skyfreight_type` and related properties, populates `skyfreight.state.zones`.

---

## 13. Fleet management and airfield lock

### 13.1 Fleet initialization

On first scenario load, fleet is read from the `.miz` warehouse values (scenario author's day-zero state). Subsequent loads use the persisted JSON values and restore them to warehouses.

### 13.2 Ferry contracts

Move an airframe from source to destination. On delivery, `count_total` decrements at source and increments at destination. On abandonment or crash, the airframe is lost — `count_total` decrements at source with no increment elsewhere.

### 13.3 Airfield lock (Phase 2, not active in Phase 0)

Player can only spawn an airframe at the airfield where they last landed and shut down. Deviations require relocation.

Enforcement in Phase 2:
- Primary: dynamic slots, deny spawn if home airfield mismatches.
- Fallback: post-spawn kick-to-spectator with explanation popup.

### 13.4 Relocation (Phase 2)

- **Tier 1: Instant self-relocation** — F10 or chat `-relocate <airfield>`. Cost: `base_fee + distance_nm * per_nm`. Updates `last_airfield` immediately.
- **Tier 2: Player-pickup** — creates a pickup contract for another pilot. Stranded player pays that contract's payout on delivery.

Schema and config live in Phase 0, logic activates in Phase 2.

---

## 14. Economy (Phase 2)

### 14.1 Credit ownership

Credits live in `skyfreight_players.credits` (Phase 1 DB) or `state.players[ucid].credits` (Phase 0 JSON). **We do not use DCSServerBot's CreditSystem.** Our credits are our own. If we ever want Discord role automation based on credits, we build that in our own Python plugin — not through a third-party plugin's achievements feature.

### 14.2 Planned spending surfaces (Phase 2)

- Relocation fees (Tier 1 and Tier 2).
- Aircraft purchase (via dynamic slots).
- Fuel costs on refuel.
- Hangar storage at non-home airfields.
- Cargo insurance (Phase 3 stretch).

### 14.3 Aircraft ownership sketch

1. Player buys an airframe type tied to a home airfield.
2. Dynamic slot at home airfield shows their aircraft.
3. Flies somewhere, lands, shuts down — aircraft parked at non-home airfield.
4. Daily storage fees tick against balance. If unpaid long enough, airframe is impounded.
5. Storage can be pre-paid.

### 14.4 Revenue split when economy active

When fuel costs exist, each crew member has overhead. Adjust split — owner 100%, crew 100% each (not 40%) — so crew can cover their own fuel. Revisit numbers during Phase 2 tuning.

---

## 15. Persistence

### 15.1 What gets saved

- Player state (including credits) — `players.json`
- Fleet per airfield — `fleet.json`
- Warehouse inventories — `warehouses.json`
- Construction progress — `construction.json`
- Active contracts, cargo, pool — `contracts.json`
- Session meta — `meta.json`

### 15.2 Save triggers

| Trigger | What saves |
|---|---|
| Scenario start | Nothing out; state is LOADED from disk |
| Contract state transition | Just `contracts.json` |
| Delivery | `contracts.json`, `players.json`, `fleet.json`, `warehouses.json` |
| Mission end (graceful) | Full snapshot |
| 15-min autosave | Full snapshot |
| Admin command | Full snapshot |

### 15.3 Crash recovery

If scenario ends abnormally:
1. Next scenario load reads last autosave.
2. Contracts in `in_flight` status at autosave time:
   - Cargo respawns at pickup airfield.
   - Pax respawns at pickup building.
   - Contract returns to `accepted` state with owner preserved.
   - TTL extended by grace period.
3. Owner gets notification: "Your contract #4412 was interrupted. Cargo returned to Batumi."
4. No credit penalty.

### 15.4 Warehouse restoration at scenario start

DCS re-initializes warehouses from `.miz` on every scenario load. We override:

```
for each airbase:
  wh = airbase:getWarehouse()
  for each item in wh.inventory:
    wh:setItem(item, 0)          -- clear
  for each item in saved_state:
    wh:setItem(item, count)      -- replay
```

Runs at mission start with a short delay to let DCS finish its own init.

---

## 16. SRS integration

### 16.1 Phase 0 scope

Single trigger: **new contract generated**.

1. Tone file plays on configured frequency.
2. After tone, a randomly-selected dispatch audio file plays.
3. Players on-frequency hear "New dispatch available" announcement.
4. Contract simultaneously appears in F10 menu and chat.

### 16.2 Audio file layout

```
audio/
├── tone_new_dispatch.ogg
├── dispatch_new_01.ogg
├── dispatch_new_02.ogg
├── dispatch_new_03.ogg
└── ...
```

Config:

```
srs:
  enabled: true
  dispatch_frequency_hz: 251000000
  modulation: AM
  tone_file: tone_new_dispatch.ogg
  dispatch_files:
    - dispatch_new_01.ogg
    - dispatch_new_02.ogg
```

### 16.3 Future triggers (deferred)

- Contract delivered.
- Construction site completed.
- Server restart warnings.

---

## 17. Rank and progression system

### 17.1 Tiers

```
0 — Cadet
1 — First Officer
2 — Captain
3 — Senior Captain
4 — Chief Pilot
```

### 17.2 Advancement formula

```
score = (hours * weight_hours) + (contracts * weight_contracts) + (tonnage * weight_tonnage)
```

Default weights (configurable): `hours=2.0, contracts=1.0, tonnage=0.01`.

Thresholds (configurable): Cadet=0, FO=500, Capt=2500, SrCapt=10000, ChiefPilot=25000.

### 17.3 Phase 0 rank display

Shown in F10 "My Stats" popup. Discord role mapping is Phase 1+ and is handled in our own plugin — not via CreditSystem achievements.

### 17.4 Rank does not gate contracts in Phase 0

All players can accept all contracts. Phase 2 may add rank-gated high-tier contracts.

---

## 18. Leaderboards and raffles

### 18.1 Phase 0 leaderboards

In-game only, via F10 "Leaderboard" popup:

```
+-- Skyfreight Leaderboard (this session) ---------+
|  1. Maverick         $4,800   (8 contracts)      |
|  2. Goose            $3,200   (5 contracts)      |
|  ...                                             |
+--------------------------------------------------+
```

Two views (cycle via F10 submenu):
- Current session.
- All-time (from persistent state).

### 18.2 Phase 1 leaderboards

Add Discord slash commands:
- `/skyfreight leaderboard [season|alltime] [metric]`
- Seasonal resets monthly.
- Multiple sort columns: earnings, contracts, hours, tonnage.

### 18.3 Raffle (tracked in Phase 0, drawn in Phase 2)

`state.players[ucid].raffle_tickets` accumulates according to rules (default: 1 per 1000 credits earned). No draws in Phase 0. Phase 2 adds draw mechanics.

---

## 19. Narrative generation

### 19.1 Template structure (mad-libs)

```
-- lua/templates/narratives.lua
return {
  openings = {
    routine = {
      "Dispatch reports a routine {cargo_type} shipment needs transport.",
      "{source_region} has a {cargo_type} order ready for pickup.",
    },
    urgent = {
      "URGENT — {destination} urgently needs {cargo_type}.",
    },
  },
  middles = {
    civilian = {
      "This is a civilian contract; expect no hostile activity en route.",
    },
  },
  sign_offs = {
    routine = {
      "Standard payout on delivery. Safe flying.",
    },
    urgent = {
      "Bonus payout for fast delivery. Don't waste time.",
    },
  },
}
```

### 19.2 Composition

At contract generation:
1. Select one opening (by priority).
2. Select zero or more middles (by zone `narrative_tags`).
3. Select one sign-off (by priority).
4. Substitute variables.

### 19.3 Audio narrative (Phase 2)

Schema supports `audio_file` on narratives; no playback in Phase 0.

---

## 20. Discord integration (Phase 1+)

### 20.1 Goals for Phase 1

Provide Discord as an additional I/O channel. Stay light on bot plugins — use only core DCSServerBot infrastructure:
- Event bus (receive mission events).
- Command routing (slash commands).
- UCID resolution (built into bot core).

Do NOT depend on: Logistics, CreditSystem, SlotBlocking, or any other feature plugin.

### 20.2 Phase 1 player slash commands

| Command | Description |
|---|---|
| `/skyfreight stats [player]` | Show stats |
| `/skyfreight contracts [server]` | List available |
| `/skyfreight mycontract` | Show active |
| `/skyfreight leaderboard [season\|alltime] [metric]` | Ranked list |
| `/skyfreight join <code>` | Join an operation |
| `/skyfreight rank [player]` | Rank and next threshold |
| `/skyfreight fleet [airfield]` | Fleet at airfield |
| `/skyfreight history [player] [limit]` | Contract history |

### 20.3 Phase 1 admin slash commands

| Command | Description |
|---|---|
| `/skyfreight save` | Force save |
| `/skyfreight reload` | Force state sync |
| `/skyfreight generate <type>` | Force-generate contract |
| `/skyfreight cancel <contract_id>` | Admin-cancel |
| `/skyfreight reset_player <player>` | Reset stats |
| `/skyfreight set_airfield <player> <airfield>` | Override last airfield |

### 20.4 Status channel (optional)

Auto-posting channel for:
- New contracts (color-coded by priority).
- Completed contracts with payout summary.
- Construction site progress.
- Leaderboard changes.

### 20.5 DB migration from JSON

When Phase 1 goes live, existing JSON state is imported into PostgreSQL on first bot startup. Migration script reads JSON, upserts to tables. JSON files become a local cache/fallback.

---

## 21. Configuration

### 21.1 Config file format

Lua table for Phase 0 (simple, no YAML parser in-sandbox by default):

```lua
-- Saved Games/DCS/Missions/Saves/skyfreight/config.lua
return {
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
    priority_multipliers = { routine = 1.0, high = 1.3, urgent = 1.6 },
  },
  ranks = {
    tiers = {
      { name = "Cadet",          threshold = 0 },
      { name = "First Officer",  threshold = 500 },
      { name = "Captain",        threshold = 2500 },
      { name = "Senior Captain", threshold = 10000 },
      { name = "Chief Pilot",    threshold = 25000 },
    },
    weights = { hours = 2.0, contracts = 1.0, tonnage = 0.01 },
  },
  srs = {
    enabled = false,
    dispatch_frequency_hz = 251000000,
    modulation = "AM",
    tone_file = "tone_new_dispatch.ogg",
    dispatch_files = { "dispatch_new_01.ogg", "dispatch_new_02.ogg" },
  },
  persistence = {
    save_dir = "Missions/Saves/skyfreight",
    autosave_interval_minutes = 15,
    crash_recovery_return_cargo = true,
    grace_minutes_after_crash = 15,
  },
  relocation = { enabled = false },
  airfield_lock = { enabled = false },
  economy = { enabled = false },
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
    enabled = false,
    log_level = "info",          -- debug, info, warning, error
  },
}
```

### 21.2 Phase 1 adds

YAML config for the DCSServerBot plugin side. Lua config remains authoritative for in-mission behavior; bot YAML handles Discord channel IDs, DB connection, etc.

---

## 22. Development and deployment

### 22.1 Repo layout

(As shown in §4.1.)

### 22.2 Dev workflow

1. Clone repo on local dev machine.
2. Write Lua in your editor.
3. Test locally: run a DCS server with a test `.miz` that loads `skyfreight/lua/init.lua`.
4. Fly, log, iterate.
5. Git commit, push.
6. Copy to production server when stable.

### 22.3 Loading Skyfreight into a .miz

The scenario author adds a single "Do Script File" trigger at mission start that loads `skyfreight/lua/init.lua`:

```lua
-- in a "Do Script File" trigger, pointing to:
-- <path_to_skyfreight_repo>/lua/init.lua
```

All other modules are loaded by `init.lua`.

### 22.4 Scenario authoring guide

1. Build scenario normally.
2. Place trigger zones for hubs, construction sites, drop zones, pax buildings.
3. Set zone properties per §12.
4. Set warehouse inventories at airfields (day-zero fleet and materiel).
5. Add a Do Script File trigger loading `skyfreight/lua/init.lua`.
6. Save.

### 22.5 Testing strategy

- **Minimal smoke scenario** (`scenarios/examples/skyfreight_caucasus_demo.miz`): one hub, one destination, one construction site, one pax building. Tests every module in isolation.
- **In-mission debug menu** (under F10 Skyfreight/Debug): dump state, force events, report stuck cargo.
- **Log-level config**: `debug.log_level` controls verbosity in `dcs.log`.

---

## 23. Phased roadmap

### Phase 0 — Lua-first MVP

Build order (suggested):

1. Module skeleton (`init.lua`, `core.lua`, `util.lua`, empty modules returning empty tables).
2. `storage.lua` — JSON read/write.
3. `identity.lua` — UCID resolution.
4. `notify.lua` — outText wrapper.
5. `credits.lua` — local balance.
6. `zones.lua` — discovery at mission start.
7. `warehouses.lua` — read/write/snapshot/restore.
8. `menu.lua` — F10 scaffold with accept-only first.
9. `contracts.lua` — one contract type, airfield-to-airfield.
10. `cargo.lua` — static spawn, proximity-poll delivery.
11. Payout on delivery.
12. Autosave loop.
13. Crash recovery.
14. Additional contract types (pax, construction, warehouse).
15. Join codes.
16. `rank.lua`.
17. `leaderboard.lua`.
18. `srs.lua` — dispatch audio.
19. `narrative.lua` — template composition.
20. Polish, error handling, docs.

### Phase 1 — Discord + DB

- Add DCSServerBot Python plugin (`skyfreight-plugin`).
- Lua abstraction modules learn to route to bot.
- PostgreSQL migration from JSON.
- Discord slash commands.
- Status channel embeds.

### Phase 2 — Economy

- Aircraft ownership via dynamic slots.
- Fuel costs.
- Hangar storage.
- Airfield lock + relocation.
- Revenue split adjustment.
- Raffle draws.
- Rank-gated contracts.
- Audio narrative per contract.

### Phase 3 — Stretch

- Hazard zones (separate design session).
- Cargo capacity matching.
- Seasonal tournaments.
- Cargo insurance.
- Squadron support.
- Web dashboard.
- Military variant (Milfreight) as a fork.

---

## 24. Open threads and deferred decisions

**24.1 Hazard zones.** Entire system deferred.

**24.2 Cargo size / weight / aircraft capacity matching.** Phase 3 side project.

**24.3 Web dashboard.** Phase 3.

**24.4 Dynamic slots fallback.** Phase 2 dependency on dynamic slots; fallback for servers that prefer pre-placed slots undecided.

**24.5 Economy balancing.** Placeholder numbers in config; needs playtesting.

**24.6 Weather-affected contracts.** Dynamic weather response not feasible without restart. Scenario-load weather modifiers possible in Phase 2.

**24.7 Fleet replenishment.** Ferry contracts drain source airfields. How do they refill? Admin command, scheduled restock, passive regeneration — undecided.

**24.8 Ground-crew F8 cargo menu.** Ground crew can spawn cargo we don't know about. Phase 0 logs but ignores. Phase 2+ may register "found cargo" toward contracts or restrict F8.

**24.9 Partial delivery payout math.** 4-crate contract, 1 destroyed, 3 delivered — what payout? Needs spec. Phase 0 may just pay the owner `3/4 * base_payout` and call it done.

**24.10 Discord role automation in Phase 1.** Without CreditSystem's achievements feature, we'll build rank-role mapping ourselves in the Python plugin.

**24.11 Pax capacity across multiple aircraft types.** If a 30-pax contract requires 4 Huey trips, does that feel right? Capacity-scaling may need adjustment during playtest.

---

**End of document.**
