-- ==============================================================
--  core/options.lua — basic editor settings
-- ==============================================================

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Set true if using Nerd Font in terminal
vim.g.have_nerd_font = true

-- Line numbers
vim.o.number = true

-- Mouse support
vim.o.mouse = "a"

-- Hide mode since statusline shows it
vim.o.showmode = false

-- Use system clipboard
vim.schedule(function()
	vim.o.clipboard = "unnamedplus"
end)

-- Indentation and undo
vim.o.breakindent = true
vim.o.undofile = true

-- Case-insensitive search unless capital letters used
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep sign column visible
vim.o.signcolumn = "yes"

-- Timing tweaks
vim.o.updatetime = 250
vim.o.timeoutlen = 300

-- Window behavior
vim.o.splitright = true
vim.o.splitbelow = true

-- Display invisible characters
vim.o.list = true
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- Preview substitutions live
vim.o.inccommand = "split"

-- Highlight current line
vim.o.cursorline = true

-- Keep some context around cursor
vim.o.scrolloff = 10

-- Confirm when quitting unsaved
vim.o.confirm = true

-- End of core/options.lua

-- ==============================================================
--  Filetype-specific indentation
-- ==============================================================

vim.api.nvim_create_autocmd("FileType", {
	pattern = { "java", "go", "c", "cpp" },
	callback = function()
		vim.bo.tabstop = 4
		vim.bo.shiftwidth = 4
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	pattern = { "javascript", "typescript", "json", "yaml", "lua" },
	callback = function()
		vim.bo.tabstop = 2
		vim.bo.shiftwidth = 2
	end,
})
