-- ==============================================================
--  plugins/git.lua — Git signs and gutter integration
-- ==============================================================

return {
	"lewis6991/gitsigns.nvim",
	opts = {
		signs = {
			add = { text = "+" },
			change = { text = "~" },
			delete = { text = "_" },
			topdelete = { text = "‾" },
			changedelete = { text = "~" },
		},
	},
}

-- End of plugins/git.lua
