-- ==============================================================
--  core/lazy.lua — plugin manager bootstrap (lazy.nvim)
-- ==============================================================

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'

-- Clone lazy.nvim if missing
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    'git', 'clone', '--filter=blob:none', '--branch=stable',
    'https://github.com/folke/lazy.nvim.git', lazypath,
  })
end

vim.opt.rtp:prepend(lazypath)

-- Setup and import all plugins under lua/plugins/
require('lazy').setup({
  { import = 'plugins' },
}, {
  ui = {
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      start = '🚀',
      lazy = '💤 ',
    },
  },
})

-- End of core/lazy.lua

