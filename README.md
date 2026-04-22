Skyfreight is a Lua-first civilian logistics framework for DCS World.

Current status: Phase 0 in progress.

**Mission Loading**
Use a tiny bootstrap file as the mission entrypoint instead of loading `lua/init.lua` directly. DCS can execute embedded scripts without a stable filesystem-relative base path, so the bootstrap gives Skyfreight the real `lua` directory first.

Example `LuaLoad.lua`:

```lua
skyfreight = skyfreight or {}
skyfreight.paths = skyfreight.paths or {}
skyfreight.paths.lua = [[C:\Users\Stevie\OneDrive\Saved Games\DCS.openbeta\Missions\Graceys-Village-Missions\skyfreight-dcs\lua]]

dofile(skyfreight.paths.lua .. "\\init.lua")
```

Point the mission trigger at `LuaLoad.lua`.

**Debug Mode**
Debug settings live in [lua/config.lua](./lua/config.lua).

Enable debug logging while developing:

```lua
debug = {
  enabled = true,
  log_level = "info",
  single_player_ucid = "sp_test_pilot",
}
```

With `debug.enabled = true`, the loader writes per-module lines to `dcs.log`, for example:

- `[skyfreight][debug] loading core from ...`
- `[skyfreight][debug] loaded notify from ...`
- `[skyfreight][debug] loaded templates.narratives from ...`

**Single Player Testing**
Single player does not provide a real multiplayer UCID. For local testing, Skyfreight can use the synthetic UCID from `debug.single_player_ucid`, but only when:

- `debug.enabled = true`
- `net` is unavailable in the mission environment

This is for development only. Persistent player identity in real gameplay still uses UCID only.

**Notes**
- Keep `LuaLoad.lua` as a bootstrap only. Do not manually `dofile()` every module in mission order.
- `notify.lua` is the only place that should call `trigger.action.outText` / `trigger.action.outTextForGroup`.
- `storage.lua` is the only place that should use `io`, `os`, or `lfs`.
