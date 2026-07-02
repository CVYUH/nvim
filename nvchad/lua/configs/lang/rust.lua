-- Rust language tooling — single source of truth.
--
-- LSP server config + on-demand commands consolidated here. DAP / formatters /
-- debugger setup land here too (one place for all Rust tooling).
--
-- Why one analyzer for everything: cvyuh-systems holds 8 separate Cargo
-- roots (cvyuh-libs is a workspace; the 7 services are single-crate). The
-- upstream rust_analyzer config detects per-crate workspace_root via
-- `cargo metadata`, which spawns a fresh rust-analyzer per detected root —
-- multiple instances at ~6–7 GB each. This setup:
--   * Pins root_dir to ~/code/cvyuh-systems for any buffer under that tree,
--     so every Rust buffer attaches to the SAME LSP client (one process).
--   * Lists all 8 Cargo.tomls under settings.linkedProjects so rust-analyzer
--     loads them as one combined view — cross-crate goto-def works, no
--     re-analysis when switching crates.
--   * Adds explicit reuse_client so any rust_analyzer client whose root
--     falls under cvyuh-systems folds into the single shared instance.
--   * Falls back to standard per-Cargo.toml root for buffers outside
--     cvyuh-systems (other Rust projects keep working normally).
--
-- Auto-start is OFF by default — at ~6 GB on this workspace, only run when
-- needed. :RAStart turns it on for current + future Rust buffers, :RAStop
-- kills the process and disables auto-attach.

local M = {}

local CVYUH_ROOT = vim.fs.normalize(vim.fn.expand('~/code/cvyuh-systems'))

local LINKED_PROJECTS = {
  CVYUH_ROOT .. '/cvyuh-libs/Cargo.toml',
  CVYUH_ROOT .. '/fabrik/Cargo.toml',
  CVYUH_ROOT .. '/scribe/Cargo.toml',
  CVYUH_ROOT .. '/idm2/Cargo.toml',
  CVYUH_ROOT .. '/interceptor/Cargo.toml',
  CVYUH_ROOT .. '/platform-test/Cargo.toml',
  CVYUH_ROOT .. '/provision/Cargo.toml',
  CVYUH_ROOT .. '/relay/Cargo.toml',
  CVYUH_ROOT .. '/rna/Cargo.toml',
}

local function under_cvyuh(path)
  if not path or path == '' then return false end
  local n = vim.fs.normalize(path)
  -- Resolve any symlinks so two physical paths to the same dir compare equal.
  local resolved = vim.uv.fs_realpath(n) or n
  return resolved:sub(1, #CVYUH_ROOT) == CVYUH_ROOT
end

function M.setup()
  -- Register server config (replaces the old ~/.config/nvim/lsp/rust_analyzer.lua).
  vim.lsp.config('rust_analyzer', {
    root_dir = function(bufnr, on_dir)
      local fname = vim.api.nvim_buf_get_name(bufnr)
      if under_cvyuh(fname) then
        on_dir(CVYUH_ROOT)
        return
      end
      local cargo = vim.fs.root(fname, { 'Cargo.toml' })
      on_dir(cargo or vim.fs.dirname(fname))
    end,

    reuse_client = function(client, config)
      if client.name ~= config.name then return false end
      local cr = client.config and client.config.root_dir
      local nr = config.root_dir
      if cr == nr then return true end
      if cr and nr and under_cvyuh(cr) and under_cvyuh(nr) then return true end
      return false
    end,

    settings = {
      ['rust-analyzer'] = {
        linkedProjects = LINKED_PROJECTS,
      },
    },
  })

  -- Auto-attach OFF until :RAStart.
  vim.lsp.enable("rust_analyzer", false)

  vim.api.nvim_create_user_command("RAStart", function()
    vim.lsp.enable("rust_analyzer", true)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "rust" then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("doautocmd FileType")
        end)
      end
    end
    vim.notify("rust-analyzer: started", vim.log.levels.INFO)
  end, { desc = "Start rust-analyzer for Rust buffers" })

  vim.api.nvim_create_user_command("RAStop", function()
    vim.lsp.enable("rust_analyzer", false)
    local n = 0
    for _, c in ipairs(vim.lsp.get_clients({ name = "rust_analyzer" })) do
      c:stop(true)
      n = n + 1
    end
    vim.notify(("rust-analyzer: stopped (%d client(s))"):format(n), vim.log.levels.INFO)
  end, { desc = "Stop rust-analyzer and disable auto-attach" })

  -- TODO: DAP / formatters when needed — add here so all Rust tooling
  -- stays in this one file.
end

return M
