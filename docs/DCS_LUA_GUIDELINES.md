# DCS Lua Guidelines

**A reference for writing DCS World mission Lua correctly. This document is for Claude Code (and any human developer) working on Skyfreight.**

Read this before writing any Lua. DCS Lua has several traits that differ from standard Lua and from most Lua tutorials you'll find online.

---

## 1. Environment facts

- **Lua version: 5.1** (not 5.3, not 5.4, not LuaJIT-visible features).
- **No integer type.** All numbers are IEEE 754 doubles.
- **No `goto`.** Lua 5.1 doesn't support it.
- **No `bit32` by default.** If you need bitwise, use `bit.band`, `bit.bor`, etc. — check availability with `pcall` first.
- **`//` integer divide does not exist.** Use `math.floor(a/b)`.
- **`unpack` not `table.unpack`.** The 5.1 name.
- **String patterns are Lua patterns, not regex.** No `\d`, `\w`, `\s`. Use `%d`, `%w`, `%s`.

---

## 2. Sandboxing

By default, DCS sanitizes the mission scripting sandbox — `io`, `os`, `lfs`, `require`, `package`, and several others are removed. **Our target server is desanitized**, so we have access to these. But we still code defensively:

- All file I/O goes through `storage.lua`. No direct `io.open` outside that module.
- All directory traversal goes through `storage.lua`. No direct `lfs.*` outside that module.
- If we need system time, prefer `timer.getAbsTime()` over `os.time()` when possible (for mission-time correctness).

This matters because it keeps the codebase portable to a sanitized environment later (e.g., if anyone else wants to run Skyfreight on a stock install).

---

## 3. Globals and namespacing

DCS pre-populates many globals: `world`, `trigger`, `coalition`, `country`, `env`, `timer`, `land`, `atmosphere`, `missionCommands`, `net`, `AI`, `Unit`, `Group`, `StaticObject`, `Airbase`, `Warehouse`, `coord`, `Weapon`, `Object`, `Spot`, `mist` (if loaded), `moose` (if loaded).

**Rules:**

- **Everything Skyfreight lives under `skyfreight`.** No bare globals. If you need a module-local variable, use `local`.
- **Never redefine a DCS global.** Do not `trigger = {}` or `env = ...`.
- **Never redefine Lua globals.** No `print = ...`, `type = ...`, etc.
- **Require other modules via our own loader, not `require()`.** DCS's sandbox may or may not support `require` depending on sanitization. Use `dofile` if needed or our init chain.

---

## 4. Event handlers

Events fire from `world.addEventHandler`. Register once; handle all events in a dispatcher.

**Pattern:**

```lua
local M = {}

local handlers = {}  -- event.id -> function

function M.on(event_id, fn)
  handlers[event_id] = fn
end

local eventHandler = {}
function eventHandler:onEvent(event)
  if not event or not event.id then return end
  local fn = handlers[event.id]
  if not fn then return end
  local ok, err = pcall(fn, event)
  if not ok then
    env.error("[skyfreight] event handler error for id " .. event.id .. ": " .. tostring(err))
  end
end

world.addEventHandler(eventHandler)
return M
```

**Rules:**

- **Wrap handlers in `pcall`.** If one handler errors, DCS may continue dispatching but the stack trace is lost in `dcs.log`. `pcall` gives us readable errors.
- **Never block in a handler.** No tight loops, no expensive `world.searchObjects` per event. If you need work, schedule it via `timer.scheduleFunction` to run in the next tick.
- **Event object shape varies.** `event.initiator`, `event.target`, `event.weapon`, `event.place`, `event.subPlace`, `event.time`, `event.cargo` — not all fields present for all events. Always check before using: `if event.initiator and event.initiator:isExist() then ...`.
- **`world.event.S_EVENT_*` constants.** Use the named constants, not raw integers. The enum changes between DCS versions; named constants are stable.

---

## 5. Timers

`timer.scheduleFunction(func, args, time)` — DCS's scheduler.

**Return value rules:**

```lua
local function myTask(args, now)
  -- do stuff
  return now + 2.0   -- reschedule for 2 seconds from now
  -- OR
  return nil          -- don't reschedule
end

timer.scheduleFunction(myTask, myArgs, timer.getTime() + 5.0)
```

**Rules:**

