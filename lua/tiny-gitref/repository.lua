local M = {}

function M.normalize_remote(remote)
  if type(remote) ~= "string" then
    return ""
  end

  return vim.trim(remote)
    :gsub("%.git$", "")
    :gsub("^[%a][%w+.-]*://", "")
    :gsub("^[^/@]+@", "")
    :gsub("^([^/]-):%d+/", "%1/")
    :gsub("/+$", "")
end

function M.parse_remote(remote)
  local normalized = M.normalize_remote(remote)
  local host, path = normalized:match("^([^/:]+)[/:](.+)$")

  if not host or not path then
    return nil
  end

  if host == "ssh.github.com" then
    host = "github.com"
  end

  path = path:gsub("^/+", ""):gsub("/+$", "")
  local name = path:match("([^/]+)$")
  local owner = path:match("^(.*)/[^/]+$")

  if not owner or owner == "" or not name then
    return nil
  end

  return {
    host = host:lower(),
    owner = owner,
    name = name,
    slug = path,
  }
end

function M.from_octo(bufnr)
  if vim.bo[bufnr].filetype ~= "octo" then
    return nil
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  local host, owner, name = path:match("^octo://([^/]+)/([^/]+)/([^/]+)")

  if not owner then
    return nil
  end

  return {
    host = host:lower(),
    owner = owner,
    name = name,
    slug = owner .. "/" .. name,
  }
end

function M.root_for_buffer(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local git_root = name:match("^(.-)[/\\]%.git[/\\]")

  if git_root and git_root ~= "" then
    return git_root
  end

  local start = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
  return vim.fs.root(start, ".git")
end

function M.buffer_key(bufnr)
  local octo = M.from_octo(bufnr)

  if octo then
    return string.format("%s://%s/%s", octo.host, octo.slug)
  end

  return M.root_for_buffer(bufnr)
end

function M.detect(opts, bufnr, callback)
  local octo = M.from_octo(bufnr)

  if octo then
    callback(octo)
    return function() end
  end

  local root = M.root_for_buffer(bufnr)

  if not root then
    callback()
    return function() end
  end

  local command = { "git", "-C", root, "remote", "get-url", opts.remote }
  local ok, job = pcall(vim.system, command, { text = true }, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        callback()
        return
      end

      local repository = M.parse_remote(out.stdout)

      if not repository then
        callback(nil, ("cannot parse remote URL for %s"):format(root))
        return
      end

      callback(repository)
    end)
  end)

  if not ok then
    callback(nil, tostring(job))
    return function() end
  end

  return function()
    job:kill("TERM")
  end
end

return M
