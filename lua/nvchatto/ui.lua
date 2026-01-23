-- UI and popup management
local M = {}

-- Append content to popup buffer (without adding newlines)
function M.append_to_popup(conversation, content)
  if not conversation.buf or not vim.api.nvim_buf_is_valid(conversation.buf) then
    return
  end
  
  local current_lines = vim.api.nvim_buf_line_count(conversation.buf)
  local last_line = vim.api.nvim_buf_get_lines(conversation.buf, current_lines - 1, current_lines, false)[1] or ""
  
  local lines = vim.split(content, "\n", {plain = true})
  lines[1] = last_line .. lines[1]
  
  vim.api.nvim_buf_set_lines(conversation.buf, current_lines - 1, current_lines, false, lines)
  
  -- Auto-scroll to bottom
  if conversation.win and vim.api.nvim_win_is_valid(conversation.win) then
    vim.api.nvim_win_set_cursor(conversation.win, {vim.api.nvim_buf_line_count(conversation.buf), 0})
  end
end

-- Create popup window
function M.create_popup()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Ollama Chat ',
    title_pos = 'center'
  }
  
  local win = vim.api.nvim_open_win(buf, true, opts)
  vim.api.nvim_win_set_option(win, 'wrap', true)
  vim.api.nvim_win_set_option(win, 'linebreak', true)
  
  return buf, win
end

return M
