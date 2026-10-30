local Forgejo = require("tiny-gitref.providers.forgejo")
local GitHub = require("tiny-gitref.providers.github")
local GitLab = require("tiny-gitref.providers.gitlab")

local M = {}

local providers = {
  forgejo = Forgejo,
  gitea = Forgejo,
  github = GitHub,
  gitlab = GitLab,
}

local builtins = {
  ["github.com"] = {
    provider = "github",
    api = "https://api.github.com",
  },
  ["gitlab.com"] = {
    provider = "gitlab",
    api = "https://gitlab.com/api/v4",
  },
  ["codeberg.org"] = {
    provider = "forgejo",
    api = "https://codeberg.org/api/v1",
    token_env = { "CODEBERG_TOKEN", "FORGEJO_TOKEN", "GITEA_TOKEN" },
  },
  ["gitea.com"] = {
    provider = "forgejo",
    api = "https://gitea.com/api/v1",
    token_env = { "GITEA_TOKEN", "FORGEJO_TOKEN" },
  },
}

local function strip_trailing_slashes(value)
  return value:gsub("/+$", "")
end

local function endpoint_config(options, host)
  local configured = (options.endpoints or {})[host]
  local builtin = builtins[host]

  if type(configured) == "string" then
    configured = { provider = configured }
  end

  if not configured and not builtin then
    return nil, ("no provider configured for %s; add it under endpoints"):format(host)
  end

  return vim.tbl_deep_extend("force", vim.deepcopy(builtin or {}), configured or {})
end

local function read_token(token)
  if type(token) == "function" then
    local ok, value = pcall(token)

    if not ok then
      return nil, "token callback failed: " .. tostring(value)
    end

    token = value
  end

  if token == nil then
    return ""
  end

  if type(token) ~= "string" then
    return nil, "token must be a string or function"
  end

  return vim.trim(token)
end

local function resolve_token(config, provider)
  if config.token ~= nil then
    return read_token(config.token)
  end

  for _, name in ipairs(config.token_env or provider.token_env or {}) do
    local value = vim.env[name]

    if value and value ~= "" then
      return value
    end
  end

  return ""
end

function M.resolve(repository, options)
  local host = repository.host:lower():gsub("%.$", "")
  local config, config_err = endpoint_config(options, host)

  if not config then
    return nil, config_err
  end

  local provider_name = tostring(config.provider or ""):lower()
  local provider = providers[provider_name]

  if not provider then
    return nil, ("unknown provider %q for %s"):format(provider_name, host)
  end

  local token, token_err = resolve_token(config, provider)

  if token == nil then
    return nil, token_err
  end

  local api = strip_trailing_slashes(config.api or provider.default_api(repository))
  local graphql = config.graphql

  if not graphql and provider.default_graphql then
    graphql = provider.default_graphql(repository, api)
  end

  return {
    api = api,
    graphql = graphql and strip_trailing_slashes(graphql) or nil,
    host = host,
    name = provider.name,
    provider = provider,
    token = token,
  }
end

return M
