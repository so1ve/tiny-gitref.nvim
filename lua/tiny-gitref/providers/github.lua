local Common = require("tiny-gitref.common")
local Http = require("tiny-gitref.http")

local M = {
  name = "github",
  token_env = { "GH_TOKEN", "GITHUB_TOKEN" },
}

local MENTIONABLE_USERS_QUERY = [[
query($owner: String!, $name: String!, $limit: Int!) {
  repository(owner: $owner, name: $name) {
    mentionableUsers(first: $limit) {
      nodes {
        login
        name
        url
        bio
      }
    }
  }
}
]]

function M.default_api(repository)
  if repository.host == "github.com" then
    return "https://api.github.com"
  end

  return ("https://%s/api/v3"):format(repository.host)
end

function M.default_graphql(repository, api)
  if repository.host == "github.com" then
    return "https://api.github.com/graphql"
  end

  if api:match("/api/v3$") then
    return api:gsub("/api/v3$", "/api/graphql")
  end

  return api .. "/graphql"
end

function M.rest_url(repository, endpoint, limit)
  return ("%s/repos/%s/issues?state=all&sort=updated&direction=desc&per_page=%d"):format(
    endpoint.api,
    Common.encode_path(repository.slug),
    Common.clamp_limit(limit)
  )
end

local function headers(endpoint)
  local result = {
    Accept = "application/vnd.github+json",
    ["X-GitHub-Api-Version"] = "2022-11-28",
  }

  if endpoint.token ~= "" then
    result.Authorization = "Bearer " .. endpoint.token
  end

  return result
end

local function gh_api_args(repository)
  local args = { "api" }

  if repository.host ~= "github.com" then
    vim.list_extend(args, { "--hostname", repository.host })
  end

  return args
end

local function request_rest_with_curl(repository, endpoint, limit, callback)
  return Http.request({
    url = M.rest_url(repository, endpoint, limit),
    headers = headers(endpoint),
  }, callback)
end

local function request_rest_with_gh(repository, endpoint, limit, callback)
  local args = gh_api_args(repository)
  vim.list_extend(args, {
    "-H",
    "Accept: application/vnd.github+json",
    "-H",
    "X-GitHub-Api-Version: 2022-11-28",
    ("repos/%s/issues?state=all&sort=updated&direction=desc&per_page=%d"):format(
      repository.slug,
      Common.clamp_limit(limit)
    ),
  })

  return Http.run("gh", args, callback)
end

local function request_rest(repository, endpoint, limit, callback)
  if endpoint.token ~= "" or vim.fn.executable("gh") == 0 then
    return request_rest_with_curl(repository, endpoint, limit, callback)
  end

  local cancelled = false
  local cancel = function() end
  cancel = request_rest_with_gh(repository, endpoint, limit, function(out)
    if cancelled then
      return
    end

    if out.code == 0 then
      callback(out)
      return
    end

    local gh_error = Http.error_message(out)
    cancel = request_rest_with_curl(repository, endpoint, limit, function(curl_out)
      if cancelled then
        return
      end

      if curl_out.code ~= 0 then
        curl_out.stderr = ("gh: %s; curl: %s"):format(gh_error, Http.error_message(curl_out))
      end

      callback(curl_out)
    end)
  end)

  return function()
    cancelled = true
    cancel()
  end
end

local function request_mentions_with_curl(repository, endpoint, limit, callback)
  local payload = vim.json.encode({
    query = MENTIONABLE_USERS_QUERY,
    variables = {
      owner = repository.owner,
      name = repository.name,
      limit = Common.clamp_limit(limit),
    },
  })

  if not endpoint.graphql then
    callback({
      code = -1,
      stdout = "",
      stderr = "GitHub GraphQL endpoint is not configured",
    })
    return function() end
  end

  local request_headers = headers(endpoint)
  request_headers["Content-Type"] = "application/json"

  return Http.request({
    url = endpoint.graphql,
    method = "POST",
    headers = request_headers,
    body = payload,
  }, callback)
