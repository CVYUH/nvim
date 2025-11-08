-- ==============================================================
--  plugins/theme.lua — colorscheme setup
-- ==============================================================

return {
	{
		"folke/tokyonight.nvim",
		priority = 1000,
		config = function()
			-- choose one: "tokyonight", "tokyonight-night", "tokyonight-storm", "tokyonight-moon"
			vim.cmd.colorscheme("tokyonight-night")
		end,
	},
	{
		"ellisonleao/gruvbox.nvim",
		priority = 1000,
		config = function()
			require("gruvbox").setup({
				contrast = "hard",
				italic = { emphasis = false, strings = false, comments = false, operators = false, folds = false },
			})
			-- vim.cmd.colorscheme("gruvbox")
		end,
	},
	{
		"Mofiqul/vscode.nvim",
		priority = 1000,
		config = function()
			require("vscode").setup({
				transparent = false,
				italic_comments = false,
				disable_nvimtree_bg = true,
			})
			-- vim.cmd.colorscheme("vscode")
		end,
	},
	{
		"projekt0n/github-nvim-theme",
		priority = 1000,
		config = function()
			require("github-theme").setup({
				options = {
					transparent = false,
					hide_end_of_buffer = true,
					styles = { comments = "NONE", keywords = "NONE", functions = "NONE", variables = "NONE" },
				},
			})
			-- vim.cmd.colorscheme("github_dark_default")
		end,
	},
}
