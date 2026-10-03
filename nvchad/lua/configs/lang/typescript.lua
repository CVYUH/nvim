-- TypeScript / JavaScript language tooling — single source of truth.
--
-- LSP server (ts_ls / typescript-language-server) + on-demand commands.
-- Formatting (prettier) lives in conform; see configs/conform.lua.
--
-- cvyuh-systems has many separate TS/JS projects (dashboard, dashboard1, openbao/ui,
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

-- ts_ls is the one server here whose cmd is a FUNCTION, not a fixed list:
-- lspconfig prefers <root>/node_modules/.bin/typescript-language-server and
-- only falls back to the global one. A bare PATH check would therefore refuse
-- to start on a project that vendors the server locally — the common case in
-- this repo, where dashboard/, dashboard1/, openbao/ui/ and readme/docs-* each carry their
-- own node_modules. So check the project-local path too before giving up.
local function server_available()
  if vim.fn.executable("typescript-language-server") == 1 then
    return true
  end
  -- pcall: vim.fs.root works off the buffer's NAME, so an unnamed scratch
  -- buffer (or a brand-new session) has nothing to resolve against. Treat
  -- that as "no local copy" rather than letting it raise inside the command.
  local ok, root = pcall(vim.fs.root, 0, { "package.json", "tsconfig.json" })
  if not ok or not root then
    return false
  end
  local local_bin =
    vim.fs.joinpath(root, "node_modules", ".bin", "typescript-language-server")
  return vim.uv.fs_stat(local_bin) ~= nil
end

function M.setup()
  -- No per-project overrides today — ts_ls defaults are fine.

  -- Auto-attach OFF until :TSStart.
  vim.lsp.enable("ts_ls", false)

  vim.api.nvim_create_user_command("TSStart", function()
    -- Refuse loudly rather than reporting success we cannot verify.
    -- vim.lsp.enable() only flips auto-attach; with no binary reachable the
    -- client spawn fails out of band, so a bare "ts_ls: started" notify is
    -- indistinguishable from a working server that simply cannot answer.
    if not server_available() then
      vim.notify(
        "ts_ls: typescript-language-server not found — nothing was started.\n"
          .. "Checked PATH and this project's node_modules/.bin.\n"
          .. "Install it with :MasonToolsInstall (it is in ensure_installed),\n"
          .. "or add it to the project: npm i -D typescript-language-server.",
        vim.log.levels.ERROR
      )
      return
    end

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
