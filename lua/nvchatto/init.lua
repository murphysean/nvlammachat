-- Main plugin module
local config = require('nvchatto.config')
local conversation = require('nvchatto.conversation')
local ui = require('nvchatto.ui')
local tools = require('nvchatto.tools')
local http = require('nvchatto.http')

local M = {}

-- Setup function
function M.setup(opts)
  config.setup(opts)
end

-- Process streaming chunk
local function process_chunk(json_data)
  if json_data.error then
    ui.append_to_popup(conversation.state, "\n\n## ❌ Error\n" .. tostring(json_data.error) .. "\n")
    return
  end

  if not json_data.message then return end

  local msg = json_data.message

  -- Handle thinking state transitions
  if msg.thinking then
    if not conversation.state.thinking_mode then
      conversation.state.thinking_mode = true
      conversation.state.thinking_tokens = 0
      ui.append_to_popup(conversation.state, "\n## 🧠 Thinking\n")
    end
    conversation.state.thinking_tokens = conversation.state.thinking_tokens + 1
    ui.append_to_popup(conversation.state, msg.thinking)
  end

  -- Handle content (assistant response)
  if msg.content and msg.content ~= "" then
    if conversation.state.thinking_mode then
      conversation.state.thinking_mode = false
      ui.append_to_popup(conversation.state, "\n\n## 🤖 Assistant\n")
      conversation.state.assistant_started = true
      conversation.state.current_response_tokens = 0
    elseif not conversation.state.assistant_started then
      ui.append_to_popup(conversation.state, "## 🤖 Assistant\n")
      conversation.state.assistant_started = true
      conversation.state.current_response_tokens = 0
    end

    conversation.state.current_response_tokens = conversation.state.current_response_tokens + 1
    ui.append_to_popup(conversation.state, msg.content)

    -- Update or create current assistant message
    local last_msg = conversation.state.messages[#conversation.state.messages]
    if last_msg and last_msg.role == "assistant" then
      last_msg.content = last_msg.content .. msg.content
      last_msg.tokens = conversation.state.current_response_tokens
    else
      table.insert(conversation.state.messages, {
        role = "assistant",
        content = msg.content,
        tokens = conversation.state.current_response_tokens
      })
    end
  end

  -- Handle tool calls
  if msg.tool_calls then
    ui.append_to_popup(conversation.state, "\n\n## 🛠️ Tool Requests\n")
    for _, tool_call in ipairs(msg.tool_calls) do
      local func_data = tool_call["function"]
      if func_data then
        ui.append_to_popup(conversation.state, "- " .. func_data.name .. " (" .. vim.fn.json_encode(func_data.arguments) .. ")\n")
      end
    end

    -- Add tool calls to the current assistant message
    local last_msg = conversation.state.messages[#conversation.state.messages]
    if last_msg and last_msg.role == "assistant" then
      last_msg.tool_calls = msg.tool_calls
    else
      table.insert(conversation.state.messages, {
        role = "assistant",
        content = "",
        tool_calls = msg.tool_calls
      })
    end

    return msg.tool_calls
  end

  -- Handle completion
  if json_data.done then
    local duration_sec = math.floor((json_data.total_duration or 0) / 1000000000)
    local response_tokens = json_data.eval_count or 0

    ui.append_to_popup(conversation.state, string.format("\n\n## 📊 Performance\nCompleted in %ds | Sent: %d tokens | Received: %d tokens | Thinking: %d tokens",
      duration_sec, conversation.state.sent_tokens, response_tokens, conversation.state.thinking_tokens))

    -- Reset state for next interaction
    conversation.state.thinking_mode = false
    conversation.state.assistant_started = false

    return nil, true
  end
end

-- Continue conversation with LLM
function M.continue_conversation()
  if not conversation.state.active then return end

  -- Trim conversation if too long (keep system + last 6 messages)
  if #conversation.state.messages > 8 then
    local system_msg = conversation.state.messages[1]
    local recent_messages = {}
    for i = math.max(2, #conversation.state.messages - 5), #conversation.state.messages do
      table.insert(recent_messages, conversation.state.messages[i])
    end
    conversation.state.messages = {system_msg}
    for _, msg in ipairs(recent_messages) do
      table.insert(conversation.state.messages, msg)
    end
  end

  -- Calculate and display token counts by role
  local token_counts = {system = 0, user = 0, assistant = 0, tool = 0}
  local total_tokens = 0
  for _, msg in ipairs(conversation.state.messages) do
    local tokens = msg.tokens or 0
    token_counts[msg.role] = (token_counts[msg.role] or 0) + tokens
    total_tokens = total_tokens + tokens
  end

  conversation.state.sent_tokens = total_tokens

  local url = config.config.base_url .. "/api/chat"

  ui.append_to_popup(conversation.state, string.format("\n## 📤 Request\n🔗 %s | 🤖 %s\n📊 %d tokens (system: %d, user: %d, assistant: %d, tool: %d)\n",
    config.config.base_url, config.config.model,
    total_tokens, token_counts.system, token_counts.user, token_counts.assistant, token_counts.tool))

  local payload_data = {
    model = config.config.model,
    messages = conversation.state.messages,
    tools = tools.get_definitions(),
    stream = true,
    think = config.config.think
  }

  if config.config.num_ctx then
    payload_data.options = { num_ctx = config.config.num_ctx }
  end

  local payload = vim.fn.json_encode(payload_data)

  http.stream_request(url, payload, process_chunk,
    function(tool_calls)
      ui.append_to_popup(conversation.state, "\n✅ Request Completed\n")

      if tool_calls and #tool_calls > 0 then
        ui.append_to_popup(conversation.state, "\n## 🔧 Tool Requests Pending Approval\n")

        -- Use interactive tool approval
        ui.process_tool_calls(tool_calls, conversation.state.original_buf, function(results)
          for _, result in ipairs(results) do
            if result.approved then
              ui.append_to_popup(conversation.state, string.format("\n✓ %s: Approved\n", result.name))
              ui.append_to_popup(conversation.state, "Result: " .. result.content .. "\n")
            else
              ui.append_to_popup(conversation.state, string.format("\n✗ %s: %s\n", result.name, result.content))
            end

            table.insert(conversation.state.messages, {
              role = "tool",
              tool_call_id = result.tool_call_id,
              content = result.content,
              tokens = conversation.estimate_tokens(result.content)
            })
          end

          -- Continue conversation after all tools processed
          vim.defer_fn(M.continue_conversation, 100)
        end)
      end
    end
  )
end

-- Submit input from input buffer
function M.submit_input()
  if not conversation.state.input_buf or not vim.api.nvim_buf_is_valid(conversation.state.input_buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(conversation.state.input_buf, 0, -1, false)
  local user_input = table.concat(lines, "\n")

  if user_input == "" then return end

  -- Clear input buffer
  vim.api.nvim_buf_set_lines(conversation.state.input_buf, 0, -1, false, {})

  -- Add user message to conversation
  if not conversation.state.active then
    M.initialize_conversation(user_input)
  else
    ui.append_to_popup(conversation.state, "\n\n## 🧑 User\n" .. user_input .. "\n\n")
    table.insert(conversation.state.messages, {
      role = "user",
      content = user_input,
      tokens = conversation.estimate_tokens(user_input)
    })
  end

  M.continue_conversation()
end

-- Initialize conversation with system prompt
function M.initialize_conversation(user_input)
  -- Don't overwrite original_buf if already set (it's captured when window opens)
  if not conversation.state.original_buf or not vim.api.nvim_buf_is_valid(conversation.state.original_buf) then
    conversation.state.original_buf = vim.api.nvim_get_current_buf()
  end

  local context = M.get_buffer_context()
  conversation.state.active = true

  local context_info = string.format([[You are an AI coding assistant integrated into Neovim. Your role is to help developers by analyzing code, fixing issues, and enhancing their IDE experience using available tools.

CURRENT CONTEXT:
- File: %s
- Current line: %d (column %d)
- Buffer size: %d lines
- Working directory: %s

WORKFLOW - Follow these steps for each request:
1. ANALYZE: Use get_structure and get_diagnostics to understand the current state
2. READ: Use get_lines to examine relevant code sections
3. PLAN: Think through the solution approach
4. ACT: Use replace_lines or insert_lines to make changes
5. VERIFY: Check your changes make sense in context

TOOL USAGE GUIDELINES:
- Always provide a clear "reason" parameter explaining why you need each tool
- Use get_diagnostics first for error-related requests
- Use get_structure to understand code organization
- Read code before making changes with get_lines
- Make targeted changes with replace_lines or insert_lines
- Be conservative - make minimal necessary changes

RESPONSE STYLE:
- Be concise and direct
- Explain what you're doing and why
- Show code changes clearly
- Focus on practical solutions

Use tools systematically to provide the best assistance.]], context.buffer_name, context.current_line, context.cursor_col, context.total_lines, context.working_directory)

  conversation.state.messages = {
    {
      role = "system",
      content = context_info,
      tokens = conversation.estimate_tokens(context_info)
    }
  }

  ui.append_to_popup(conversation.state, "## 🧑 User\n" .. user_input .. "\n\n")

  table.insert(conversation.state.messages, {
    role = "user",
    content = user_input,
    tokens = conversation.estimate_tokens(user_input)
  })
end

-- Get buffer context from the original buffer (not nvchatto buffers)
function M.get_buffer_context()
  local buf = conversation.state.original_buf

  -- Fallback to current buffer if no original buffer
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_get_current_buf()
  end

  local buf_name = vim.api.nvim_buf_get_name(buf)
  local cwd = vim.fn.getcwd()

  -- Try to find a window for this buffer to get cursor position
  local cursor_line = 1
  local cursor_col = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      local pos = vim.api.nvim_win_get_cursor(win)
      cursor_line = pos[1]
      cursor_col = pos[2]
      break
    end
  end

  return {
    current_line = cursor_line,
    cursor_col = cursor_col,
    buffer_name = buf_name,
    working_directory = cwd,
    total_lines = vim.api.nvim_buf_line_count(buf)
  }
end

-- Toggle window - main entry point
function M.toggle()
  ui.toggle_window()
end

-- Continue existing conversation (for backward compatibility)
function M.continue_chat()
  if not conversation.state.active then
    vim.notify("No active conversation. Start with :NVChatto", vim.log.levels.WARN)
    return
  end

  -- Ensure window is visible
  if not conversation.state.visible then
    ui.toggle_window()
  end

  -- Focus input window
  if conversation.state.input_win and vim.api.nvim_win_is_valid(conversation.state.input_win) then
    vim.api.nvim_set_current_win(conversation.state.input_win)
  end
end

-- Commands
vim.api.nvim_create_user_command('NVChatto', M.toggle, { desc = 'Toggle NVChatto window' })

-- Keymaps
vim.keymap.set('n', '<leader>oc', M.toggle, { desc = 'Toggle NVChatto window' })

-- Autocmd to handle window close
vim.api.nvim_create_autocmd("WinClosed", {
  callback = function(args)
    local closed_win = tonumber(args.match)

    -- If one of our windows is closed externally, close the other too
    if closed_win == conversation.state.win then
      if conversation.state.input_win and vim.api.nvim_win_is_valid(conversation.state.input_win) then
        vim.api.nvim_win_close(conversation.state.input_win, true)
      end
      conversation.state.win = nil
      conversation.state.input_win = nil
      conversation.state.visible = false
    elseif closed_win == conversation.state.input_win then
      if conversation.state.win and vim.api.nvim_win_is_valid(conversation.state.win) then
        vim.api.nvim_win_close(conversation.state.win, true)
      end
      conversation.state.win = nil
      conversation.state.input_win = nil
      conversation.state.visible = false
    end
  end
})

return M