- **`timer.getTime()` is mission time in seconds since mission start.** Use this for scheduling.
- **`timer.getAbsTime()` is wall-clock seconds since mission day start.** Use this for date-aware logic.
- **Scheduled function receives `(args, now)`.** `now` is the absolute scheduled fire time.
- **Return value is the next fire time, or `nil` to stop.** Don't return `true` or `false` — DCS expects a number.
- **Keep the scheduled work small.** DCS fires timers during its own tick; long-running work stalls the sim.
- **Cache the ID if you may want to cancel:** `local id = timer.scheduleFunction(...)`, then `timer.removeFunction(id)`.

---

## 6. Units, Groups, StaticObjects

### 6.1 Existence checks

**Always check `:isExist()` before using a reference.** Units can be destroyed between when you got the reference and when you use it. A "dead" reference may silently return garbage from some methods.

```lua
local unit = Unit.getByName("Player_1")
if not unit or not unit:isExist() then return end
local pos = unit:getPoint()
```

### 6.2 The right lookup function

- `Unit.getByName(name)` — for aircraft, vehicles, ships, infantry.
- `Group.getByName(name)` — for the group containing those units.
- `StaticObject.getByName(name)` — for static objects (cargo crates, buildings, etc.).
- `Airbase.getByName(name)` — for airbases.
- `Object.getByName(name)` — rarely used; generic fallback.

Using the wrong one returns `nil`. Cargo statics must use `StaticObject.getByName`.

### 6.3 Spawning

- **Groups:** `coalition.addGroup(country_id, group_category, group_data)`.
- **Statics:** `coalition.addStaticObject(country_id, static_data)`.
- **Dynamic cargo:** via the newer APIs (`Airbase:createDynamicCargo` if available in current DCS version — verify).

**Country IDs** — use the `country.id` table. `country.id.USA`, `country.id.CJTF_BLUE`, etc. Don't hardcode integers.

**Categories** — `Group.Category.AIRPLANE`, `HELICOPTER`, `GROUND`, `SHIP`, `TRAIN`.

### 6.4 Positions and coordinates

**DCS uses an unusual coordinate convention:**

- `getPoint()` returns `{x, y, z}` where:
  - `x` is world-north in meters
  - `y` is altitude (height above sea level)
  - `z` is world-east in meters
- This differs from most 3D conventions where `y` is "up" in a different orientation or `z` is altitude.

**Rules:**

- When computing horizontal distance, ignore `y`: `dx = p1.x - p2.x; dz = p1.z - p2.z; dist = math.sqrt(dx*dx + dz*dz)`.
- When checking altitude, use `y`.
- `land.getHeight({x=x, y=z})` — note this takes `{x, y}` where `y` is actually our `z` (east). Terrain height functions use the 2D map projection.

### 6.5 Warehouse API

```lua
local airbase = Airbase.getByName("Kutaisi")
local wh = airbase:getWarehouse()
local inv = wh:getInventory(item_type)  -- item_type: 0=weapons, 1=liquids, 2=aircraft, 3=munitions
-- or wh:getInventory() for everything
wh:setItem(item_type_string, count)
wh:addItem(item_type_string, count)
wh:removeItem(item_type_string, count)
```

**Rules:**

- **Warehouse reset on mission load.** DCS re-reads `.miz` inventory every scenario load. Our persistence overrides this AFTER init.
- **Item names are strings.** e.g., `"FAB-250"`, not an integer.
- **Liquids are special:** `liquid.type.jet_fuel`, `liquid.type.aviation_gasoline`, `liquid.type.diesel`, `liquid.type.methanol_mixture`. Use the enum, not strings.

---

## 7. Zones

```lua
local zone = trigger.misc.getZone("my_zone")
-- zone.point is {x, y, z}
-- zone.radius is meters (circular zones only)
```

**Quad zones** have a different structure — they don't have `radius`, they have `verticies` (DCS's spelling, yes with the typo) which is an array of four points. Detect quad zones via `zone.type == 2` or presence of `verticies`.

**Zone properties:**

```lua
-- Access via the mission env, not trigger.misc
-- This requires walking the mission data; env.mission.triggers.zones is the array.
for _, z in ipairs(env.mission.triggers.zones) do
  if z.name == "my_zone" then
    for _, prop in ipairs(z.properties or {}) do
      env.info(prop.key .. " = " .. prop.value)
    end
  end
end
```

**Rules:**

- **Zone properties are always string values.** Parse to number with `tonumber()`, to bool with `str == "true"`.
- **`env.mission` is available but large.** Don't iterate it on every tick. Discover once at mission start, cache.

---

## 8. The F10 radio menu

`missionCommands.*` family:

