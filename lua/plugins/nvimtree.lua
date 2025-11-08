-- ==============================================================
--  plugins/nvimtree.lua — file explorer
-- ==============================================================

return {
	"nvim-tree/nvim-tree.lua",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	cmd = { "NvimTreeToggle", "NvimTreeFocus" },
	keys = {
		{ "<leader>e", "<cmd>NvimTreeToggle<CR>", desc = "Toggle file explorer" },
	},
	opts = {
		sort_by = "case_sensitive",
		view = { width = 30, side = "left" },
		renderer = { group_empty = true },
		filters = { dotfiles = false },
		git = { enable = true, ignore = false },
	},
}