end

local function request_mentions_with_gh(repository, limit, callback)
  local args = gh_api_args(repository)
  vim.list_extend(args, {
    "graphql",
    "-f",
    "query=" .. MENTIONABLE_USERS_QUERY,
    "-f",
    "owner=" .. repository.owner,
    "-f",
    "name=" .. repository.name,
    "-F",
    "limit=" .. tostring(Common.clamp_limit(limit)),
  })

  return Http.run("gh", args, callback)
end

local function request_mentions(repository, endpoint, limit, callback)
  if endpoint.token ~= "" then
    return request_mentions_with_curl(repository, endpoint, limit, callback)
  end

  if vim.fn.executable("gh") == 0 then
    callback({
      code = -1,
      stdout = "",
      stderr = "mention completion needs an endpoint token, GH_TOKEN/GITHUB_TOKEN, or authenticated gh",
    })
    return function() end
  end

  return request_mentions_with_gh(repository, limit, callback)
end

local function pull_request_state(issue)
  if issue.pull_request and issue.pull_request.merged_at then
    return "merged"
  end

  return issue.state or "unknown"
end

function M.items_from_issues(issues)
  local refs = {}

  for _, issue in ipairs(issues or {}) do
    local labels = {}

    for _, label in ipairs(issue.labels or {}) do
      table.insert(labels, type(label) == "table" and label.name or tostring(label))
    end

    local is_pull_request = issue.pull_request ~= nil
    table.insert(refs, {
      author = issue.user and issue.user.login,
      body = issue.body,
      kind = is_pull_request and "PR" or "Issue",
      labels = labels,
      number = issue.number,
      state = pull_request_state(issue),
      title = issue.title,
      updated_at = issue.updated_at,
    })
  end

  return Common.ref_items(refs)
end

function M.items_from_mentions(users)
  local mentions = {}

  for _, user in ipairs(users or {}) do
    table.insert(mentions, {
      bio = user.bio,
      name = user.name,
      url = user.url,
      username = user.login,
    })
  end

  return Common.mention_items(mentions)
end

function M.parse_issues(output)
  local body = Http.decode(output)

  if type(body) ~= "table" or body.message then
    return nil, type(body) == "table" and body.message or "GitHub returned invalid issue JSON"
  end

  return M.items_from_issues(body)
end

function M.parse_mentions(output)
  local body = Http.decode(output)

  if type(body) ~= "table" then
    return nil, "GitHub returned invalid mention JSON"
  end

  if type(body.errors) == "table" and body.errors[1] then
    return nil, body.errors[1].message or "GitHub GraphQL request failed"
  end

  local nodes = body.data
    and body.data.repository
    and body.data.repository.mentionableUsers
    and body.data.repository.mentionableUsers.nodes

  if type(nodes) ~= "table" then
    return nil, "GitHub returned no mentionable users"
  end

  return M.items_from_mentions(nodes)
end

function M.fetch(repository, endpoint, options, callback)
  local triggers = options.triggers or { "#", "@" }
  local requests = {}

  if vim.tbl_contains(triggers, "#") then
    table.insert(requests, function(done)
      return request_rest(repository, endpoint, options.limit, function(out)
        if out.code ~= 0 then
          done(nil, "issues/PRs: " .. Http.error_message(out))
          return
        end

        local items, err = M.parse_issues(out.stdout)
        done(items, err and "issues/PRs: " .. err or nil)
      end)
    end)
  end

  if vim.tbl_contains(triggers, "@") then
    table.insert(requests, function(done)
      return request_mentions(repository, endpoint, options.limit, function(out)
        if out.code ~= 0 then
          done(nil, "mentions: " .. Http.error_message(out))
          return
        end

        local items, err = M.parse_mentions(out.stdout)
        done(items, err and "mentions: " .. err or nil)
      end)
    end)
  end

  return Common.fetch_all(requests, callback)
end

return M
