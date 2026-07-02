-- Compatibility shims for nvim-treesitter (master branch) on Neovim 0.11+/0.12.
--
-- == #downcase! directive ==
-- nvim-treesitter master registers a `#downcase!` query directive
-- (lua/nvim-treesitter/query_predicates.lua) that reads the captured node as
--   local node = match[id]
-- But Neovim 0.11+ changed the directive API: `match[id]` is now a LIST of
-- TSNodes, not a single node (see the builtin #gsub!/#trim! handlers in
-- runtime/lua/vim/treesitter/query.lua, which do `local nodes = match[id]; local
-- node = nodes[1]`). So master's handler treats a table as a node, the lowered
-- text is wrong, and the injection's language/content node resolves to nil. The
-- highlighter then crashes with:
--   ...runtime/lua/vim/treesitter.lua: attempt to call method 'range' (a nil value)
-- on any file whose injection query uses #downcase! — hcl/terraform heredocs
-- (`content = <<EOF`), bash, ruby, php.
--
-- Fix: re-register #downcase! with the 0.12-correct list semantics, mirroring the
-- builtin #gsub! handler. Must run AFTER nvim-treesitter loads (it registers its
-- own broken copy on load), so we hook lazy's `User LazyLoad` event and force-
-- override. Remove this once nvim-treesitter `main` (the 0.11+ rewrite) is adopted.

local M = {}

local function register_downcase()
  vim.treesitter.query.add_directive("downcase!", function(match, _, bufnr, pred, metadata)
    local id = pred[2]
    local nodes = match[id]
    if not nodes or #nodes == 0 then
      return
    end
    local node = nodes[1]
    local text = vim.treesitter.get_node_text(node, bufnr, { metadata = metadata[id] }) or ""
    metadata[id] = metadata[id] or {}
    metadata[id].text = string.lower(text)
  end, { force = true })
end

function M.setup()
  -- If treesitter is already loaded (e.g. config reload), patch immediately.
  if package.loaded["nvim-treesitter"] then
    register_downcase()
    return
  end
  -- Otherwise patch right after lazy.nvim finishes loading the plugin.
  vim.api.nvim_create_autocmd("User", {
    pattern = "LazyLoad",
    callback = function(ev)
      if ev.data == "nvim-treesitter" then
        register_downcase()
        return true -- one-shot: delete this autocmd after firing
      end
    end,
  })
end

return M
