" Ollama Neovim Plugin
" Provides integration with Ollama server for code assistance

if exists('g:loaded_ollama_nvim')
  finish
endif
let g:loaded_ollama_nvim = 1

" Default configuration
if !exists('g:ollama_host')
  let g:ollama_host = '192.168.254.37'
endif

if !exists('g:ollama_port')
  let g:ollama_port = 11434
endif

if !exists('g:ollama_model')
  let g:ollama_model = 'qwen3:4b'
endif

" Commands
command! -range OllamaChat lua require('ollama-nvim').chat_with_selection()
command! OllamaComplete lua require('ollama-nvim').complete_with_context()

" Auto setup
lua << EOF
require('ollama-nvim').setup({
  host = vim.g.ollama_host,
  port = vim.g.ollama_port,
  model = vim.g.ollama_model
})
EOF
