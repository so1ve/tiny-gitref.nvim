local Common = require("tiny-gitref.common")
local Http = require("tiny-gitref.http")

local M = {
  name = "forgejo",
  token_env = { "FORGEJO_TOKEN", "GITEA_TOKEN" },
}

function M.default_api(repository)
  return ("https://%s/api/v1"):format(repository.host)
end

function M.urls(repository, endpoint, limit)
  local project = ("%s/repos/%s"):format(endpoint.api, Common.encode_path(repository.slug))
  local amount = Common.clamp_limit(limit)

  return {
    issues = ("%s/issues?state=all&type=issues&limit=%d"):format(project, amount),
    pulls = ("%s/pulls?state=all&limit=%d"):format(project, amount),
    assignees = ("%s/assignees?limit=%d"):format(project, amount),
  }
end

local function headers(endpoint)
  local result = { Accept = "application/json" }

  if endpoint.token ~= "" then
    result.Authorization = "token " .. endpoint.token
  end

  return result
end

local function request(url, endpoint, callback)
  return Http.request({
    url = url,
    headers = headers(endpoint),
  }, callback)
end

local function labels_from(item)
  local labels = {}

  for _, label in ipairs(item.labels or {}) do
    table.insert(labels, type(label) == "table" and label.name or tostring(label))
  end

  return labels
end

function M.items_from_issues(issues)
  local refs = {}

  for _, issue in ipairs(issues or {}) do
    table.insert(refs, {
      author = issue.user and issue.user.login,
      body = issue.body,
      kind = "Issue",
      labels = labels_from(issue),
      number = issue.number,
      state = issue.state,
      title = issue.title,
      updated_at = issue.updated_at,
    })
  end

  return Common.ref_items(refs)
end

function M.items_from_pulls(pulls)
  local refs = {}

  for _, pull in ipairs(pulls or {}) do
    table.insert(refs, {
      author = pull.user and pull.user.login,
      body = pull.body,
      kind = "PR",
      labels = labels_from(pull),
      number = pull.number,
      state = pull.merged and "merged" or pull.state,
      title = pull.title,
      updated_at = pull.updated_at,
    })
  end

  return Common.ref_items(refs)
end

function M.items_from_assignees(assignees)
  local users = {}

  for _, user in ipairs(assignees or {}) do
    table.insert(users, {
      bio = user.description,
      name = user.full_name,
      url = user.html_url,
      username = user.login or user.username,
    })
  end

  return Common.mention_items(users)
end

local function decode_list(output, subject, build_items)
  local body = Http.decode(output)

  if type(body) ~= "table" or body.message then
    return nil, type(body) == "table" and body.message or ("Forgejo returned invalid %s JSON"):format(subject)
  end

  return build_items(body)
end

function M.parse_issues(output)
  return decode_list(output, "issue", M.items_from_issues)
end

function M.parse_pulls(output)
  return decode_list(output, "pull request", M.items_from_pulls)
end

function M.parse_assignees(output)
  return decode_list(output, "assignee", M.items_from_assignees)
end

function M.fetch(repository, endpoint, options, callback)
  local triggers = options.triggers or { "#", "@" }
  local urls = M.urls(repository, endpoint, options.limit)
  local requests = {}

  if vim.tbl_contains(triggers, "#") then
    table.insert(requests, function(done)
      return request(urls.issues, endpoint, function(out)
        if out.code ~= 0 then
          done(nil, "issues: " .. Http.error_message(out))
          return
        end

        local items, err = M.parse_issues(out.stdout)
        done(items, err and "issues: " .. err or nil)
      end)
    end)

    table.insert(requests, function(done)
      return request(urls.pulls, endpoint, function(out)
        if out.code ~= 0 then
          done(nil, "pull requests: " .. Http.error_message(out))
          return
        end

        local items, err = M.parse_pulls(out.stdout)
        done(items, err and "pull requests: " .. err or nil)
      end)
    end)
  end

  if vim.tbl_contains(triggers, "@") then
    table.insert(requests, function(done)
      return request(urls.assignees, endpoint, function(out)
        if out.code ~= 0 then
          done(nil, "mentions: " .. Http.error_message(out))
          return
        end

        local items, err = M.parse_assignees(out.stdout)
        done(items, err and "mentions: " .. err or nil)
      end)
    end)
  end

  return Common.fetch_all(requests, callback)
end

return M
