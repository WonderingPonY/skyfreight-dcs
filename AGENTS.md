# AGENTS.md

# Skyfreight — Codex Instructions

Skyfreight is a Lua-first civilian logistics framework for DCS World.

Current objective: Phase 0.
Build a standalone Lua framework that runs entirely inside DCS missions.

Hard constraints:
- Lua 5.1 only
- No Python
- No database
- No DCSServerBot
- Persistence via JSON files only

## Read first

Before making changes, read these files in order:
1. `docs/DESIGN.md`
2. `docs/DCS_LUA_GUIDELINES.md`

`docs/DCS_LUA_GUIDELINES.md` is mandatory before writing or changing Lua code.

## Primary implementation rules

- Use Lua 5.1 syntax only.
- Do not use `goto`, `//`, or `bit32`.
- All code must live under the `skyfreight` namespace.
- Never introduce bare globals.
- One module per file.
- Each module returns a table.
- Public API first, local helpers below.
- Do not use `require()`.
- Modules are loaded through the project init chain in `init.lua` using `dofile` or equivalent sandbox-safe loading.

## DCS-specific rules

- DCS coordinates are:
  - `x` = world-north
  - `y` = altitude
  - `z` = world-east
- Always call `:isExist()` before using DCS object references where object lifetime may be uncertain.
- Wrap DCS API calls in `pcall` whenever failure is possible.
- For player-specific F10 menus, use `missionCommands.addCommandForGroup`.
- Do not use global F10 menu variants for player-specific actions.
- UCID is the only persistent identifier for player data.
- Never key persistent player data by player name.

## Logging and side effects

- Use `env.info`, `env.warning`, and `env.error` for logging.
- Prefix every log line with `[skyfreight]`.
- Do not use `trigger.action.outText` outside `notify.lua`.
- Do not use `io.*` or `lfs.*` outside `storage.lua`.

## Configuration rules

- All default config values live in `config.lua`.
- Modules must read configuration from `skyfreight.config.*`.
- Do not hardcode config values inside feature modules.

## Build order

Follow `docs/DESIGN.md` section 23 exactly for Phase 0 sequencing.
Start with step 1: module skeleton.

Prefer small, self-contained, committable changes.
Do not bundle multiple major steps into one edit unless explicitly asked.

## Change policy

When editing:
- preserve existing architecture
- do not invent new framework patterns unless the design docs require them
- do not broaden scope beyond the current step
- avoid speculative abstractions
- keep functions small and explicit
- prefer boring, robust code over clever code

## Validation checklist

Before finishing a task, verify:
- no Lua 5.2+ syntax was introduced
- no bare globals were introduced
- no forbidden APIs are used outside their abstraction modules
- DCS object access is guarded appropriately
- logging uses the `[skyfreight]` prefix
- persistent player identity uses UCID only
- code matches the current Phase 0 step

## If uncertain

Do not invent a pattern just because it seems elegant.
Check `docs/DCS_LUA_GUIDELINES.md` section 20, “When in doubt”.
If that does not resolve the issue, prefer the simplest implementation consistent with the existing design.