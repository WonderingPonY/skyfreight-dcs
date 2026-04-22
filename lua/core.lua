local M = {}

function M.bootstrap(namespace, luaPath)
  if type(namespace) ~= "table" then
    return nil
  end

  namespace.version = namespace.version or "0.2.0"
  namespace.paths = namespace.paths or {}
  namespace.state = namespace.state or {}
  namespace.modules = namespace.modules or {}
  namespace.templates = namespace.templates or {}

  namespace.paths.lua = luaPath
  namespace.paths.templates = luaPath .. "/templates"
  namespace.state.version = namespace.state.version or namespace.version

  return namespace
end

return M
