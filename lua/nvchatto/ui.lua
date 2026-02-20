-- UI and popup management
local M = {}

-- Append content to popup buffer (without adding newlines)
function M.append_to_popup(conversation, content)
  if not conversation.buf or not vim.api.nvim_buf_is_valid(conversation.buf) then
    return
  end

  -- Make buffer temporarily modifiable
  local was_modifiable = vim.api.nvim_buf_get_option(conversation.buf, 'modifiable')
  if not was_modifiable then
    vim.api.nvim_buf_set_option(conversation.buf, 'modifiable', true)
  end

  local current_lines = vim.api.nvim_buf_line_count(conversation.buf)
  local last_line = vim.api.nvim_buf_get_lines(conversation.buf, current_lines - 1, current_lines, false)[1] or ""

  local lines = vim.split(content, "\n", {plain = true})
  lines[1] = last_line .. lines[1]

  vim.api.nvim_buf_set_lines(conversation.buf, current_lines - 1, current_lines, false, lines)

  -- Restore modifiable state
  if not was_modifiable then
    vim.api.nvim_buf_set_option(conversation.buf, 'modifiable', false)
  end

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

-- Create split layout with output (top) and input (bottom) windows
function M.create_split_ui()
  local conversation = require('nvchatto.conversation')

  -- Save the original buffer BEFORE switching focus to nvchatto windows
  -- Only capture if it's not a nvchatto buffer
  local current_buf = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(current_buf)
  if not buf_name:match("nvchatto") then
    conversation.state.original_buf = current_buf
  end

  -- Calculate dimensions
  -- Leave space at bottom for command line, status line, and padding
  -- cmdheight (usually 1) + statusline (usually 1) + extra padding (2)
  local bottom_margin = 4
  local width = math.floor(vim.o.columns * 0.35)
  local total_height = vim.o.lines - bottom_margin
  local output_height = math.floor(total_height * 0.75)
  local input_height = total_height - output_height - 1  -- -1 for separator

  -- Create output buffer (read-only)
  if not conversation.state.buf or not vim.api.nvim_buf_is_valid(conversation.state.buf) then
    conversation.state.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(conversation.state.buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(conversation.state.buf, 'filetype', 'markdown')
    vim.api.nvim_buf_set_name(conversation.state.buf, 'nvchatto-output')
  end

  -- Create input buffer
  if not conversation.state.input_buf or not vim.api.nvim_buf_is_valid(conversation.state.input_buf) then
    conversation.state.input_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(conversation.state.input_buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(conversation.state.input_buf, 'filetype', 'markdown')
    vim.api.nvim_buf_set_name(conversation.state.input_buf, 'nvchatto-input')
  end

  -- Create output window (top, right side)
  local output_win_opts = {
    relative = 'editor',
    width = width,
    height = output_height,
    row = 0,
    col = vim.o.columns - width,
    style = 'minimal',
    border = {'┌', '─', '┐', '│', '┤', '─', '├', '└'},
    title = ' NVChatto Output ',
    title_pos = 'center'
  }

  conversation.state.win = vim.api.nvim_open_win(conversation.state.buf, false, output_win_opts)
  vim.api.nvim_win_set_option(conversation.state.win, 'wrap', true)
  vim.api.nvim_win_set_option(conversation.state.win, 'linebreak', true)
  vim.api.nvim_win_set_option(conversation.state.win, 'number', false)
  vim.api.nvim_win_set_option(conversation.state.win, 'relativenumber', false)
  vim.api.nvim_win_set_option(conversation.state.win, 'cursorline', false)

  -- Make output buffer read-only
  vim.api.nvim_buf_set_option(conversation.state.buf, 'modifiable', false)

  -- Create input window (bottom, right side)
  local input_win_opts = {
    relative = 'editor',
    width = width,
    height = input_height,
    row = output_height + 1,  -- Below output window
    col = vim.o.columns - width,
    style = 'minimal',
    border = {'├', '─', '┤', '│', '┘', '─', '└', '│'},
    title = ' Input (Enter=send, Esc=close) ',
    title_pos = 'center'
  }

  conversation.state.input_win = vim.api.nvim_open_win(conversation.state.input_buf, true, input_win_opts)
  vim.api.nvim_win_set_option(conversation.state.input_win, 'wrap', true)
  vim.api.nvim_win_set_option(conversation.state.input_win, 'linebreak', true)
  vim.api.nvim_win_set_option(conversation.state.input_win, 'number', false)
  vim.api.nvim_win_set_option(conversation.state.input_win, 'relativenumber', false)

  -- Set up keymaps for input buffer
  M.setup_input_keymaps(conversation.state.input_buf)

  conversation.state.visible = true

  return conversation.state.buf, conversation.state.win, conversation.state.input_buf, conversation.state.input_win
end

-- Set up keymaps for input buffer
function M.setup_input_keymaps(buf)
  local nvchatto = require('nvchatto')

  -- Enter to submit (normal mode)
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
    callback = function()
      nvchatto.submit_input()
    end,
    desc = 'Submit input to LLM'
  })

  -- Enter to submit (insert mode) - exit insert mode first
  vim.api.nvim_buf_set_keymap(buf, 'i', '<CR>', '', {
    callback = function()
      vim.cmd('stopinsert')
      vim.schedule(function()
        nvchatto.submit_input()
      end)
    end,
    desc = 'Submit input to LLM'
  })

  -- Shift-Enter for newline (in insert mode)
  vim.api.nvim_buf_set_keymap(buf, 'i', '<S-CR>', '<Esc>A<CR>a', {
    desc = 'Insert newline'
  })

  -- Escape to close window (normal mode)
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', {
    callback = function()
      M.toggle_window()
    end,
    desc = 'Close NVChatto window'
  })

  -- Escape to close window (insert mode) - exit insert first then close
  vim.api.nvim_buf_set_keymap(buf, 'i', '<Esc>', '', {
    callback = function()
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
      vim.schedule(function()
        M.toggle_window()
      end)
    end,
    desc = 'Close NVChatto window'
  })
