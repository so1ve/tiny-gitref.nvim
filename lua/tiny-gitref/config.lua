local M = {}

M.defaults = {
  endpoints = {},
  filetypes = { "gitcommit", "markdown", "octo" },
  triggers = { "#", "@" },
  limit = 100,
  preload_provider = true,
  remote = "origin",
}

M.options = vim.deepcopy(M.defaults)

local function merge(base, opts)
  local options = vim.tbl_deep_extend("force", base, opts or {})

  for _, key in ipairs({ "filetypes", "triggers" }) do
    if opts and opts[key] then
      options[key] = vim.deepcopy(opts[key])
    end
  end

  return options
end

local function reject_top_level_token(opts)
  if opts and opts.token ~= nil then
    error("tiny-gitref: configure tokens per endpoint, not at the top level")
  end
end

function M.setup(opts)
  reject_top_level_token(opts)

  M.options = merge(vim.deepcopy(M.defaults), opts)
end

function M.get(opts)
  reject_top_level_token(opts)
  return merge(vim.deepcopy(M.options), opts)
end

return M
