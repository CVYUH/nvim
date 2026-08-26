require("nvchad.configs.lspconfig").defaults()

-- Always-on servers: auto-attach on matching FileType at startup.
-- Currently none — every language is on-demand via its lang/<x>.lua module
-- (default-off + <Lang>Start / <Lang>Stop), so no LSP runs until asked.
-- To make one always-on, add it here, e.g.:
--   local servers = { "ts_ls" }
--   vim.lsp.enable(servers)

-- Per-language modules. Each file owns ALL its language's tooling —
-- LSP server config, on-demand start/stop commands, filetype detection,
-- DAP, formatters, debugger — so the whole language stack lives in one
-- place. Add a language by mirroring lang/rust.lua and requiring it here.
require("configs.lang.rust").setup()
require("configs.lang.typescript").setup()
require("configs.lang.python").setup()
require("configs.lang.go").setup()
require("configs.lang.terraform").setup()
require("configs.lang.c").setup()
-- require("configs.lang.java").setup()  -- future

-- read :h vim.lsp.config for changing options of lsp servers
