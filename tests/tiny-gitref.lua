vim.opt.runtimepath:append(vim.fn.getcwd())

local Config = require("tiny-gitref.config")
local Forgejo = require("tiny-gitref.providers.forgejo")
local GitHub = require("tiny-gitref.providers.github")
local GitLab = require("tiny-gitref.providers.gitlab")
local Position = require("tiny-gitref.position")
local Provider = require("tiny-gitref.provider")
local Repository = require("tiny-gitref.repository")
local Source = require("tiny-gitref.source")
local TinyGitRef = require("tiny-gitref")

local function assert_equal(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error(("%s\nexpected: %s\nactual: %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local repository = Repository.parse_remote("ssh://git@ssh.github.com:443/so1ve/tiny-gitref.nvim.git")
assert_equal(repository.host, "github.com", "SSH GitHub hosts should normalize")
assert_equal(repository.slug, "so1ve/tiny-gitref.nvim", "repository slugs should parse")

repository = Repository.parse_remote("git@github.com:so1ve/tiny-gitref.nvim.git")
assert_equal(repository.slug, "so1ve/tiny-gitref.nvim", "SCP-style remotes should parse")

repository = Repository.parse_remote("git@gitlab.com:group/subgroup/project.git")
assert_equal(repository.owner, "group/subgroup", "nested GitLab namespaces should parse")
assert_equal(repository.name, "project", "nested repository names should parse")

local commit_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(commit_buffer, "/home/ray/Develop/tiny-gitref.nvim/.git/COMMIT_EDITMSG")
assert_equal(
  Repository.root_for_buffer(commit_buffer),
  "/home/ray/Develop/tiny-gitref.nvim",
  "commit message buffers should map back to the repository root"
)

Config.setup()
local github_repository = Repository.parse_remote("git@github.com:so1ve/tiny-gitref.nvim.git")
local endpoint = Provider.resolve(github_repository, Config.options)
assert_equal(endpoint.name, "github", "GitHub hosts should resolve to the GitHub provider")
assert_equal(endpoint.api, "https://api.github.com", "GitHub API endpoints should resolve")
assert_equal(endpoint.graphql, "https://api.github.com/graphql", "GitHub GraphQL endpoints should resolve")

local gitlab_repository = Repository.parse_remote("git@gitlab.com:group/subgroup/project.git")
endpoint = Provider.resolve(gitlab_repository, Config.options)
assert_equal(endpoint.name, "gitlab", "GitLab hosts should resolve to the GitLab provider")
assert_equal(endpoint.api, "https://gitlab.com/api/v4", "GitLab API endpoints should resolve")

local gitlab_urls = GitLab.urls(gitlab_repository, endpoint, 50)
assert_equal(
  gitlab_urls.issues,
  "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/issues"
    .. "?state=all&per_page=50&order_by=updated_at&sort=desc",
  "GitLab project paths should be URL encoded"
)

local codeberg_repository = Repository.parse_remote("git@codeberg.org:forgejo/forgejo.git")
endpoint = Provider.resolve(codeberg_repository, Config.options)
assert_equal(endpoint.name, "forgejo", "Codeberg hosts should resolve to the Forgejo provider")
assert_equal(endpoint.api, "https://codeberg.org/api/v1", "Codeberg API endpoints should resolve")

local forgejo_urls = Forgejo.urls(codeberg_repository, endpoint, 100)
assert_equal(
  forgejo_urls.issues,
  "https://codeberg.org/api/v1/repos/forgejo/forgejo/issues?state=all&type=issues&limit=100",
  "Forgejo issue URLs should use the v1 API"
)
assert_equal(
  forgejo_urls.assignees,
  "https://codeberg.org/api/v1/repos/forgejo/forgejo/assignees?limit=100",
  "Forgejo mentions should use assignees"
)

local unknown_repository = Repository.parse_remote("git@git.example.com:team/project.git")
local unknown_endpoint, unknown_err = Provider.resolve(unknown_repository, Config.options)
assert_equal(unknown_endpoint, nil, "Unknown hosts should not be guessed")
assert(unknown_err:find("endpoints", 1, true), "Unknown hosts should explain endpoint configuration")

Config.setup({
  endpoints = {
    ["git.example.com"] = "forgejo",
  },
})
endpoint = Provider.resolve(unknown_repository, Config.options)
assert_equal(endpoint.name, "forgejo", "Endpoint shorthands should select a provider")
assert_equal(endpoint.api, "https://git.example.com/api/v1", "Forgejo endpoints should derive the v1 API")

local enterprise_repository = Repository.parse_remote("git@ghe.example.com:team/project.git")
Config.setup({
  endpoints = {
    ["ghe.example.com"] = "github",
  },
})
endpoint = Provider.resolve(enterprise_repository, Config.options)
assert_equal(endpoint.api, "https://ghe.example.com/api/v3", "GitHub Enterprise REST endpoints should derive")
assert_equal(
  endpoint.graphql,
  "https://ghe.example.com/api/graphql",
  "GitHub Enterprise GraphQL endpoints should derive"
)

local token_called = false
Config.setup({
  endpoints = {
    ["git.example.com"] = {
      provider = "forgejo",
      api = "https://forge.example.net/custom/api/v1/",
      token = function()
        token_called = true
        return "secret"
      end,
    },
  },
})
endpoint = Provider.resolve(unknown_repository, Config.options)
assert_equal(token_called, true, "Endpoint token callbacks should be evaluated")
assert_equal(endpoint.api, "https://forge.example.net/custom/api/v1", "Custom API endpoints should be normalized")
assert_equal(endpoint.token, "secret", "Tokens should come from endpoint configuration")
assert_equal(Config.defaults.token, nil, "There should be no top-level token option")
local ok = pcall(Config.setup, {
  token = function()
    return "invalid"
  end,
})
assert_equal(ok, false, "top-level token configuration should be rejected")
ok = pcall(Config.get, {
  token = "invalid",
})
assert_equal(ok, false, "top-level token overrides should be rejected")

Config.setup()
local items = GitHub.items_from_issues({
  {
    number = 12,
    title = "Keep closed issues searchable",
    state = "closed",
    body = "Closed issue body",
    labels = { { name = "bug" } },
    user = { login = "so1ve" },
  },
  {
    number = 8,
    title = "Use mentionableUsers",
    state = "closed",
    pull_request = { merged_at = "2026-10-31T00:00:00Z" },
  },
})

assert_equal(items[1].insert_text, "#12", "closed issues should insert #12")
assert_equal(items[2].kind_name, "PR", "pull requests should be labeled as PRs")
assert_equal(items[2].detail, "PR - merged", "merged pull requests should show their state")

local mentions = GitHub.items_from_mentions({ { login = "octocat", name = "The Octocat" } })
assert_equal(mentions[1].insert_text, "@octocat", "mentions should insert @login")

items = GitLab.items_from_issues({
  {
    author = { username = "alice" },
    description = "GitLab issue",
    iid = 7,
    labels = { "bug" },
    state = "closed",
    title = "Handle GitLab issues",
  },
})
assert_equal(items[1].insert_text, "#7", "GitLab issues should use iid")

items = GitLab.items_from_merge_requests({
  {
    iid = 9,
    state = "merged",
    title = "Merge support",
  },
})
assert_equal(items[1].kind_name, "MR", "GitLab merge requests should be labeled as MRs")
assert_equal(items[1].detail, "MR - merged", "GitLab merge request states should be preserved")

items = Forgejo.items_from_pulls({
  {
    merged = true,
    number = 11,
    state = "closed",
    title = "Forgejo pull request",
  },
})
assert_equal(items[1].kind_name, "PR", "Forgejo pull requests should be labeled as PRs")
assert_equal(items[1].detail, "PR - merged", "Forgejo merged state should be normalized")

mentions = Forgejo.items_from_assignees({
  {
    full_name = "Forge User",
    login = "forge-user",
  },
})
assert_equal(mentions[1].insert_text, "@forge-user", "Forgejo assignees should provide mentions")

Config.setup({ triggers = { "#" } })
assert_equal(Config.options.triggers, { "#" }, "list options should replace defaults")
Config.setup({ preload_provider = false })
assert_equal(Config.options.preload_provider, false, "Blink provider preloading should be configurable")
Config.setup()

assert_equal(Config.defaults.preload_provider, true, "Blink provider preloading should be enabled by default")
local preload_attempts = 0
local preloaded_provider
package.loaded["blink.cmp.sources.lib"] = {
  get_provider_by_id = function(id)
    preload_attempts = preload_attempts + 1

    if preload_attempts == 1 then
      error("blink.cmp is not initialized yet")
    end

    preloaded_provider = id
    return {}
  end,
}

TinyGitRef.setup()
TinyGitRef.setup()
assert(vim.wait(1000, function()
  return preloaded_provider == "gitref"
end), "Blink should preload the gitref provider after retrying")
assert_equal(preload_attempts, 2, "provider preloading should retry until Blink is ready")

local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "#" })
vim.bo[buffer].filetype = "yaml"
vim.bo[buffer].commentstring = "# %s"
assert_equal(Position.is_allowed(buffer, 0, "#", 1, {}), true, "comment markers should allow completion")

vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "https://github.com" })
vim.bo[buffer].filetype = "lua"
vim.bo[buffer].commentstring = "// %s"
assert_equal(Position.is_allowed(buffer, 0, "https://github.com", 20, {}), false, "URLs should not look like comments")

local source_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(source_buffer, "/tmp/tiny-gitref-no-repo/test.yaml")
vim.api.nvim_set_current_buf(source_buffer)
local source = Source.new({})
assert(vim.wait(1000, function()
  return source.ready
end), "a source outside a repository should become ready")

local called = false
source:get_completions({
  mode = "default",
  bufnr = source_buffer,
  line = "#",
  cursor = { 1, 1 },
  trigger = { initial_character = "#" },
}, function(response)
  called = true
  assert_equal(response.items, {}, "a source outside a repository should return no items")
end)
assert_equal(called, true, "completion outside a repository should still call back")

vim.api.nvim_out_write("tiny-gitref tests passed\n")
