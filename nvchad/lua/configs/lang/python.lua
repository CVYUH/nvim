-- Python language tooling — single source of truth.
--
-- LSP server (pyright) + on-demand commands. Linting/formatting via ruff
-- lives in conform; see configs/conform.lua (python = ruff_format).
--
-- Auto-start is OFF by default. :PYStart turns it on for current + future
-- Python buffers, :PYStop kills the process and disables auto-attach.

local M = {}

function M.setup()
  -- No per-project overrides today — pyright defaults are fine.

  -- Auto-attach OFF until :PYStart.
  vim.lsp.enable("pyright", false)

  vim.api.nvim_create_user_command("PYStart", function()
    vim.lsp.enable("pyright", true)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "python" then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("doautocmd FileType")
        end)
      end
    end
    vim.notify("pyright: started", vim.log.levels.INFO)
  end, { desc = "Start pyright for Python buffers" })

  vim.api.nvim_create_user_command("PYStop", function()
    vim.lsp.enable("pyright", false)
    local n = 0
    for _, c in ipairs(vim.lsp.get_clients({ name = "pyright" })) do
      c:stop(true)
      n = n + 1
    end
    vim.notify(("pyright: stopped (%d client(s))"):format(n), vim.log.levels.INFO)
  end, { desc = "Stop pyright and disable auto-attach" })

  -- TODO: DAP (debugpy) when needed — keep all Python tooling in this file.
end

return M
