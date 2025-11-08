-- ==============================================================
--  plugins/osc52.lua — copy over SSH to local clipboard
-- ==============================================================

return {
	"ojroques/nvim-osc52",
	event = "VeryLazy",
	config = function()
		require("osc52").setup({})
		-- Auto-copy yanks to local clipboard over SSH (OSC52)
		vim.api.nvim_create_autocmd("TextYankPost", {
			callback = function()
				if vim.v.event.operator == "y" and (vim.v.event.regname == "" or vim.v.event.regname == "+") then
					require("osc52").copy_register("+")
				end
			end,
		})
	end,
}
