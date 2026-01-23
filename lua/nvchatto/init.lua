-- Main plugin module
local config = require('ollama-nvim.config')
local conversation = require('ollama-nvim.conversation')
local ui = require('ollama-nvim.ui')
local tools = require('ollama-nvim.tools')
local http = require('ollama-nvim.http')

local M = {}

-- Setup function
function M.setup(opts)
  config.setup(opts)
end

-- Process streaming chunk
local function process_chunk(json_data)
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
  
  ui.append_to_popup(conversation.state, string.format("📤 Sending: %d tokens (system: %d, user: %d, assistant: %d, tool: %d)\n\n", 
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
  local url = string.format("http://%s:%d/api/chat", config.config.host, config.config.port)
  
  ui.append_to_popup(conversation.state, "🔄 Sending request to Ollama...\n")
  
  http.stream_request(url, payload, process_chunk,
    function(tool_calls)
      ui.append_to_popup(conversation.state, "\n✅ Request completed\n")
      
      if tool_calls and #tool_calls > 0 then
        for _, tool_call in ipairs(tool_calls) do
          local func_data = tool_call["function"]
          if func_data then
            local reason = func_data.arguments.reason or "No reason provided"
            local confirm = vim.fn.confirm("Execute " .. func_data.name .. "?\nReason: " .. reason, "&Yes\n&No", 1)
            if confirm == 1 then
              ui.append_to_popup(conversation.state, "\n\n## 🔧 Tool Execution\n")
              ui.append_to_popup(conversation.state, "Executing " .. func_data.name .. "...\n")
              local result = tools.execute(func_data.name, func_data.arguments, conversation.state.original_buf)
              ui.append_to_popup(conversation.state, "Result: " .. result .. "\n")
              
              table.insert(conversation.state.messages, {
                role = "tool",
                tool_call_id = tool_call.id,
                content = result,
                tokens = conversation.estimate_tokens(result)
              })
              
              vim.defer_fn(M.continue_conversation, 500)
            else
              ui.append_to_popup(conversation.state, "\n\n## 🔧 Tool Execution\nTool execution declined\n")
              table.insert(conversation.state.messages, {
                role = "tool", 
                tool_call_id = tool_call.id,
                content = "Tool execution declined by user",
                tokens = conversation.estimate_tokens("Tool execution declined by user")
              })
            end
          end
        end
      end
    end
  )
end

-- Continue existing conversation
function M.continue_chat()
  if not conversation.state.active then
    vim.notify("No active conversation. Start with :OllamaChat", vim.log.levels.WARN)
    return
  end
  
  local user_input = vim.fn.input("Continue chat: ")
  if user_input == "" then return end
  
  table.insert(conversation.state.messages, {
    role = "user", 
    content = user_input,
    tokens = conversation.estimate_tokens(user_input)
  })
  M.continue_conversation()
end

-- Get buffer context
local function get_buffer_context()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local buf_name = vim.api.nvim_buf_get_name(0)
  local cwd = vim.fn.getcwd()
  
  return {
    current_line = cursor_pos[1],
    cursor_col = cursor_pos[2],
    buffer_name = buf_name,
    working_directory = cwd,
    total_lines = vim.api.nvim_buf_line_count(0)
  }
end

-- Chat with buffer context
function M.chat_with_context()
  local user_input = vim.fn.input("Chat: ")
  if user_input == "" then return end
  
  -- Check if window is still valid, reset if not
  if conversation.state.active and conversation.state.win and not vim.api.nvim_win_is_valid(conversation.state.win) then
    conversation.state.active = false
    conversation.state.buf = nil
    conversation.state.win = nil
  end
  
  -- Initialize conversation if not active
  if not conversation.state.active then
    local context = get_buffer_context()
    conversation.state.original_buf = vim.api.nvim_get_current_buf()
    conversation.state.buf, conversation.state.win = ui.create_popup()
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
  else
    ui.append_to_popup(conversation.state, "\n\n## 🧑 User\n" .. user_input .. "\n\n")
  end
  
  table.insert(conversation.state.messages, {
    role = "user", 
    content = user_input,
    tokens = conversation.estimate_tokens(user_input)
  })
  M.continue_conversation()
end

-- Commands
vim.api.nvim_create_user_command('OllamaChat', M.chat_with_context, {})
vim.api.nvim_create_user_command('OllamaContinue', M.continue_chat, {})

-- Keymaps
vim.keymap.set('n', '<leader>oc', M.chat_with_context, { desc = 'Ollama Chat' })

-- Autocmd to clean up on window close
vim.api.nvim_create_autocmd("WinClosed", {
  callback = function()
    if conversation.state.win and not vim.api.nvim_win_is_valid(conversation.state.win) then
      conversation.reset()
    end
  end
})

return M
