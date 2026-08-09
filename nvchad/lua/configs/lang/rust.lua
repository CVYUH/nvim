-- Rust language tooling — single source of truth.
--
-- LSP server config + on-demand commands consolidated here. DAP / formatters /
-- debugger setup land here too (one place for all Rust tooling).
--
-- Why one analyzer for everything: cvyuh-systems holds a dozen separate Cargo
-- roots (cvyuh-libs is a workspace; the services are single-crate). The
-- upstream rust_analyzer config detects per-crate workspace_root via
-- `cargo metadata`, which spawns a fresh rust-analyzer per detected root —
-- multiple instances at ~6–7 GB each. This setup:
--   * Pins root_dir to ~/code/cvyuh-systems for any buffer under that tree,
--     so every Rust buffer attaches to the SAME LSP client (one process).
--   * Sends every Cargo.toml under settings.linkedProjects so rust-analyzer
--     loads them as one combined view — cross-crate goto-def works, no
--     re-analysis when switching crates. The list is read from
--     nvim/rust-lsp/rust-analyzer.toml, which is its single source.
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

-- The crate list is deliberately NOT auto-discovery: the repo also contains
-- _inspirations/ (12 vendored third-party workspaces — kanidm, sqlx, redis-rs,
-- ldap3, …) which are read-only reference and must never be indexed. Letting
-- rust-analyzer scan from the repo root would spin every one of them up.
--
-- SINGLE SOURCE: nvim/rust-lsp/rust-analyzer.toml. That file has to exist
-- anyway — it is what bounds a client that sends no settings (Claude Code) when
-- it initialises the shared instance first — so it owns the list and this file
-- reads it rather than keeping a second copy. The two used to be hand-synced;
-- they drifted apart the moment anyone forgot.
--
-- Read from the canonical repo path, not the ~/.config symlink, so a missing
-- symlink is not silently a missing list.
local RA_TOML = CVYUH_ROOT .. '/nvim/rust-lsp/rust-analyzer.toml'

-- Minimal TOML slice: pull the quoted paths out of `linkedProjects = [ … ]`.
-- Not a general parser — it stops at the closing bracket, so the `[files]`
-- table below it (excludeDirs) is never picked up.
local function linked_projects()
  local ok, lines = pcall(vim.fn.readfile, RA_TOML)
  if not ok or type(lines) ~= 'table' then return nil end

  local out, inside = {}, false
  for _, line in ipairs(lines) do
    if not line:match('^%s*#') then
      if not inside and line:match('^%s*linkedProjects%s*=%s*%[') then inside = true end
      if inside then
        -- Entries are repo-relative so the TOML carries nobody's $HOME.
        -- rust-analyzer would resolve them against the workspace root itself,
        -- but we join here anyway: root_dir below already pins CVYUH_ROOT, and
        -- sending absolute paths keeps this independent of that resolution.
        for p in line:gmatch('"([^"]+)"') do
          out[#out + 1] = p:sub(1, 1) == '/' and p or (CVYUH_ROOT .. '/' .. p)
        end
        if line:find(']', 1, true) then break end
      end
    end
  end

  return #out > 0 and out or nil
end

local function under_cvyuh(path)
  if not path or path == '' then return false end
  local n = vim.fs.normalize(path)
  -- Resolve any symlinks so two physical paths to the same dir compare equal.
  local resolved = vim.uv.fs_realpath(n) or n
  return resolved:sub(1, #CVYUH_ROOT) == CVYUH_ROOT
end

function M.setup()
  local projects = linked_projects()
  if not projects then
    -- Loud, because the silent version of this failure is a ~30GB analyzer.
    vim.notify(
      ('rust-analyzer: could not read linkedProjects from %s\n'):format(RA_TOML)
        .. 'Falling back to rust-analyzer\'s own config lookup. If that is missing too it '
        .. 'will auto-discover from the repo root and index _inspirations/.',
      vim.log.levels.ERROR
    )
  end

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

    -- Omitted entirely when the list could not be read, so rust-analyzer falls
    -- back to its own user-level config rather than to an empty project view.
    settings = {
      ['rust-analyzer'] = projects and { linkedProjects = projects } or {},
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
