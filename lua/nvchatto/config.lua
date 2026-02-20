-- Configuration module
local M = {}

M.defaults = {
  base_url = "http://localhost:11434",
  model = "qwen3:4b",
  api_key = nil,  -- Optional: API key for cloud providers (e.g., ollama.com). Falls back to $OLLAMA_API_KEY env var
  timeout = 30000,
  think = true,
  num_ctx = nil  -- Context length (tokens), nil = use model default
}

M.config = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M
