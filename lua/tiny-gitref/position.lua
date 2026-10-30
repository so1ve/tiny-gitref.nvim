local Config = require("tiny-gitref.config")

local M = {}

local function has_comment_capture(bufnr, row, column)
  local ok, captures = pcall(vim.treesitter.get_captures, bufnr, { row, column })

  if not ok then
    return false
  end

  for _, capture in ipairs(captures) do
    if capture.capture == "comment" then
      return true
    end
  end

  return false
end

local function comment_marker(bufnr)
  local commentstring = vim.bo[bufnr].commentstring
  local marker = commentstring:match("^(.-)%%s") or commentstring:match("^%s*(%S+)")

  if not marker then
    return nil
  end

  marker = vim.trim(marker)
  return marker ~= "" and marker or nil
end

local function has_comment_marker(line, column, marker)
  local before_cursor = line:sub(1, column)
  local offset = 1

  while true do
    local start = before_cursor:find(marker, offset, true)

    if not start then
      return false
    end

    if start == 1 or before_cursor:sub(start - 1, start - 1):match("%s") then
      return true
    end

    offset = start + #marker
  end
end

function M.is_allowed(bufnr, row, line, column, filetypes)
  filetypes = filetypes or Config.options.filetypes

  if vim.tbl_contains(filetypes, vim.bo[bufnr].filetype) then
    return true
  end

  if has_comment_capture(bufnr, row, column) or (column > 0 and has_comment_capture(bufnr, row, column - 1)) then
    return true
  end

  local marker = comment_marker(bufnr)
  return marker ~= nil and has_comment_marker(line, column, marker)
end

return M
