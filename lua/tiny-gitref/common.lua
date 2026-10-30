local M = {}

local MAX_DOC_LENGTH = 4000

function M.clamp_limit(limit)
  return math.max(1, math.min(tonumber(limit) or 100, 100))
end

function M.encode_uri_component(value)
  return (tostring(value):gsub("([^%w%-%._~])", function(char)
    return ("%%%02X"):format(string.byte(char))
  end))
end

function M.encode_path(path)
  local parts = {}

  for part in tostring(path):gmatch("[^/]+") do
    table.insert(parts, M.encode_uri_component(part))
  end

  return table.concat(parts, "/")
end

local function concise_body(body)
  if type(body) ~= "string" then
    return ""
  end

  body = vim.trim(body:gsub("\r\n", "\n"))

  if #body > MAX_DOC_LENGTH then
    return body:sub(1, MAX_DOC_LENGTH) .. "\n\n..."
  end

  return body
end

local function ref_item(ref, count, index)
  local number = tostring(ref.number)
  local lines = {
    ("# #%s %s"):format(number, ref.title or ""),
    "",
    ("%s - %s"):format(ref.kind, ref.state or "unknown"),
  }

  if ref.author and ref.author ~= "" then
    table.insert(lines, "Author: @" .. ref.author)
  end

  if type(ref.labels) == "table" and #ref.labels > 0 then
    table.insert(lines, "Labels: " .. table.concat(ref.labels, ", "))
  end

  if ref.updated_at and ref.updated_at ~= "" then
    table.insert(lines, "Updated: " .. ref.updated_at)
  end

  local body = concise_body(ref.body)

  if body ~= "" then
    vim.list_extend(lines, { "", body })
  end

  return {
    label = ("#%s %s"):format(number, ref.title or ""),
    insert_text = "#" .. number,
    trigger = "#",
    kind_name = ref.kind,
    kind_icon = "#",
    detail = ("%s - %s"):format(ref.kind, ref.state or "unknown"),
    documentation = table.concat(lines, "\n"),
    score_offset = count - index,
    sort_key = ref.updated_at or "",
  }
end

function M.ref_items(refs)
  local items = {}

  for _, ref in ipairs(refs or {}) do
    if ref.number ~= nil and ref.title then
      table.insert(items, ref_item(ref, #refs, #items + 1))
    end
  end

  return items
end

local function mention_item(user, count, index)
  local lines = { ("# @%s"):format(user.username), "" }

  if user.name and user.name ~= "" then
    table.insert(lines, user.name)
  end

  if user.bio and user.bio ~= "" then
    vim.list_extend(lines, { "", user.bio })
  end

  if user.url and user.url ~= "" then
    vim.list_extend(lines, { "", user.url })
  end

  return {
    label = user.username,
    insert_text = "@" .. user.username,
    trigger = "@",
    kind_name = "Mention",
    kind_icon = "@",
    detail = user.name or "Mentionable user",
    documentation = table.concat(lines, "\n"),
    score_offset = count - index,
  }
end

function M.mention_items(users)
  local items = {}

  for _, user in ipairs(users or {}) do
    if user.username then
      table.insert(items, mention_item(user, #users, #items + 1))
    end
  end

  return items
end

function M.sort_items(items)
  table.sort(items, function(left, right)
    if left.sort_key or right.sort_key then
      local left_key = left.sort_key or ""
      local right_key = right.sort_key or ""

      if left_key ~= right_key then
        return left_key > right_key
      end
    end

    if (left.score_offset or 0) ~= (right.score_offset or 0) then
      return (left.score_offset or 0) > (right.score_offset or 0)
    end

    return (left.label or "") < (right.label or "")
  end)
end

function M.fetch_all(requests, callback)
  if #requests == 0 then
    callback({})
    return function() end
  end

  local pending = #requests
  local cancelled = false
  local items = {}
  local errors = {}
  local cancels = {}

  local function finish_request(index, request_items, err)
    if cancelled then
      return
    end

    pending = pending - 1

    if request_items then
      vim.list_extend(items, request_items)
    end

    if err then
      errors[index] = err
    end

    if pending > 0 then
      return
    end

    local messages = {}

    for _, message in pairs(errors) do
      table.insert(messages, message)
    end

    table.sort(messages)
    M.sort_items(items)
    callback(items, #messages > 0 and table.concat(messages, "\n") or nil)
  end

  for index, request in ipairs(requests) do
    local ok, cancel = pcall(request, function(request_items, err)
      finish_request(index, request_items, err)
    end)

    if not ok then
      finish_request(index, nil, tostring(cancel))
    elseif type(cancel) == "function" then
      table.insert(cancels, cancel)
    end
  end

  return function()
    cancelled = true

    for _, cancel in ipairs(cancels) do
      cancel()
    end
  end
end

return M
