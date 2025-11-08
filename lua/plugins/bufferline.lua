-- ==============================================================
--  plugins/bufferline.lua — show open buffers like VS Code tabs
-- ==============================================================

return {
	"akinsho/bufferline.nvim",
	version = "*",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	opts = {
		options = {
			mode = "buffers",
			diagnostics = "nvim_lsp",
			show_buffer_close_icons = false,
			show_close_icon = false,
			separator_style = "slant",
			always_show_bufferline = true,
		},
	},
	keys = {
		{ "<leader>bb", "<cmd>enew<CR>", desc = "New buffer" },
		{ "<leader>bp", "<cmd>BufferLineCyclePrev<CR>", desc = "Previous buffer" },
		{ "<leader>bn", "<cmd>BufferLineCycleNext<CR>", desc = "Next buffer" },
	},
}
