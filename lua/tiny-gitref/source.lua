local Config = require("tiny-gitref.config")
local Position = require("tiny-gitref.position")
local Provider = require("tiny-gitref.provider")
local Repository = require("tiny-gitref.repository")

local M = {}

local sources = setmetatable({}, { __mode = "k" })
local next_waiter_id = 0
local autocmds_installed = false

local function empty_response()
  return {
    is_incomplete_backward = false,
    is_incomplete_forward = false,
    items = {},
  }
end

local function trigger_start(line, column, trigger)
  local before_cursor = line:sub(1, column)
  local start = nil
  local offset = 1

  while true do
    local found = before_cursor:find(trigger, offset, true)

    if not found then
      break
    end

    start = found
    offset = found + #trigger
  end

  return start and start - 1 or column
end

local function to_blink_item(item, context, trigger)
  local row = context.cursor[1] - 1
  local start_column = trigger_start(context.line, context.cursor[2], trigger)

  return {
    label = item.label,
    insertText = item.insert_text,
    textEdit = {
      range = {
        start = { line = row, character = start_column },
        ["end"] = { line = row, character = context.cursor[2] },
      },
      newText = item.insert_text,
    },
    kind = require("blink.cmp.types").CompletionItemKind.Reference,
    kind_name = item.kind_name,
    kind_icon = item.kind_icon,
    detail = item.detail,
    documentation = item.documentation,
    score_offset = item.score_offset,
  }
end

function M:enabled()
  return vim.fn.executable("git") == 1 or vim.bo.filetype == "octo"
end

function M:get_trigger_characters()
  return self.config.triggers
end

function M:should_show_items(context)
  return context.mode ~= "cmdline"
    and context.trigger.initial_character ~= nil
    and vim.tbl_contains(self.config.triggers, context.trigger.initial_character)
    and Position.is_allowed(
      context.bufnr,
      context.cursor[1] - 1,
      context.line,
      context.cursor[2],
      self.config.filetypes
    )
end

function M:report_error(message)
  if not message or message == self.last_error then
    return
  end

  self.last_error = message
  vim.notify("tiny-gitref: " .. message, vim.log.levels.WARN)
end

function M:cancel_fetch()
  if self.cancel then
    self.cancel()
    self.cancel = nil
  end
end

function M:finish(items, err)
  self.loading = false
  self.ready = true
  self.items = items or {}

  local waiters = self.waiters
  self.waiters = {}

  for _, waiter in pairs(waiters) do
    if not waiter.cancelled then
      waiter.callback(self:response(waiter.trigger, waiter.context))
    end
  end

  if err then
    self:report_error(err)
  else
    self.last_error = nil
  end
end

function M:response(trigger, context)
  local items = {}

  for _, item in ipairs(self.items) do
    if item.trigger == trigger then
      table.insert(items, to_blink_item(item, context, trigger))
    end
  end

  return {
    is_incomplete_backward = false,
    is_incomplete_forward = false,
    items = items,
  }
end

function M:load(bufnr)
  self.generation = self.generation + 1
  local generation = self.generation

  self:cancel_fetch()
  self.loading = true
  self.ready = false
  self.repo_key = Repository.buffer_key(bufnr)

  if not self.repo_key then
    self:finish({})
    return
  end

  Repository.detect(self.config, bufnr, function(repository, err)
    if generation ~= self.generation then
      return
    end

    if not repository then
      self:finish({}, err)
      return
    end

    local endpoint, endpoint_err = Provider.resolve(repository, self.config)

    if not endpoint then
      self:finish({}, endpoint_err)
      return
    end

    self.cancel = endpoint.provider.fetch(repository, endpoint, self.config, function(items, fetch_err)
      if generation ~= self.generation then
        return
      end

      self.cancel = nil
      self:finish(items, fetch_err)
    end)
  end)
end

function M:refresh_if_needed()
  local key = Repository.buffer_key(0)

  if key ~= self.repo_key then
    self:load(0)
  end
end

function M:reload()
  self:load(0)
end

function M:get_completions(context, callback)
  local trigger = context.trigger.initial_character

  if not trigger or not vim.tbl_contains(self.config.triggers, trigger) then
    callback(empty_response())
    return function() end
  end

  if
    not Position.is_allowed(
      context.bufnr,
      context.cursor[1] - 1,
      context.line,
      context.cursor[2],
      self.config.filetypes
    )
  then
    callback(empty_response())
    return function() end
  end

  local key = Repository.buffer_key(context.bufnr)

  if key ~= self.repo_key then
    self:load(context.bufnr)
  end

  if self.ready then
    callback(self:response(trigger, context))
    return function() end
  end

  next_waiter_id = next_waiter_id + 1
  local waiter = {
    trigger = trigger,
    context = context,
    callback = callback,
  }
  self.waiters[next_waiter_id] = waiter

  return function()
    waiter.cancelled = true
    self.waiters[next_waiter_id] = nil
  end
end

local function install_autocmds()
  if autocmds_installed then
    return
  end

  autocmds_installed = true
  local group = vim.api.nvim_create_augroup("tiny-gitref", { clear = true })

  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
      for source in pairs(sources) do
        source:refresh_if_needed()
      end
    end,
  })

  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      for source in pairs(sources) do
        source:refresh_if_needed()
      end
    end,
  })
end

function M.new(opts)
  local self = setmetatable({
    config = Config.get(opts),
    generation = 0,
    items = {},
    loading = false,
    ready = false,
    repo_key = false,
    waiters = {},
  }, { __index = M })

  sources[self] = true
  install_autocmds()

  vim.schedule(function()
    self:refresh_if_needed()
  end)

  return self
end

function M.reload_all()
  for source in pairs(sources) do
    source:reload()
  end
end

return M
