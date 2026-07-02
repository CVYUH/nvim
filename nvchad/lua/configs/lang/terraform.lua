-- Terraform / OpenTofu language tooling — single source of truth.
--
-- Covers both `.tf` (terraform) and `.tofu` (OpenTofu) files. The LSP
-- server (terraformls, the HashiCorp official one) speaks HCL and works
-- for both — only the filetype detection differs.
--
-- Why .tofu wasn't getting analyzer / coloring: nvim's default
-- ftdetect doesn't map `.tofu` to anything, so the buffer ended up with
-- empty filetype, treesitter didn't fire, and terraformls's filetype
-- filter (`terraform`) skipped attach. The vim.filetype.add() below
-- maps `.tofu` → terraform so colors + LSP both apply.
--
-- Auto-start is OFF by default. :TFStart turns it on for current + future
-- terraform/tofu buffers, :TFStop kills the process and disables auto-attach.

local M = {}

-- Filetype detection: .tofu → terraform. (.tf already maps to terraform by
-- nvim default.) MUST register at STARTUP, before any file is opened. If it
-- only ran inside setup() (which fires on the lazy lspconfig load), a .tofu
-- opened as the FIRST file of a session would miss the mapping — empty
-- filetype, so treesitter doesn't color it and terraformls won't attach.
-- Called from autocmds.lua at startup; setup() also calls it (idempotent) so
-- this file stays the single source of truth for tofu detection.
function M.register_ft()
  vim.filetype.add({
    extension = {
      tofu = "terraform",
    },
  })
end

function M.setup()
  M.register_ft()

  -- No per-project overrides today — terraformls defaults are fine.

  -- Auto-attach OFF until :TFStart.
  vim.lsp.enable("terraformls", false)

  vim.api.nvim_create_user_command("TFStart", function()
    vim.lsp.enable("terraformls", true)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "terraform" then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("doautocmd FileType")
        end)
      end
    end
    vim.notify("terraformls: started", vim.log.levels.INFO)
  end, { desc = "Start terraformls for terraform/tofu buffers" })

  vim.api.nvim_create_user_command("TFStop", function()
    vim.lsp.enable("terraformls", false)
    local n = 0
    for _, c in ipairs(vim.lsp.get_clients({ name = "terraformls" })) do
      c:stop(true)
      n = n + 1
    end
    vim.notify(("terraformls: stopped (%d client(s))"):format(n), vim.log.levels.INFO)
  end, { desc = "Stop terraformls and disable auto-attach" })

  -- TODO: tflint integration, formatters (terraform fmt / tofu fmt) when
  -- needed — keep all terraform/tofu tooling in this file.
end

return M
