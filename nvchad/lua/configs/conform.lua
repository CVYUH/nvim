local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    rust = { "rustfmt" },
    go = { "goimports", "gofmt" },
    javascript = { "prettier" },
    typescript = { "prettier" },
    javascriptreact = { "prettier" },
    typescriptreact = { "prettier" },
    json = { "prettier" },
    yaml = { "prettier" },
    markdown = { "prettier" },
    terraform = { "tofu_fmt" },
    hcl = { "tofu_fmt" },
    python = { "ruff_format" },
  },

  -- format_on_save = {
  --   timeout_ms = 500,
  --   lsp_fallback = true,
  -- },
}

vim.api.nvim_create_user_command("Format", function(args)
  local range = nil
  if args.count ~= -1 then
    range = { start = { args.line1, 0 }, ["end"] = { args.line2, math.huge } }
  end
  require("conform").format({ async = true, lsp_fallback = true, range = range })
end, { range = true, desc = "Format buffer or range via conform" })

return options
