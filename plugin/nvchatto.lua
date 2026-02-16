vim.api.nvim_create_user_command(
  "OllamaChat",
  function()
    require('nvchatto').chat_with_context()
  end,
  { desc = "Begin a chat with your configured LLM"}
)
vim.api.nvim_create_user_command(
  "OllamaContinue",
  function()
    require('nvchatto').continue_chat()
  end,
  { desc = "Continue the current chat"}
)

if not vim.g.nvchatto_is_setup then
  require('nvchatto').setup({})
  vim.g.nvchatto_is_setup = true
end
