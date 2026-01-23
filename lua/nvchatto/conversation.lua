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
  M.state.thinking_mode = false
  M.state.assistant_started = false
  M.state.thinking_tokens = 0
  M.state.current_response_tokens = 0
  M.state.sent_tokens = 0
end

return M
