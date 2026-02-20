-- Tool execution module
local M = {}

-- Helper function to get target buffer
local function get_target_buffer(file_path, original_buf)
  if not file_path then
    return original_buf or 0
  end

  -- Make path relative to working directory
  local cwd = vim.fn.getcwd()
  local full_path = vim.fn.fnamemodify(cwd .. "/" .. file_path, ":p")

  -- Check if file is already open in a buffer
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local buf_name = vim.api.nvim_buf_get_name(buf)
    if buf_name == full_path then
      return buf
    end
  end

  -- Open the file in a new buffer
  local buf = vim.fn.bufnr(full_path, true)
  if vim.fn.filereadable(full_path) == 1 then
    vim.fn.bufload(buf)
  end
  return buf
end

-- Execute a tool
function M.execute(tool_name, args, original_buf)
  local target_buf = get_target_buffer(args.file, original_buf)

  if tool_name == "get_lines" then
    local start_line = args.start_line or 1
    local end_line = args.end_line or vim.api.nvim_buf_line_count(target_buf)
    local lines = vim.api.nvim_buf_get_lines(target_buf, start_line - 1, end_line, false)

    -- Include line numbers for confident editing
    local numbered_lines = {}
    for i, line in ipairs(lines) do
      table.insert(numbered_lines, string.format("%6d | %s", start_line + i - 1, line))
    end

    local file_info = args.file and (" from " .. args.file) or ""
    return table.concat(numbered_lines, "\n") .. "\n-- Lines " .. start_line .. "-" .. (start_line + #lines - 1) .. file_info

  elseif tool_name == "replace_lines" then
    local start_line = args.start_line or 1
    local end_line = args.end_line or start_line
    local lines = args.lines or {}
    vim.api.nvim_buf_set_lines(target_buf, start_line - 1, end_line, false, lines)

    -- Trigger LSP diagnostics update
    vim.schedule(function()
      vim.diagnostic.reset(nil, target_buf)
      -- Trigger buffer change event for LSP
      vim.api.nvim_exec_autocmds("TextChanged", {buffer = target_buf})
    end)

    local file_info = args.file and (" in " .. args.file) or ""
    return string.format("Replaced lines %d-%d with %d new lines%s", start_line, end_line, #lines, file_info)

  elseif tool_name == "insert_lines" then
    local line_num = args.line_num or 1
    local lines = args.lines or {}
    vim.api.nvim_buf_set_lines(target_buf, line_num - 1, line_num - 1, false, lines)

    -- Trigger LSP diagnostics update
    vim.schedule(function()
      vim.diagnostic.reset(nil, target_buf)
      -- Trigger buffer change event for LSP
      vim.api.nvim_exec_autocmds("TextChanged", {buffer = target_buf})
    end)

    local file_info = args.file and (" in " .. args.file) or ""
    return string.format("Inserted %d lines at line %d%s", #lines, line_num, file_info)

  elseif tool_name == "get_diagnostics" then
    local diagnostics = vim.diagnostic.get(target_buf)
    if #diagnostics == 0 then
      local file_info = args.file and (" in " .. args.file) or ""
      return "No diagnostics found" .. file_info
    end

    local file_info = args.file and (" for " .. args.file) or ""
    local result = {"LSP Diagnostics" .. file_info .. ":"}
    local severity_names = {"ERROR", "WARN", "INFO", "HINT"}
    for _, diag in ipairs(diagnostics) do
      local severity = severity_names[diag.severity] or "UNKNOWN"
      local line = diag.lnum + 1
      local col = diag.col + 1
      table.insert(result, string.format("  Line %d:%d [%s] %s", line, col, severity, diag.message))
      if diag.source then
        table.insert(result, string.format("    Source: %s", diag.source))
      end
    end
    return table.concat(result, "\n")

  elseif tool_name == "get_structure" then
    local result = {}

    -- Try LSP document symbols first
    local clients = vim.lsp.get_clients({bufnr = target_buf})
    if #clients > 0 then
      local params = {textDocument = vim.lsp.util.make_text_document_params(target_buf)}
      local symbols = vim.lsp.buf_request_sync(target_buf, 'textDocument/documentSymbol', params, 1000)

      if symbols and symbols[1] and symbols[1].result then
        table.insert(result, "LSP Document Symbols:")
        for _, symbol in ipairs(symbols[1].result) do
          local line = symbol.range.start.line + 1
          table.insert(result, string.format("  %s: %s (line %d)", symbol.kind, symbol.name, line))
        end
      end
    end

    -- Fallback to simple pattern matching
    if #result == 0 then
      table.insert(result, "File Structure (pattern-based):")
      local lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
      for i, line in ipairs(lines) do
        if line:match("^%s*function%s+([%w_]+)") or
           line:match("^%s*def%s+([%w_]+)") or
           line:match("^%s*class%s+([%w_]+)") or
           line:match("^%s*#%s*(.+)$") or
           line:match("^%s*--%s*(.+)$") or
           line:match("^%s*//%s*(.+)$") then
          table.insert(result, string.format("  Line %d: %s", i, line:gsub("^%s*", "")))
        end
      end
    end

    return table.concat(result, "\n")

  elseif tool_name == "search_workspace" then
    local pattern = args.pattern
    local file_pattern = args.file_pattern or ""
    local case_flag = args.case_sensitive and "" or "-i"
    local cwd = vim.fn.getcwd()

    local cmd = string.format("cd %s && rg %s --line-number --column --no-heading --color=never %s %s",
      vim.fn.shellescape(cwd),
      case_flag,
      vim.fn.shellescape(pattern),
      file_pattern ~= "" and vim.fn.shellescape(file_pattern) or "")

    local output = vim.fn.system(cmd)

    if vim.v.shell_error ~= 0 then
      return "No matches found for pattern: " .. pattern
    end

    -- Limit output to first 50 matches
    local lines = vim.split(output, "\n")
    local result_lines = {"Search results for '" .. pattern .. "':"}
    for i = 1, math.min(50, #lines) do
      if lines[i] ~= "" then
        table.insert(result_lines, lines[i])
      end
    end

    if #lines > 50 then
      table.insert(result_lines, string.format("\n... (%d more matches)", #lines - 50))
    end

    return table.concat(result_lines, "\n")
  end

  return "Unknown tool: " .. tool_name
end

-- Get tool definitions for LLM
function M.get_definitions()
  local function_def = "function"
  return {
    {
      type = "function",
      [function_def] = {
        name = "get_lines",
        description = "Get lines from a buffer. Use 'file' parameter to read from files other than the current buffer.",
        parameters = {
          type = "object",
          properties = {
            file = {type = "string", description = "File path/name to read from (required when reading a different file)"},
            start_line = {type = "integer", description = "Starting line number"},
            end_line = {type = "integer", description = "Ending line number"},
            reason = {type = "string", description = "Reason tool is being requested"}
          },
          required = {"reason"}
        }
      }
    },
    {
      type = "function",
      [function_def] = {
        name = "replace_lines",
        description = "Replace specific line range with new lines in a buffer. Use 'file' parameter to modify files other than the current buffer.",
        parameters = {
          type = "object",
          properties = {
            file = {type = "string", description = "File path/name to modify (required when modifying a different file)"},
            start_line = {type = "integer", description = "Starting line number to replace"},
            end_line = {type = "integer", description = "Ending line number to replace"},
            lines = {type = "array", description = "New lines to insert"},
            reason = {type = "string", description = "Reason tool is being requested"}
          },
          required = {"start_line", "end_line", "lines", "reason"}
        }
      }
    },
    {
      type = "function",
      [function_def] = {
        name = "insert_lines",
        description = "Insert new lines at a specific position without replacing existing content. Use 'file' parameter to modify files other than the current buffer.",
        parameters = {
          type = "object",
          properties = {
            file = {type = "string", description = "File path/name to modify (required when modifying a different file)"},
            line_num = {type = "integer", description = "Line number where to insert new lines"},
            lines = {type = "array", description = "New lines to insert"},
            reason = {type = "string", description = "Reason tool is being requested"}
          },
          required = {"line_num", "lines", "reason"}
        }
      }
    },
    {
      type = "function",
      [function_def] = {
        name = "get_diagnostics",
        description = "Get LSP diagnostics and compile errors for a buffer",
        parameters = {
          type = "object",
          properties = {
            file = {type = "string", description = "Optional file path/name to check diagnostics for"},
            reason = {type = "string", description = "Reason tool is being requested"}
          },
          required = {"reason"}
        }
      }
    },
    {
      type = "function",
      [function_def] = {
        name = "get_structure",
        description = "Get file structure including functions, classes, and headers using LSP or pattern matching",
        parameters = {
          type = "object",
          properties = {
            reason = {type = "string", description = "Reason tool is being requested"}
          },
          required = {"reason"}
        }
      }
    },
    {
      type = "function",
      [function_def] = {
        name = "search_workspace",
        description = "Search for text patterns across files in the workspace using ripgrep",
        parameters = {
          type = "object",
          properties = {
            pattern = {type = "string", description = "Text pattern or regex to search for"},
            file_pattern = {type = "string", description = "Optional file glob pattern (e.g., '*.lua', '*.rs')"},
            case_sensitive = {type = "boolean", description = "Whether search is case sensitive (default: false)"},
            reason = {type = "string", description = "Reason tool is being requested"}
          },
          required = {"pattern", "reason"}
        }
      }
    }
  }
end

return M
