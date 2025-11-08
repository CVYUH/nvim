-- ==============================================================
--  plugins/theme.lua — colorscheme setup
-- ==============================================================

return {
	{
		"folke/tokyonight.nvim",
		priority = 1000,
	},
	{
		"ellisonleao/gruvbox.nvim",
		priority = 1000,
		config = function()
			require("gruvbox").setup({
				contrast = "hard", -- options: soft, medium, hard
				italic = {
					strings = false,
					comments = false,
					operators = false,
					folds = false,
				},
			})
			vim.cmd.colorscheme("gruvbox")
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
			--vim.cmd.colorscheme("vscode")
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
					styles = {
						comments = "NONE",
						keywords = "NONE",
						functions = "NONE",
						variables = "NONE",
					},
				},
			})
			--vim.cmd.colorscheme("github_dark_default") -- default; try github_light_default too
		end,
	},
}
