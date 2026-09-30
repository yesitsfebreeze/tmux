-- tmux owns the cursor when its client renderer is enabled. Keep the existing
-- editor animation on stock tmux and outside tmux.
return {
  {
    "sphamba/smear-cursor.nvim",
    event = "VeryLazy",
    cond = function()
      if not vim.env.TMUX then return true end
      local result = vim.fn.system({ "tmux", "show-options", "-Av", "cursor-smear" })
      local owns_cursor = vim.v.shell_error == 0 and vim.trim(result) == "on"
      if owns_cursor then require("config.smear-tmux").setup() end
      return not owns_cursor
    end,
    opts = { legacy_computing_symbols_support = true },
  },
}
