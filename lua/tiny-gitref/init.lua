local Config = require("tiny-gitref.config")
local Source = require("tiny-gitref.source")

local M = {}
local commands_installed = false
local provider_preloaded = false
local preload_pending = false
local preload_attempts = 0

local PRELOAD_RETRY_COUNT = 100
local PRELOAD_RETRY_DELAY = 50

local function preload_provider()
  if provider_preloaded or not Config.options.preload_provider then
    preload_pending = false
    return
  end

  local module_ok, sources = pcall(require, "blink.cmp.sources.lib")
  local provider_ok, provider = false, nil

  if module_ok then
    provider_ok, provider = pcall(sources.get_provider_by_id, "gitref")
  end

  if provider_ok and provider ~= nil then
    provider_preloaded = true
    preload_pending = false
    return
  end

  preload_attempts = preload_attempts + 1

  if preload_attempts >= PRELOAD_RETRY_COUNT then
    preload_pending = false
    return
  end

  vim.defer_fn(preload_provider, PRELOAD_RETRY_DELAY)
end

local function schedule_provider_preload()
  if provider_preloaded or preload_pending or not Config.options.preload_provider then
    return
  end

  preload_pending = true
  preload_attempts = 0
  vim.schedule(preload_provider)
end

function M.setup(opts)
  Config.setup(opts)

  if not commands_installed then
    commands_installed = true
    vim.api.nvim_create_user_command("GitRefReload", function()
      M.reload()
    end, { desc = "Reload tiny-gitref completions" })
  end

  schedule_provider_preload()
end

function M.new(opts)
  return Source.new(opts)
end

function M.reload()
  Source.reload_all()
end

return M
