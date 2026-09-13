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
--
-- == #set-lang-from-info-string! directive ==
-- The same bug, in the same file, in the directive markdown uses to resolve a
-- fenced block's language from its info string (```rust -> the rust parser).
-- It crashes identically, and it fires on any .md holding a fenced code block,
-- so markdown is unreadable without this. Fixed the same way, and the alias
-- table below is upstream's — reproduced because theirs is a file-local.

local M = {}

-- Aliases vim.filetype.match cannot resolve from a bare `a.<alias>` filename.
local INFO_STRING_ALIASES = {
  ex = "elixir",
  pl = "perl",
  sh = "bash",
  uxn = "uxntal",
  ts = "typescript",
}

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

local function register_info_string()
  vim.treesitter.query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
    local nodes = match[pred[2]]
    if not nodes or #nodes == 0 then
      return
    end
    local alias = vim.treesitter.get_node_text(nodes[1], bufnr):lower()
    -- `a.<alias>` is upstream's trick for reusing nvim's filetype table as a
    -- language lookup: ```python -> a.python -> python.
    local ft = vim.filetype.match({ filename = "a." .. alias })
    metadata["injection.language"] = ft or INFO_STRING_ALIASES[alias] or alias
  end, { force = true })
end

local function register_all()
  -- Load upstream's copy FIRST. query_predicates is not required by
  -- nvim-treesitter's own setup — the query engine pulls it in the first time a
  -- query actually runs, which is after LazyLoad has fired. Patch before that
  -- and upstream re-registers its broken handlers over ours and the crash comes
  -- back. Requiring it here makes the ordering ours to decide.
  pcall(require, "nvim-treesitter.query_predicates")
  register_downcase()
  register_info_string()
end

function M.setup()
  -- If treesitter is already loaded (e.g. config reload), patch immediately.
  if package.loaded["nvim-treesitter"] then
    register_all()
    return
  end
  -- Otherwise patch right after lazy.nvim finishes loading the plugin.
  vim.api.nvim_create_autocmd("User", {
    pattern = "LazyLoad",
    callback = function(ev)
      if ev.data == "nvim-treesitter" then
        register_all()
        return true -- one-shot: delete this autocmd after firing
      end
    end,
  })
end

return M
