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
          if line:match('^HTTP/1%.1 ([0-9]+)%s*') then
            local status_code = line:match('%d+')
            if status_code and tonumber(status_code) ~= 200 then
              vim.notify('HTTP error: ' .. status_code, vim.log.levels.ERROR)
            end
          end
          if line ~= "" then
            local success, json_data = pcall(vim.fn.json_decode, line)
            if success then
              local tool_calls, _ = process_chunk_fn(json_data)

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