end

-- Toggle window visibility
function M.toggle_window()
  local conversation = require('nvchatto.conversation')

  if conversation.state.visible then
    -- Mark as not visible first to prevent WinClosed autocmd from interfering
    conversation.state.visible = false

    -- Close windows
    if conversation.state.win and vim.api.nvim_win_is_valid(conversation.state.win) then
      vim.api.nvim_win_close(conversation.state.win, true)
    end
    if conversation.state.input_win and vim.api.nvim_win_is_valid(conversation.state.input_win) then
      vim.api.nvim_win_close(conversation.state.input_win, true)
    end
    conversation.state.win = nil
    conversation.state.input_win = nil
  else
    -- Create or restore windows
    M.create_split_ui()
  end
end

-- Tool approval dialog state
M.tool_dialog = {
  buf = nil,
  win = nil,
  pending_tools = {},
  current_index = 1,
  results = {},
  original_win = nil,
}

-- Preview tool action (open file, go to line)
local function preview_tool(tool_name, args, original_buf)
  -- Get target buffer
  local target_buf = original_buf
  if args.file then
    local cwd = vim.fn.getcwd()
    local full_path = vim.fn.fnamemodify(cwd .. "/" .. args.file, ":p")
    target_buf = vim.fn.bufnr(full_path, true)
    if vim.fn.filereadable(full_path) == 1 then
      vim.fn.bufload(target_buf)
    end
  end

  -- Open in current window or split
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    -- Find or create a window for this buffer
    local existing_win = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == target_buf then
        existing_win = win
        break
      end
    end

    local preview_win
    if existing_win then
      preview_win = existing_win
      vim.api.nvim_set_current_win(existing_win)
    else
      -- Open in a vertical split on the left side
      vim.cmd('vsplit')
      vim.api.nvim_win_set_buf(0, target_buf)
      preview_win = vim.api.nvim_get_current_win()
    end

    -- Store the preview window for clearing highlights later
    M.tool_dialog.preview_win = preview_win

    -- Go to line if specified
    if args.start_line or args.line_num then
      local line = args.start_line or args.line_num or 1
      vim.api.nvim_win_set_cursor(preview_win, {line, 0})
      -- Center the line
      vim.api.nvim_win_call(preview_win, function()
        vim.cmd('normal! zz')
      end)
    end

    -- Highlight the range if it's a replace operation
    if args.start_line and args.end_line then
      -- Clear any existing highlights in this window (safely)
      pcall(vim.api.nvim_win_call, preview_win, function()
        vim.fn.clearmatches()
      end)
      -- Add visual highlight for the entire range (all lines from start to end)
      -- \%>al matches after line a (so lines > a), \%<bl matches before line b (so lines < b)
      -- Combine without OR to get AND: lines that are both >(start-1) AND <(end+1)
      pcall(vim.api.nvim_win_call, preview_win, function()
        local start_line = args.start_line
        local end_line = args.end_line
        -- Match lines from start_line to end_line inclusive
        -- \%>(start-1)l\%<(end+1)l matches lines where line > (start-1) AND line < (end+1)
        local pattern = string.format('\\%%>%dl\\%%<%dl.*', start_line - 1, end_line + 1)
        vim.fn.matchadd('Search', pattern)
      end)
    end
  end
end

