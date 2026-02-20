-- HTTP streaming module
local M = {}

-- HTTP streaming request
function M.stream_request(url, data, process_chunk_fn, on_complete)
  local config = require('nvchatto.config')

  -- Get API key from config or environment variable
  local api_key = config.config.api_key or vim.env.OLLAMA_API_KEY

  -- Build curl command
  local auth_header = ""
  if api_key and api_key ~= "" then
    auth_header = string.format("-H 'Authorization: Bearer %s'", api_key);
  end

  -- Use -k to skip certificate verification (common for local Ollama instances with self-signed certs)
  local cmd = string.format(
    "curl -s -k -X POST -H 'Content-Type: application/json' %s -d %s %s",
    auth_header,
    vim.fn.shellescape(data),
    url
  )

  local pending_tool_calls = {}
  local buffer = ""  -- Accumulate partial lines across chunks
  local stderr_buffer = ""  -- Capture stderr for error reporting
  local http_error = nil

  vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, chunk)
      if not chunk or #chunk == 0 then return end

      -- Append chunk to buffer
      buffer = buffer .. table.concat(chunk, "\n")

      -- Split by newlines
      local lines = vim.split(buffer, "\n", { plain = true })

      -- The last element might be incomplete (no trailing newline), keep it in buffer
      buffer = lines[#lines] or ""
      lines[#lines] = nil

      -- Process complete lines
      for _, line in ipairs(lines) do
        if line ~= "" then
          -- Check for HTTP status line
          local status_code = line:match('^HTTP/1%.1 (%d+)')
          if status_code then
            if tonumber(status_code) ~= 200 then
              http_error = "HTTP Error: " .. status_code
              process_chunk_fn({ error = http_error })
            end
          else
            -- Try to parse as JSON
            local success, json_data = pcall(vim.fn.json_decode, line)
            if success then
              local tool_calls, _ = process_chunk_fn(json_data)
              if tool_calls then
                pending_tool_calls = tool_calls
              end
            else
              -- JSON parse error - show in output
              process_chunk_fn({ error = "JSON parse error: " .. tostring(json_data) .. "\nRaw: " .. line:sub(1, 200) })
            end
          end
        end
      end
    end,
    on_stderr = function(_, chunk)
      if chunk and #chunk > 0 then
        stderr_buffer = stderr_buffer .. table.concat(chunk, "\n")
      end
    end,
    on_exit = function(_, exit_code)
      -- Process any remaining data in buffer
      if buffer ~= "" then
        local success, json_data = pcall(vim.fn.json_decode, buffer)
        if success then
          local tool_calls, _ = process_chunk_fn(json_data)
          if tool_calls then
            pending_tool_calls = tool_calls
          end
        else
          process_chunk_fn({ error = "JSON parse error on final data: " .. tostring(json_data) })
        end
        buffer = ""
      end

      -- Report curl/connection errors
      if exit_code ~= 0 then
        local error_msg = stderr_buffer:gsub("^%s+", ""):gsub("%s+$", "")
        if error_msg == "" then
          error_msg = "curl exited with code " .. exit_code
        end
        process_chunk_fn({ error = "Connection error: " .. error_msg })
      end

      vim.schedule(function()
        if #pending_tool_calls > 0 then
          on_complete(pending_tool_calls)
        else
          on_complete(nil)
        end
      end)
    end
  })
end

return M
