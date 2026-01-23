# Ollama Neovim Plugin

A minimal Neovim plugin for integrating with Ollama servers.

## Features

- **Buffer Context Chat**: Chat with LLM using current buffer context (file, cursor position, working directory)
- **Auto-completion**: Context-aware code completion using surrounding lines
- **Tool Support**: LLM can respond with replacement, prepend, or append actions
- **Buffer Tools**: LLM has access to read/write buffer operations

## Installation

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'your-username/ollama-nvim',
  config = function()
    require('ollama-nvim').setup({
      host = "192.168.254.37",  -- Your Ollama server IP
      port = 11434,
      model = "qwen3:4b"
    })
  end
}
```

## Usage

### Key Mappings

- `<leader>oc` (normal mode): Chat with buffer context
- `<leader>og` (normal mode): Generate completion with context
- `<C-x><C-o>` (insert mode): Omni-completion

### Commands

- `:OllamaChat` - Chat with buffer context
- `:OllamaComplete` - Generate completion

### Buffer Context

The LLM receives:
- Current line number and cursor position
- Buffer name (file path)
- Working directory
- Total line count

### Available Tools for LLM

- `read_buffer(start_line, end_line)` - Read lines from buffer
- `write_buffer(line_num, content)` - Write content at line
- `replace_buffer(start_line, end_line, content)` - Replace lines
- `get_line()` - Get current line content

### LLM Tool Responses

The LLM can respond with special prefixes:

- `REPLACE:` - Replace selected text
- `PREPEND:` - Add text before selection
- `APPEND:` - Add text after selection
- Plain text - Display as notification

## Configuration

```lua
require('ollama-nvim').setup({
  host = "192.168.254.37",     -- Ollama server host
  port = 11434,          -- Ollama server port
  model = "qwen3:4b",      -- Model to use
  timeout = 30000        -- Request timeout
})
```