-- Create tool approval dialog
function M.create_tool_dialog(tool_call, on_result)
  local func_data = tool_call["function"]
  if not func_data then
    on_result({ approved = false, message = "Invalid tool call" })
    return
  end

  local tool_name = func_data.name
  local args = func_data.arguments or {}
  local reason = args.reason or "No reason provided"

  -- Create buffer for dialog
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

  -- Build dialog content
  local lines = {
    "# Tool Request: " .. tool_name,
    "",
    "## Reason",
    reason,
    "",
    "## Arguments",
  }

  for key, value in pairs(args) do
    if key ~= "reason" then
      if type(value) == "table" then
        table.insert(lines, string.format("- **%s**: %s", key, vim.fn.json_encode(value)))
      else
        table.insert(lines, string.format("- **%s**: %s", key, tostring(value)))
      end
    end
  end

  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")
  table.insert(lines, "**Actions:**")
  table.insert(lines, "  [y] Approve    [n] Reject    [e] Edit args    [m] Add message    [q] Skip all")

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  -- Calculate dialog size
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 4)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create floating window
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Tool Approval ',
    title_pos = 'center',
    zindex = 100,
  }

  local win = vim.api.nvim_open_win(buf, true, opts)
  vim.api.nvim_win_set_option(win, 'wrap', true)
  vim.api.nvim_win_set_option(win, 'linebreak', true)

  -- Store state
  M.tool_dialog.buf = buf
  M.tool_dialog.win = win

  -- Preview the tool action
  local conversation = require('nvchatto.conversation')
  preview_tool(tool_name, args, conversation.state.original_buf)

  -- Refocus the dialog (preview_tool may have changed focus)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end

  -- Set up keymaps
  local function close_and_callback(result)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    -- Clear highlight in preview window if it exists
    if M.tool_dialog.preview_win and vim.api.nvim_win_is_valid(M.tool_dialog.preview_win) then
      pcall(vim.api.nvim_win_call, M.tool_dialog.preview_win, function()
        vim.fn.clearmatches()
      end)
    end
    on_result(result)
  end

  vim.api.nvim_buf_set_keymap(buf, 'n', 'y', '', {
    callback = function()
      close_and_callback({ approved = true, args = args })
    end,
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', 'n', '', {
    callback = function()
      close_and_callback({ approved = false, message = "Rejected by user" })
    end,
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
    callback = function()
      M.tool_dialog.skip_all = true
      close_and_callback({ approved = false, message = "Skipped by user" })
    end,
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', 'm', '', {
    callback = function()
      -- Close dialog and prompt for message
      vim.api.nvim_win_close(win, true)

      -- Use vim.ui.input for message (or fall back to vim.fn.input)
      local message = vim.fn.input("Enter feedback/message: ")
      close_and_callback({ approved = false, message = message })
    end,
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', 'e', '', {
    callback = function()
      -- Close dialog and edit args
      vim.api.nvim_win_close(win, true)

      -- Create editable buffer
      local edit_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(edit_buf, 'buftype', 'nofile')
      vim.api.nvim_buf_set_option(edit_buf, 'filetype', 'json')
      vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, { vim.fn.json_encode(args) })

      local edit_win = vim.api.nvim_open_win(edit_buf, true, {
        relative = 'editor',
        width = 80,
        height = 10,
        row = math.floor((vim.o.lines - 10) / 2),
        col = math.floor((vim.o.columns - 80) / 2),
        style = 'minimal',
        border = 'rounded',
        title = ' Edit Arguments (JSON) ',
        title_pos = 'center',
        zindex = 101,
      })

      -- Set up keymaps for edit buffer
      vim.api.nvim_buf_set_keymap(edit_buf, 'n', '<CR>', '', {
        callback = function()
          local edited_lines = vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false)
          local edited_json = table.concat(edited_lines, "\n")
          local success, edited_args = pcall(vim.fn.json_decode, edited_json)

          vim.api.nvim_win_close(edit_win, true)
          vim.api.nvim_buf_delete(edit_buf, { force = true })

          if success then
            close_and_callback({ approved = true, args = edited_args })
          else
            vim.notify("Invalid JSON, using original args", vim.log.levels.WARN)
            close_and_callback({ approved = true, args = args })
          end
        end,
      })

      vim.api.nvim_buf_set_keymap(edit_buf, 'n', '<Esc>', '', {
        callback = function()
          vim.api.nvim_win_close(edit_win, true)
          vim.api.nvim_buf_delete(edit_buf, { force = true })
          close_and_callback({ approved = false, message = "Cancelled edit" })
        end,
      })

      vim.cmd('startinsert')
    end,
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', {
    callback = function()
      close_and_callback({ approved = false, message = "Cancelled" })
    end,
  })
end

-- Process tool calls interactively
function M.process_tool_calls(tool_calls, original_buf, on_complete)
  local tools = require('nvchatto.conversation')
  local results = {}
  local index = 1

  M.tool_dialog.skip_all = false

  local function process_next()
    if M.tool_dialog.skip_all or index > #tool_calls then
      on_complete(results)
      return
    end

    local tool_call = tool_calls[index]
    local func_data = tool_call["function"]

    M.create_tool_dialog(tool_call, function(result)
      local tool_result = {
        tool_call_id = tool_call.id,
        name = func_data.name,
      }

      if result.approved then
        -- Execute the tool
        local tools_module = require('nvchatto.tools')
        local exec_result = tools_module.execute(func_data.name, result.args, original_buf)
        tool_result.content = exec_result
        tool_result.approved = true
      else
        tool_result.content = result.message or "Rejected by user"
        tool_result.approved = false
      end

      table.insert(results, tool_result)
      index = index + 1

      -- Process next tool with a small delay to let UI update
      vim.defer_fn(process_next, 100)
    end)
  end

  process_next()
end

return M