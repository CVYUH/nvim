require "nvchad.autocmds"

-- Register .tofu → terraform filetype at startup (before any file opens), so a
-- .tofu opened as the first file of a session still gets colors + terraformls.
-- Owned by lang/terraform.lua; invoked here only for early timing.
require("configs.lang.terraform").register_ft()

-- Patch nvim-treesitter master's #downcase! directive for Neovim 0.12 (fixes the
-- highlighter crash on terraform heredocs, bash, ruby, php). See the module.
require("configs.treesitter_fixes").setup()

-- nvim-tree cursor: rest on the filename's first char when moving between
-- entries (j/k), but leave horizontal moves (l/h) free so a long, truncated
-- name can be scrolled into view. Replaces nvim-tree's hijack_cursor, which
-- snapped on every move and blocked horizontal scroll (see lua/plugins/init.lua).
local nt_grp = vim.api.nvim_create_augroup("NvimTreeNameCursor", { clear = true })
local nt_last_line = -1
vim.api.nvim_create_autocmd("CursorMoved", {
  group = nt_grp,
  callback = function()
    if vim.bo.filetype ~= "NvimTree" then
      return
    end
    local line = vim.api.nvim_win_get_cursor(0)[1]
    if line == nt_last_line then
      return -- same line: horizontal move, leave the cursor free to scroll
    end
    nt_last_line = line
    local ok, api = pcall(require, "nvim-tree.api")
    if not ok then
      return
    end
    local node = api.tree.get_node_under_cursor()
    if not node or not node.name then
      return
    end
    -- Plain-text find so filenames with magic chars are matched literally.
    local col = vim.api.nvim_get_current_line():find(node.name, 1, true)
    if col then
      vim.api.nvim_win_set_cursor(0, { line, col - 1 })
    end
  end,
})
