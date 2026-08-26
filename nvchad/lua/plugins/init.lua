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
    "nvim-tree/nvim-tree.lua",
    opts = function(_, opts)
      opts.hijack_cursor = false
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
        "json", "yaml", "toml", "bash", "markdown",
      },
    },
  },
}
