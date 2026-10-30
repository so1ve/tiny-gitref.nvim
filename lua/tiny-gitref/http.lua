local M = {}

local function first_line(value)
  if type(value) ~= "string" then
    return nil
  end

  for line in value:gmatch("[^\r\n]+") do
    line = vim.trim(line)

    if line ~= "" then
      return line
    end
  end
end

function M.decode(value)
  local ok, result = pcall(vim.json.decode, value, { luanil = { object = true, array = true } })
  return ok and result or nil
end

function M.error_message(out)
  local message = first_line(out.stderr)
  local body = M.decode(out.stdout)

  if body and type(body) == "table" then
    message = body.message or body.error or message
  end

  return message or ("command exited with status " .. tostring(out.code))
end

function M.run(command, args, callback)
  local ok, job = pcall(vim.system, vim.list_extend({ command }, args), { text = true }, function(out)
    vim.schedule(function()
      callback(out)
    end)
  end)

  if not ok then
    callback({ code = -1, stdout = "", stderr = tostring(job) })
    return function() end
  end

  return function()
    job:kill("TERM")
  end
end

function M.request(spec, callback)
  local args = {
    "--silent",
    "--show-error",
    "--fail",
    "--max-time",
    "20",
  }

  for name, value in pairs(spec.headers or {}) do
    vim.list_extend(args, { "-H", name .. ": " .. value })
  end

  if spec.method then
    vim.list_extend(args, { "-X", spec.method })
  end

  if spec.body then
    vim.list_extend(args, { "--data-binary", spec.body })
  end

  table.insert(args, spec.url)
  return M.run("curl", args, callback)
end

return M
