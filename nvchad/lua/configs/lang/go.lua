-- Go language tooling — single source of truth.
--
-- LSP server config + on-demand commands consolidated here. DAP / formatters
-- land here too (one place for all Go tooling).
--
-- Auto-start is OFF by default. :GOStart turns it on for current + future
-- Go buffers, :GOStop kills the process and disables auto-attach.

local M = {}

function M.setup()
  -- No per-project overrides today — gopls defaults are fine. When we need
  -- them (e.g. build tags, workspace settings) register via:
  --   vim.lsp.config('gopls', { settings = { gopls = { ... } } })

  -- Auto-attach OFF until :GOStart.
  vim.lsp.enable("gopls", false)

  vim.api.nvim_create_user_command("GOStart", function()
    vim.lsp.enable("gopls", true)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "go" then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("doautocmd FileType")
        end)
      end
    end
    vim.notify("gopls: started", vim.log.levels.INFO)
  end, { desc = "Start gopls for Go buffers" })

  vim.api.nvim_create_user_command("GOStop", function()
    vim.lsp.enable("gopls", false)
    local n = 0
    for _, c in ipairs(vim.lsp.get_clients({ name = "gopls" })) do
      c:stop(true)
      n = n + 1
    end
    vim.notify(("gopls: stopped (%d client(s))"):format(n), vim.log.levels.INFO)
  end, { desc = "Stop gopls and disable auto-attach" })

  -- TODO: DAP (delve) when needed — keep all Go tooling in this file.
end

return M
