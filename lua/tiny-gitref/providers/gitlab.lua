local Common = require("tiny-gitref.common")
local Http = require("tiny-gitref.http")

local M = {
  name = "gitlab",
  token_env = { "GITLAB_TOKEN", "PRIVATE_TOKEN" },
}

function M.default_api(repository)
  return ("https://%s/api/v4"):format(repository.host)
end

function M.urls(repository, endpoint, limit)
  local project = Common.encode_uri_component(repository.slug)
  local base = ("%s/projects/%s"):format(endpoint.api, project)
  local amount = Common.clamp_limit(limit)

  return {
    issues = ("%s/issues?state=all&per_page=%d&order_by=updated_at&sort=desc"):format(base, amount),
    merge_requests = ("%s/merge_requests?state=all&per_page=%d&order_by=updated_at&sort=desc"):format(base, amount),
    members = ("%s/members/all?per_page=%d"):format(base, amount),
  }
end

local function headers(endpoint)
  local result = { Accept = "application/json" }

  if endpoint.token ~= "" then
    result["PRIVATE-TOKEN"] = endpoint.token
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
      author = issue.author and issue.author.username,
      body = issue.description,
      kind = "Issue",
      labels = labels_from(issue),
      number = issue.iid,
      state = issue.state,
      title = issue.title,
      updated_at = issue.updated_at,
    })
  end

  return Common.ref_items(refs)
end

function M.items_from_merge_requests(merge_requests)
  local refs = {}

  for _, merge_request in ipairs(merge_requests or {}) do
    table.insert(refs, {
      author = merge_request.author and merge_request.author.username,
      body = merge_request.description,
      kind = "MR",
      labels = labels_from(merge_request),
      number = merge_request.iid,
      state = merge_request.state,
      title = merge_request.title,
      updated_at = merge_request.updated_at,
    })
  end

  return Common.ref_items(refs)
end

function M.items_from_members(members)
  local users = {}

  for _, member in ipairs(members or {}) do
    table.insert(users, {
      bio = member.bio,
      name = member.name,
      url = member.web_url,
      username = member.username,
    })
  end

  return Common.mention_items(users)
end

local function decode_list(output, subject, build_items)
  local body = Http.decode(output)

  if type(body) ~= "table" or body.message then
    return nil, type(body) == "table" and body.message or ("GitLab returned invalid %s JSON"):format(subject)
  end

  return build_items(body)
end

function M.parse_issues(output)
  return decode_list(output, "issue", M.items_from_issues)
end

function M.parse_merge_requests(output)
  return decode_list(output, "merge request", M.items_from_merge_requests)
end

function M.parse_members(output)
  return decode_list(output, "member", M.items_from_members)
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
      return request(urls.merge_requests, endpoint, function(out)
        if out.code ~= 0 then
          done(nil, "merge requests: " .. Http.error_message(out))
          return
        end

        local items, err = M.parse_merge_requests(out.stdout)
        done(items, err and "merge requests: " .. err or nil)
      end)
    end)
  end

  if vim.tbl_contains(triggers, "@") then
    table.insert(requests, function(done)
      return request(urls.members, endpoint, function(out)
        if out.code ~= 0 then
          done(nil, "mentions: " .. Http.error_message(out))
          return
        end

        local items, err = M.parse_members(out.stdout)
        done(items, err and "mentions: " .. err or nil)
      end)
    end)
  end

  return Common.fetch_all(requests, callback)
end

return M
