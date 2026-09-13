-- Markdown tooling — single source of truth.
--
-- Rendering itself is render-markdown.nvim (see lua/plugins/init.lua): it draws
-- in the buffer, on by default, and <leader>mr drops back to the raw source.
-- All this file adds is wrapping, because 16% of the repo's markdown lines run
-- past 120 columns and its tables reach four figures — unwrapped, they scroll
-- off the window instead of rendering.
--
-- No LSP here, which is why setup() is called from autocmds.lua at startup
-- rather than from lspconfig.lua alongside the languages that have a server.

local M = {}

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("MarkdownBuffer", { clear = true }),
    pattern = { "markdown" },
    callback = function()
      vim.opt_local.wrap = true
      vim.opt_local.linebreak = true -- break on words, not mid-word
    end,
  })
end

return M
