-- ==============================================================
--  core/autocmds.lua — editor automation
-- ==============================================================

-- Highlight text after yanking (copy)
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- End of core/autocmds.lua

