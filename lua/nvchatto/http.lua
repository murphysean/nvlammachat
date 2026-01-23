-- HTTP streaming module
local M = {}

-- HTTP streaming request
function M.stream_request(url, data, process_chunk_fn, on_complete)
  local cmd = string.format(
    "curl -s -X POST -H 'Content-Type: application/json' -d %s %s",
    vim.fn.shellescape(data), url
  )
  
  local pending_tool_calls = {}
  
  vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, chunk)
      if chunk and #chunk > 0 then
        for _, line in ipairs(chunk) do
          if line ~= "" then
            local success, json_data = pcall(vim.fn.json_decode, line)
            if success then
              local tool_calls, is_done = process_chunk_fn(json_data)
              
              if tool_calls then
                pending_tool_calls = tool_calls
              end
            end
          end
        end
      end
    end,
    on_exit = function()
      vim.defer_fn(function()
        if #pending_tool_calls > 0 then
          on_complete(pending_tool_calls)
        else
          on_complete(nil)
        end
      end, 200)
    end
  })
end

return M
