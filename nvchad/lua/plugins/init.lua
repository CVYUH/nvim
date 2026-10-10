return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  {
    -- We want the cursor to REST on the filename's first char (tidy) yet still
    -- scroll a long, truncated name into view with `l`. NvChad's hijack_cursor
    -- snaps on EVERY move — including horizontal — so it blocks scrolling.
    -- Disable it here and instead snap-to-name only when the LINE changes,
    -- via a CursorMoved autocmd (see lua/autocmds.lua): j/k rest on the name,
    -- l/h scroll horizontally. Width stays at NvChad's default.
    --
    -- Gitignored files are SHOWN by default. nvim-tree hides them out of the
    -- box, which quietly lies about a tree whose real per-machine config —
    -- infra/local/box.yaml, lan.yaml — is gitignored on purpose. `shift-i`
    -- still toggles them off when the noise is unwanted; `shift-h` does the
    -- same for dotfiles.
    "nvim-tree/nvim-tree.lua",
    opts = function(_, opts)
      opts.hijack_cursor = false
      opts.filters = vim.tbl_extend("force", opts.filters or {}, {
        git_ignored = false,
      })
      -- Showing ignored files makes every repo's status walk its ignored
      -- trees; the Java forks take ~400ms warm, which is the default timeout,
      -- and five timeouts switch git off for the session. Upstream reference
      -- clones are browsed, not edited, so they get no status at all.
      opts.git = vim.tbl_extend("force", opts.git or {}, {
        timeout = 3000,
        disable_for_dirs = function(path)
          return path:find("/cvyuh%-systems/_inspirations/") ~= nil
            or path:find("/cvyuh%-systems/wazuh$") ~= nil
        end,
      })
      return opts
    end,
  },

  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  {
    "williamboman/mason.nvim",
    -- Tool list lives in mason-tool-installer below. Mason v2 ignores
    -- ensure_installed here, which is why nothing ever auto-installed.
    opts = {},
  },

  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "williamboman/mason.nvim" },
    -- NvChad sets defaults.lazy = true, so without a trigger this never loads
    -- (and setup() never registers its commands / auto-install). Load early.
    event = "VeryLazy",
    opts = {
      -- Single source of truth for CLI tooling (LSP servers + formatters).
      -- Auto-installs anything missing at startup; :MasonToolsUpdate refreshes.
      -- rust-analyzer is intentionally NOT here: it comes from rustup as a
      -- toolchain-matched component (see configs/lang/rust.lua).
      ensure_installed = {
        "lua-language-server", "stylua",
        "gopls", "goimports",
        "typescript-language-server", "prettier",
        "terraform-ls",
        "pyright", "ruff",
        -- clangd only. No clang-format: postgres formats with its own
        -- pgindent, so C is deliberately absent from configs/conform.lua.
        "clangd",
      },
      run_on_start = true,
    },
  },

  {
    -- In-buffer markdown rendering: headings, tables, code blocks, lists,
    -- callouts, all drawn in the terminal. Pure Lua — no node, no browser, no
    -- server — so it is the one view that works over ssh and on every .md.
    -- Raw text comes back in insert mode and on the cursor's own line, so
    -- editing always sees the source.
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    ft = { "markdown" },
    opts = {},
  },

  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    opts = {
      ensure_installed = {
        "lua", "vim", "vimdoc",
        "rust",
        "go", "gomod", "gosum",
        "typescript", "javascript", "tsx",
        "hcl", "terraform",
        "python",
        "c",
        -- markdown_inline is a separate parser for what sits *inside* a line
        -- (links, emphasis, code spans). Without it render-markdown draws the
        -- block structure and leaves every inline span as raw text.
        "json", "yaml", "toml", "bash", "markdown", "markdown_inline",
      },
    },
  },
}
