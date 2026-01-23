-- Configuration module
local M = {}

M.defaults = {
  host = "192.168.254.37",
  port = 11434,
  model = "qwen3:4b",
  timeout = 30000,
  think = true,
  num_ctx = nil  -- Context length (tokens), nil = use model default
}

M.config = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M