- `missionCommands.addCommand(name, path, handler, args)` — global, visible to all players.
- `missionCommands.addCommandForGroup(group_id, name, path, handler, args)` — **per-group**, only visible to players in that group.
- `missionCommands.addSubMenu(name, path)` / `addSubMenuForGroup(...)` — submenu creation.
- `missionCommands.removeItem(path)` / `removeItemForGroup(group_id, path)` — removal.

**Rules:**

- **For player-facing menus, use `*ForGroup` variants.** Otherwise every player sees every other player's menus (and clicks affect the wrong state).
- **Path is a table of strings from root to leaf.** `{"Skyfreight", "Accept Contract", "Page 1"}`.
- **Handler receives `args` only.** No access to who clicked. Stash UCID/group in `args` when registering.
- **Player groups have numeric IDs**, not UCIDs. Map group → UCID via `identity.lua`.
- **Menus are rebuilt when the scenario changes, NOT on player slot change.** If a player leaves and rejoins a slot, their menu is gone — rebuild on `S_EVENT_BIRTH`.

---

## 9. Network (multiplayer) concerns

Mission scripting runs on the **server**, not on client machines. Therefore:

- **No direct UI for specific clients.** Use `trigger.action.outTextForGroup(group_id, text, duration, clearview)`.
- **No client-side state.** All state is server-side.
- **`net.*` functions** let us reach into the bot Lua state (`net.dostring_in`). We'll use this from the bot side in Phase 1, not from mission side.

---

## 10. Player identification

DCS has several ways to identify a player:

- **UCID** — unique per account, persists across name changes. The only stable key.
- **Player name** — current display name. Can collide and can be spoofed.
- **Slot ID / Unit ID** — unique per scenario session, not persistent.
- **Group ID** — the player's current group. Used for radio menus.

**Rules:**

- **All persistent data keyed by UCID.** No exceptions.
- **Get UCID via `net.get_player_info(player_id, 'ucid')`** — but `net` may not be available mission-side, only hook-side. Check.
- **From mission side,** you typically have a Unit. Get its group, then look up the player: `net.get_player_list()` returns all current players with their IDs, names, UCIDs, and slot IDs. Match by slot.
- **Cache the UCID → unit mapping** at `S_EVENT_BIRTH`, update at `S_EVENT_PLAYER_LEAVE_UNIT`.

---

## 11. Logging and debugging

`env.info(msg)`, `env.warning(msg)`, `env.error(msg)` — log to `dcs.log`.

**Pattern:**

```lua
env.info("[skyfreight] contract " .. contract_id .. " delivered by " .. ucid)
```

**Rules:**

- **Always prefix with `[skyfreight]`** for grep-ability in `dcs.log`.
- **Use `env.warning` for recoverable anomalies** (e.g., "expected zone X not found, skipping").
- **Use `env.error` only for actual bugs** — not for "expected state that just didn't happen this time."
- **Don't log inside tight loops.** `env.info` is slow; flooding the log costs perf.
- **For debug logging**, gate on `config.debug.enabled`:

```lua
local function dbg(msg)
  if skyfreight.config.debug.enabled then
    env.info("[skyfreight][debug] " .. msg)
  end
end
```

---

## 12. Performance

DCS fires mission-side Lua in its main sim tick. Slow Lua = sim stutters.

**Rules:**

- **No polling loops faster than 1 second** unless genuinely necessary. Default: 2 seconds. Cargo proximity polling at 2s is the tightest we need.
- **Don't iterate all players every tick.** Iterate on events instead.
- **`world.searchObjects` is expensive.** Cache results. Don't call more than a few times per second.
- **Don't re-build the full F10 menu on every event.** Build once per player at `S_EVENT_BIRTH`; rebuild parts only on state change.
- **JSON serialization is expensive.** Autosave once every 15 minutes; partial saves on state change.

---

## 13. Error handling

**Pattern:**

```lua
local ok, result = pcall(function()
  return someDCSCall()
end)
if not ok then
  env.error("[skyfreight] call failed: " .. tostring(result))
  return
end
-- use result
```

**Rules:**

- **Wrap DCS API calls in `pcall`** when failure is possible and recoverable.
- **Don't swallow errors silently.** Log them.
- **Don't `assert(cond)` in production code** — the assertion triggers a full mission error display. Use `if not cond then env.error(...) return end`.

---

## 14. String safety and user input

Chat commands and F10 menu actions can bring user input into our state.

**Rules:**

- **Sanitize before using in file paths, table keys, or log messages.**
- **Join codes are 4 digits.** Validate with `^%d%d%d%d$` pattern before accepting.
- **Never eval user input.** No `loadstring(user_input)()`, even with trust.

---

## 15. Table idioms

### 15.1 Array vs hash

