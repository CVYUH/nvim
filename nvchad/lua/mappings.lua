require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- Markdown. Rendering is on by default; this drops back to the raw source.
map("n", "<leader>mr", "<cmd>RenderMarkdown toggle<cr>", { desc = "Markdown render in buffer" })

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
