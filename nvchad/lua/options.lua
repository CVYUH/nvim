require "nvchad.options"

-- add yours here!

-- local o = vim.o
-- o.cursorlineopt ='both' -- to enable cursorline!

-- Over SSH or mosh, nvim's own clipboard pick is wrong: none outside tmux, tmux's shared
-- buffer inside it, or the remote Mac's pbcopy. Copy via OSC52 to the local
-- terminal's clipboard instead; paste from nvim's register so `p` never picks
-- up a foreign tmux buffer. tmux needs `set-clipboard on` to pass OSC52 through.
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
  local osc52 = require "vim.ui.clipboard.osc52"
  local function paste()
    return { vim.fn.split(vim.fn.getreg "", "\n"), vim.fn.getregtype "" }
  end
  vim.g.clipboard = {
    name = "OSC52",
    copy = { ["+"] = osc52.copy "+", ["*"] = osc52.copy "*" },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end