Lua tables are both. `#t` only works on sequence arrays (1..n with no holes). For hashes, iterate with `pairs(t)`. For arrays, `ipairs(t)`.

**Rules:**

- **UCID-keyed tables are hashes.** `for ucid, player in pairs(state.players) do ...`.
- **Contract lists are arrays.** `for _, contract in ipairs(contracts) do ...`.
- **`#t` on a hash returns 0 or nonsense.** Don't use it.
- **Count hash entries by iterating**: `local n = 0; for _ in pairs(t) do n = n + 1 end`.

### 15.2 Cloning

Lua assigns tables by reference. To clone:

```lua
local function shallowClone(t)
  local r = {}
  for k, v in pairs(t) do r[k] = v end
  return r
end

local function deepClone(t, seen)
  seen = seen or {}
  if seen[t] then return seen[t] end
  if type(t) ~= "table" then return t end
  local r = {}
  seen[t] = r
  for k, v in pairs(t) do r[deepClone(k, seen)] = deepClone(v, seen) end
  return r
end
```

Use `util.deepClone` (once written) rather than reinventing per-module.

### 15.3 Nil holes in arrays

`{1, 2, nil, 4}` — `#t` can return 2 or 4 depending on implementation. **Never store `nil` in an array slot.** Use `false` or remove and re-index.

---

## 16. Module template

Every Skyfreight module follows this shape:

```lua
-- lua/<name>.lua
-- Brief description of module purpose

local M = {}

-- Module-local state
local state = {}

-- Forward declarations
local helper

-- Public API

function M.publicFunction()
  helper()
end

-- Private helpers

helper = function()
  -- ...
end

return M
```

Loaded by `init.lua`:

```lua
skyfreight.mymodule = dofile(skyfreight.paths.lua .. "/mymodule.lua")
```

(Exact loader depends on what works in the sandboxed environment — may be `dofile` with full paths or a custom `require` via our own resolver.)

---

## 17. Testing without flying

Some tests can run without DCS:

- Narrative composition (pure Lua).
- Payout calculation (pure Lua).
- Table utilities.

Others require DCS:

- Zone discovery.
- Cargo spawning.
- Event handling.
- Warehouse ops.
- F10 menu.

**For DCS-required tests, maintain a minimal smoke `.miz`** at `scenarios/examples/skyfreight_caucasus_demo.miz`. Load it, fly a short test, verify via log messages and in-game popups.

---

## 18. Common pitfalls checklist

Before considering any Lua change done, check:

- [ ] Runs under Lua 5.1 syntax (no `goto`, no integer `//`, no `bit32`).
- [ ] No new globals outside `skyfreight.*`.
- [ ] All DCS object references checked with `:isExist()` before method calls.
- [ ] All event handlers wrapped in `pcall`.
- [ ] All scheduled functions return a number or `nil`.
- [ ] All logging prefixed with `[skyfreight]`.
- [ ] No file I/O outside `storage.lua`.
- [ ] No `io`, `os`, `lfs`, `dcsbot`, or `trigger.action.outText` outside their respective abstraction modules.
- [ ] F10 menu modifications use `*ForGroup` variants for player-specific actions.
- [ ] UCID used as the persistent key, not player name.
- [ ] No tight polling loops under 1 second.
- [ ] No `assert()` in production code paths.
- [ ] Tables indexed as arrays don't contain `nil` holes.
- [ ] New `config.*` values have defaults in `config.lua`.

---

## 19. Resources

- **DCS Scripting Engine** — hoggit wiki: https://wiki.hoggitworld.com/view/Category:Scripting
- **MOOSE framework** (reference, not dependency) — https://github.com/FlightControl-Master/MOOSE
- **MIST framework** (reference, not dependency) — https://github.com/mrSkortch/MissionScriptingTools
- **CTLD script** (reference for sling load patterns) — https://github.com/ciribob/DCS-CTLD
- **Hoggit "Events" reference** — https://wiki.hoggitworld.com/view/Category:Events

Read these when you need to know "what does DCS actually do here?" — MOOSE and MIST are working, battle-tested Lua you can cross-reference.

---

## 20. When in doubt

1. Check `:isExist()` on any DCS object reference before using it.
2. Wrap anything that touches DCS API in `pcall` if it might fail.
3. Log with `env.info` at key decision points during development; gate behind `debug.enabled` for production.
4. Prefer events over polling; when polling, use long intervals.
5. Keep modules self-contained; talk to other modules through their public API only.
6. If something needs a Lua feature from 5.2+, find a 5.1 equivalent; don't try to polyfill.

---

**End of guidelines.**
