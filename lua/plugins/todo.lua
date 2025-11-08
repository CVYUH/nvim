-- ==============================================================
--  plugins/todo.lua — highlight TODO, FIXME, NOTE comments
-- ==============================================================

return {
	"folke/todo-comments.nvim",
	event = "VimEnter",
	dependencies = { "nvim-lua/plenary.nvim" },
	opts = { signs = false },
}

-- End of plugins/todo.lua
