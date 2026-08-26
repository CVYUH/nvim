-- C language tooling — single source of truth.
--
-- LSP server config + on-demand commands consolidated here. DAP / formatters
-- land here too (one place for all C tooling).
--
-- Auto-start is OFF by default. :CStart turns it on for current + future
-- C buffers, :CStop kills the process and disables auto-attach.
--
-- WHY CLANGD NEEDS MORE SETUP THAN gopls/rust-analyzer:
-- gopls finds a project from go.mod, rust-analyzer from Cargo.toml. clangd has
-- no equivalent — it needs a compile_commands.json naming the exact compiler
-- invocation for every .c file. Without one it falls back to guessing flags,
-- and on a tree like postgres/ that means EVERY #include "postgres.h" comes
-- back unresolved: no goto-definition, no hover, red diagnostics everywhere.
-- That is a missing compile_commands.json, not a broken editor.
--
-- For postgres/ specifically, many headers (pg_config.h, fmgroids.h, the
-- generated parser) do not exist on disk at all until the tree is configured
-- and partially built. Generating that file is a separate step:
--
--   cd ~/code/cvyuh-systems/postgres
--   meson setup build     # writes build/compile_commands.json
--   ninja -C build        # materialises the generated headers
--   ln -s build/compile_commands.json .   # so clangd finds it from the root
--
-- The symlink matters: clangd searches a file's own directory and its
-- ancestors, so a compile_commands.json parked only in build/ is not reliably
-- picked up for sources under src/.

local M = {}

function M.setup()
  vim.lsp.config("clangd", {
    cmd = {
      "clangd",
      -- Index the whole project in the background so goto-definition works
      -- across translation units instead of only within the open file.
      "--background-index",
      -- Never auto-insert #include lines. postgres has strict, hand-curated
      -- include order (postgres.h always first); clangd's guesses fight it.
      "--header-insertion=never",
      -- Show full signatures in completion rather than bare identifiers —
      -- worth the noise when reading an unfamiliar C codebase.
      "--completion-style=detailed",
    },

    -- clang-tidy is deliberately NOT enabled. It layers opinionated lint on
    -- top of real diagnostics, and on third-party C the two are hard to tell
    -- apart. Add "--clang-tidy" above once the tree is indexing cleanly.
  })

  -- Auto-attach OFF until :CStart.
  vim.lsp.enable("clangd", false)

  vim.api.nvim_create_user_command("CStart", function()
    -- Refuse loudly rather than reporting success we cannot verify.
    -- vim.lsp.enable() only flips auto-attach; with no binary on PATH the
    -- client spawn fails out of band, so a bare "clangd: started" notify is
    -- indistinguishable from a working server that simply cannot answer.
    -- Mason installs into a bin dir it puts on nvim's PATH, so this check
    -- sees Mason-installed and system clangd alike.
    if vim.fn.executable("clangd") ~= 1 then
      vim.notify(
        "clangd: not found on PATH — nothing was started.\n"
          .. "Install it with :MasonToolsInstall (it is in ensure_installed),\n"
          .. "or :MasonInstall clangd, or system-wide via apt install clangd.",
        vim.log.levels.ERROR
      )
      return
    end

    vim.lsp.enable("clangd", true)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "c" then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("doautocmd FileType")
        end)
      end
    end
    vim.notify("clangd: started", vim.log.levels.INFO)
  end, { desc = "Start clangd for C buffers" })

  vim.api.nvim_create_user_command("CStop", function()
    vim.lsp.enable("clangd", false)
    local n = 0
    for _, c in ipairs(vim.lsp.get_clients({ name = "clangd" })) do
      c:stop(true)
      n = n + 1
    end
    vim.notify(("clangd: stopped (%d client(s))"):format(n), vim.log.levels.INFO)
  end, { desc = "Stop clangd and disable auto-attach" })

  -- Formatting is intentionally absent — see lua/configs/conform.lua. postgres
  -- formats with its own pgindent (BSD indent + typedefs.list), not
  -- clang-format; wiring clang-format here would silently reformat the tree
  -- into diffs upstream would reject.

  -- TODO: DAP (gdb via nvim-dap) when needed — keep all C tooling in this file.
end

return M
