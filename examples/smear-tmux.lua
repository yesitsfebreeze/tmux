-- Editor metadata for the shared tmux renderer. Drawing remains entirely in tmux.
local M = {}
local started = false

function M.setup()
  if started or not vim.api.nvim_ui_send then return end
  started = true
  local previous, pending
  local group = vim.api.nvim_create_augroup("TmuxSmearMetadata", { clear = true })

  local function send(value)
    vim.api.nvim_ui_send("\27]777;smear-v1;" .. value .. "\27\\")
  end

  local function report()
    pending = false
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_get_current_buf()
    local top, line = vim.fn.line("w0"), vim.fn.line(".")
    local height = vim.api.nvim_win_get_height(win)
    local origin = vim.api.nvim_win_get_position(win)[1]
    local scroll = 0
    if previous and previous.win == win and previous.buf == buf
      and previous.top ~= top and previous.line ~= line then
      -- Same screen-distance rule as smear_cursor.screen (including folds).
      local first, last = math.min(previous.top, top), math.max(previous.top, top)
      local all = height
      if last - first < height then
        local ok, result = pcall(vim.api.nvim_win_text_height, win, {
          start_row = first - 1, end_row = last - 1,
        })
        all = ok and result.all or 1
      end
      scroll = (all - 1) * (previous.top > top and -1 or 1)
    end
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    local cursor = vim.api.nvim_get_hl(0, { name = "Cursor", link = false })
    local mode = vim.api.nvim_get_mode().mode
    if mode ~= "i" and mode ~= "R" and mode ~= "c" and mode ~= "t" then mode = "n" end
    send(table.concat({ mode, cursor.bg or normal.fg or 0xd0d0d0, normal.bg or -1,
      win, buf, top, line, scroll, origin, height }, ";"))
    previous = { win = win, buf = buf, top = top, line = line }
  end

  local function schedule()
    if pending then return end
    pending = true
    vim.schedule(report)
  end
  vim.api.nvim_create_autocmd({ "VimEnter", "VimResume", "FocusGained", "BufEnter",
    "WinEnter", "WinScrolled", "CursorMoved", "CursorMovedI", "ModeChanged",
    "CmdlineChanged", "ColorScheme", "VimResized" }, { group = group, callback = schedule })
  vim.api.nvim_create_autocmd({ "VimLeavePre", "VimSuspend" }, {
    group = group, callback = function() send("off") end,
  })
  schedule()
end

return M
