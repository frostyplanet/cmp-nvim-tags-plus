# cmp-nvim-tags-plus

README_en | [README_zh](README_zh.md)

A powerful Neovim completion source for `nvim-cmp` that leverages `ctags` to provide LSP-like features without the heavy memory footprint. Ideal for Rust projects where `rust-analyzer` might be too resource-intensive.

## Features

- **Context-Aware Completion**: Intelligent filtering for Rust `Type::method` syntax using tag fields (implementation, struct, class).
- **Dynamic Signature Extraction**: Automatically reads source files to provide full function signatures (including multi-line parameters) in the documentation window.
- **Ghost-Text Signature Help**: Non-intrusive parameter hints displayed as virtual lines (virt_lines) directly below your cursor while typing.
- **Safety Checks**: Smart detection to prevent triggers in comments or strings.
- **Fast and Lightweight**: Pure Lua implementation with minimal overhead.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "hrsh7th/nvim-cmp",
  dependencies = {
    "frostyplanet/cmp-nvim-tags-plus",
  },
  config = function()
    require("cmp_nvim_tags_plus").setup({
        signature_help = {
            enabled = true,
            virt_lines = true,
            manual_key = "<leader>k",  -- bind the key to call document hint explicitly (when cursor on function name). Press twice it will disappear
        }
    })
    local cmp = require("cmp")
    cmp.setup({
        sources = {
            { name = "tags" },
        },
    })
  end,
}
```

## Default Configuration

```lua
require('cmp_nvim_tags_plus').setup({
  max_items = 10,
  keyword_length = 3,
  signature_help = {
    enabled = true,            -- Enable signature help
    virt_lines = true,         -- true: show below line; false: show at EOL
    trigger_on_bracket = true, -- Auto trigger on '('
    manual_key = nil,          -- no default keymap
  }
})
```

## How it Works

- **Trigger**: Triggered by typing `(`. It continuously updates as you move the cursor in Insert mode using `CursorMovedI`.
- **Dismiss**: Automatically disappears when you type the closing `)` or leave Insert mode.
- **Accuracy**: Uses regex to ensure signatures are only shown when you are inside an unclosed function call.

### My recommend config for rust

To ensure your completion source is always up-to-date, add this to your configuration:

```lua
local function update_tags()
  local ft = vim.bo.filetype
  if ft == "rust" then
    vim.fn.jobstart("rusty-tags vi -O tags")
  else
    vim.fn.jobstart("ctags -R .")
  end
end

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = { "*.rs", "*.c", "*.cpp", "*.go" },
  callback = update_tags,
})
```

## Credits

Based on the original [cmp-nvim-tags](https://github.com/quangnguyen30192/cmp-nvim-tags) by quangnguyen30192.
