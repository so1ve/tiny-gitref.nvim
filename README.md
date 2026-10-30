# tiny-gitref.nvim

Multi-provider issue, pull request, and mention completion for Neovim.

It completes references with `#` and users with `@` in comments, commit messages, Markdown, and Octo buffers. GitHub is one provider rather than the data model: GitLab and Forgejo/Gitea use the same completion path through their own adapters.

## Why

`blink-cmp-git` is GitHub-specific and uses endpoints that omit closed items. Its `@` completion uses contributors rather than the users GitHub allows you to mention.

tiny-gitref.nvim keeps retrieval rules in small provider adapters:

- GitHub reads `/issues?state=all`, so open, closed, and merged items remain available.
- GitHub mentions come from GraphQL `repository.mentionableUsers`.
- GitLab reads issues and merge requests with `state=all`, and mentions come from project members.
- Forgejo/Gitea reads issues and pull requests with `state=all`, and mentions come from repository assignees.
- A remote host without an explicit provider is rejected instead of being guessed as GitHub Enterprise.
- Completion only starts from a real comment, a configured filetype, or a commit message.

## Built-in providers

| Host | Provider | API root | Default token variables |
| --- | --- | --- | --- |
| `github.com` | `github` | `https://api.github.com` | `GH_TOKEN`, `GITHUB_TOKEN` |
| `gitlab.com` | `gitlab` | `https://gitlab.com/api/v4` | `GITLAB_TOKEN`, `PRIVATE_TOKEN` |
| `codeberg.org` | `forgejo` | `https://codeberg.org/api/v1` | `CODEBERG_TOKEN`, `FORGEJO_TOKEN`, `GITEA_TOKEN` |
| `gitea.com` | `forgejo` | `https://gitea.com/api/v1` | `GITEA_TOKEN`, `FORGEJO_TOKEN` |

GitHub and GitLab also work on self-hosted instances when their host is added under `endpoints`. Forgejo and Gitea can use either provider name.

Bitbucket and SourceHut do not have built-in adapters yet. Their APIs need separate providers; arbitrary `api` overrides alone are not enough.

## Requirements

- Neovim 0.13+
- `git`
- `curl`
- `gh` for authenticated GitHub mentions when no GitHub token is configured

Issue and pull request lookup falls back to unauthenticated requests where the platform permits it. Private repositories and most mention lookups need a provider token or the platform's authenticated CLI.

GitLab project members and Forgejo/Gitea assignees return `401` without authentication, so configure their endpoint token to use `@` completion. Public `#` completion still works in projects that allow anonymous API access.

## Installation

### `lazy.nvim`

```lua
{
  "so1ve/tiny-gitref.nvim",
  dependencies = {
    "saghen/blink.cmp",
  },
  opts = {},
}
```

### `vim.pack`

```lua
vim.pack.add({
  { src = "https://github.com/so1ve/tiny-gitref.nvim" },
}, { confirm = false, load = false })
```

## Usage

Register tiny-gitref as a blink.cmp source:

```lua
require("tiny-gitref").setup()

require("blink.cmp").setup({
  sources = {
    default = { "gitref", "lsp", "path", "snippets", "buffer" },
    providers = {
      gitref = {
        module = "tiny-gitref",
        name = "GitRef",
      },
    },
  },
})
```

By default, `setup()` schedules Blink's `gitref` provider preload and retries briefly while Blink finishes initializing. This makes the first `#` immediate without the manual `vim.schedule()` block.

Use `#` in a comment, commit message, Markdown, or Octo buffer:

```yaml
#11 feat: implement new feature
#3  Renovate Dependency Dashboard
```

Use `@` for users the provider can mention:

```text
Review requested from @octocat.
```

Refresh cached data after changing remotes or authentication:

```vim
:GitRefReload
```

## Configuration

```lua
require("tiny-gitref").setup({
  filetypes = { "gitcommit", "markdown", "octo" },
  triggers = { "#", "@" },
  limit = 100,
  preload_provider = true,
  remote = "origin",
  endpoints = {
    -- Only the provider is required. The API root becomes
    -- https://git.example.com/api/v1.
    ["git.example.com"] = "forgejo",

    -- Override the API root when it is not at the platform default.
    ["gitlab.example.com"] = {
      provider = "gitlab",
      api = "https://gitlab.example.com/api/v4",
      token = function()
        return vim.env.GITLAB_TOKEN or ""
      end,
    },

    ["ghe.example.com"] = {
      provider = "github",
      api = "https://ghe.example.com/api/v3",
      graphql = "https://ghe.example.com/api/graphql",
      token = function()
        return vim.env.GH_ENTERPRISE_TOKEN or ""
      end,
    },
  },
})
```

| Option | Default | Description |
| --- | --- | --- |
| `endpoints` | `{}` | Per-host provider selection, API root, and authentication. |
| `filetypes` | `{ "gitcommit", "markdown", "octo" }` | Filetypes where completion is always allowed. |
| `triggers` | `{ "#", "@" }` | Completion trigger characters. |
| `limit` | `100` | Maximum items requested from each endpoint. |
| `preload_provider` | `true` | Preload Blink's `gitref` provider during setup so the first trigger is immediate. |
| `remote` | `"origin"` | Git remote used to find the repository. |

Endpoint fields:

| Field | Required | Description |
| --- | --- | --- |
| `provider` | For custom hosts | `github`, `gitlab`, `forgejo`, or `gitea`. |
| `api` | No | API root override. The provider supplies a host-based default. |
| `graphql` | No | GitHub GraphQL endpoint override. |
| `token` | No | Endpoint-only string or function. It is never a top-level option. |

Without an explicit endpoint token, each provider reads its default environment variables from the table above. Configuring `token` on one endpoint does not apply it to another host.

Other buffers use Tree-sitter comment captures. As a fallback for the first character typed before a parser updates, tiny-gitref also checks the buffer's `commentstring` marker.

## API

### `setup(opts?)`

Stores configuration, defines `:GitRefReload`, and preloads the Blink provider by default. Set `preload_provider = false` if another startup path owns provider loading. A top-level `token` option raises an error; configure `endpoints[host].token` instead.

### `reload()`

Reloads data for every active Blink source.

```lua
require("tiny-gitref").reload()
```

The module also exposes `new(opts)` for blink.cmp providers. The provider module is `tiny-gitref`, and the source ID is `gitref`.

## Notes

References and mentions share one cache per active repository. tiny-gitref preloads the current repository when Blink creates the source and reloads when insert mode starts in a different repository.

GitLab merge requests use `iid` for the `#number` shown in the project. Forgejo pull requests normalize a merged pull request to the `merged` state even though its API reports it as closed.

## 📝 License

[MIT](./LICENSE). Made with ❤️ by [Ray](https://github.com/so1ve)
