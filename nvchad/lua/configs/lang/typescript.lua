-- TypeScript / JavaScript language tooling — single source of truth.
--
-- LSP server (ts_ls / typescript-language-server) + on-demand commands.
-- Formatting (prettier) lives in conform; see configs/conform.lua.
--
-- cvyuh-systems has many separate TS/JS projects (dashboard, openbao/ui,
-- readme/docs-*, …), each with its own package.json/tsconfig.json. ts_ls
-- detects each project root independently, so touching files across projects
-- can spin up a ts_ls instance per root. Default-off keeps that opt-in.
--
-- Auto-start is OFF by default. :TSStart turns it on for current + future
-- TS/JS buffers, :TSStop kills the process(es) and disables auto-attach.

local M = {}

-- ts_ls attaches to all four; the Start re-trigger must match the same set.
local TS_FILETYPES = {
  typescript = true,
  typescriptreact = true,
  javascript = true,
  javascriptreact = true,
}

function M.setup()
  -- No per-project overrides today — ts_ls defaults are fine.

  -- Auto-attach OFF until :TSStart.
  vim.lsp.enable("ts_ls", false)

  vim.api.nvim_create_user_command("TSStart", function()
    vim.lsp.enable("ts_ls", true)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and TS_FILETYPES[vim.bo[buf].filetype] then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("doautocmd FileType")
        end)
      end
    end
    vim.notify("ts_ls: started", vim.log.levels.INFO)
  end, { desc = "Start ts_ls for TypeScript/JavaScript buffers" })

  vim.api.nvim_create_user_command("TSStop", function()
    vim.lsp.enable("ts_ls", false)
    local n = 0
    for _, c in ipairs(vim.lsp.get_clients({ name = "ts_ls" })) do
      c:stop(true)
      n = n + 1
    end
    vim.notify(("ts_ls: stopped (%d client(s))"):format(n), vim.log.levels.INFO)
  end, { desc = "Stop ts_ls and disable auto-attach" })

  -- TODO: DAP (js-debug) / eslint LSP when needed — keep all TS/JS tooling here.
end

return M
