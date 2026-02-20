-- Conversation state management
local M = {}

-- Estimate tokens for text (rough approximation: 1 token ≈ 4 characters)
function M.estimate_tokens(text)
  return math.ceil(string.len(text) / 4)
end

-- Conversation state
M.state = {
  messages = {},
  active = false,
  buf = nil,
  win = nil,
  input_buf = nil,
  input_win = nil,
  visible = false,
  original_buf = nil,
  thinking_mode = false,
  assistant_started = false,
  thinking_tokens = 0,
  current_response_tokens = 0,
  sent_tokens = 0
}

function M.reset()
  M.state.messages = {}
  M.state.active = false
  M.state.visible = false
  M.state.thinking_mode = false
  M.state.assistant_started = false
  M.state.thinking_tokens = 0
  M.state.current_response_tokens = 0
  M.state.sent_tokens = 0
  M.close_windows()
end

-- Close split windows
function M.close_windows()
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    vim.api.nvim_win_close(M.state.win, true)
  end
  if M.state.input_win and vim.api.nvim_win_is_valid(M.state.input_win) then
    vim.api.nvim_win_close(M.state.input_win, true)
  end
  if M.state.buf and vim.api.nvim_buf_is_valid(M.state.buf) then
    vim.api.nvim_buf_delete(M.state.buf, { force = true })
  end
  if M.state.input_buf and vim.api.nvim_buf_is_valid(M.state.input_buf) then
    vim.api.nvim_buf_delete(M.state.input_buf, { force = true })
  end
  M.state.win = nil
  M.state.input_win = nil
  M.state.buf = nil
  M.state.input_buf = nil
  M.state.visible = false
end

return M
