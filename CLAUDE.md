# Skyfreight — Context for Claude Code

Skyfreight is a Lua-first civilian logistics framework for DCS World.
Phase 0 goal: build a standalone Lua framework that runs entirely inside DCS missions.
No Python, no database, no DCSServerBot. Persistence via JSON files.

## Read first

- `docs/DESIGN.md` — full design specification.
- `docs/DCS_LUA_GUIDELINES.md` — **required reading** before writing any Lua.

## Non-negotiable rules

- Lua 5.1 syntax only. No `goto`, no integer division `//`, no `bit32`.
- All code lives under the `skyfreight` namespace. No bare globals.
- DCS coordinates: `x` = world-north, `y` = altitude, `z` = world-east.
- Always check `:isExist()` before using DCS object references.
- Wrap DCS API calls in `pcall` where failure is possible.
- Log with `env.info` / `env.warning` / `env.error`, always prefixed `[skyfreight]`.
- No `io.*`, `lfs.*`, or `trigger.action.outText` outside their abstraction modules
  (`storage.lua`, `notify.lua`).
- UCID is the only persistent key for player data — never player name.
- F10 menu: use `missionCommands.addCommandForGroup` for player-specific menus,
  not the global variants.

## Phase 0 build order

See `docs/DESIGN.md` §23. Start with step 1 (module skeleton).
Each step should be committable on its own — we prefer lots of small commits
over large ones.

## Conventions

- One module per file; each module returns a table.
- Public API at the top of each module; helpers below as `local`.
- Config values have defaults in `config.lua`; modules read from
  `skyfreight.config.*`, never hardcoded.
- No `require()` — use our init chain (`init.lua` loads modules via `dofile` or
  equivalent, depending on what the sandbox allows).

## When in doubt

Check `docs/DCS_LUA_GUIDELINES.md` §20 "When in doubt" before inventing a pattern.