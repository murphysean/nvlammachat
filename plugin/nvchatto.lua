vim.api.nvim_create_user_command(
  "NVChatto",
  function()
    require('nvchatto').toggle()
  end,
  { desc = "Toggle NVChatto window" }
)

if not vim.g.nvchatto_is_setup then
  require('nvchatto').setup({})
  vim.g.nvchatto_is_setup = true
end