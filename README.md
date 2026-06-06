# cmp-nvim-tags-plus

README_en | [README 中文](README_zh.md)

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
        }
    })

    -- Optionally, manually bind the signature toggle
    vim.keymap.set({ "n", "i" }, "<leader>k", function()
        require("cmp_nvim_tags_plus").toggle_signature()
    end, { desc = "Toggle Tag Signature Help" })

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
  }
})
```

## How it Works

- **Trigger**: Triggered by typing `(`. It continuously updates as you move the cursor in Insert mode using `CursorMovedI`.
- **Dismiss**: Automatically disappears when you type the closing `)` or leave Insert mode.
- **Accuracy**: Uses regex to ensure signatures are only shown when you are inside an unclosed function call.

### My recommend config for rust

lua/plugins/nvim-cmp.lua

```lua
return {
    "hrsh7th/nvim-cmp",
    dependencies = {
        "hrsh7th/cmp-buffer",
        "hrsh7th/cmp-path",
        "hrsh7th/cmp-cmdline",
        "frostyplanet/cmp-nvim-tags-plus",
    },
    config = function()
        require("cmp_nvim_tags_plus").setup({
            signature_help = {
                enabled = true,
                virt_lines = true,
            }
        })
        local cmp = require("cmp")
         -- detect valid char before cursor
        local has_words_before = function()
            local cursor = vim.api.nvim_win_get_cursor(0)
            local line, col = cursor[1], cursor[2]
            if col == 0 then return false end
            local lines = vim.api.nvim_buf_get_lines(0, line - 1, line, true)
            if not lines or #lines == 0 then return false end
            local char_before = lines[1]:sub(col, col)
            return char_before:match("%s") == nil
        end
        cmp.setup({
            window = {
                completion = cmp.config.window.bordered(),
                documentation = cmp.config.window.bordered(),
            },
            formatting = {
                format = function(entry, vim_item)
                    vim_item.menu = ({
                        buffer = "[Buf]",
                        tags = "[Tag]",
                    })[entry.source.name]
                    return vim_item
                end,
            },
            mapping = cmp.mapping.preset.insert({
                ["<Down>"] = cmp.mapping.select_next_item(),
                ["<Up>"] = cmp.mapping.select_prev_item(),
                ["<Tab>"] = cmp.mapping(function(fallback)
                    if cmp.visible() then
                        cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
                    elseif has_words_before() then
                        cmp.complete()
                    else
                        fallback()
                    end
                end, { "i", "s" }),
                ["<CR>"] = cmp.mapping.confirm({ select = true }),
            }),
            sources = {
                { name = "tags" },
                {
                    name = "buffer",
                    option = {
                        get_bufnrs = function()
                            -- complete with all buffer instead of only current buffer
                            return vim.api.nvim_list_bufs()
                        end
                    }
                },
            },
        })

    cmp.setup.cmdline(':', {
        mapping = cmp.mapping.preset.cmdline({
            -- nvim-cmp cannot work with custom up/down key, we use left/right instead
            ['<Right>'] = cmp.mapping(function(fallback)
                if cmp.visible() then
                    cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
                else
                    fallback()
                end
            end, { "c" }),
            ['<Left>'] = cmp.mapping(function(fallback)
                if cmp.visible() then
                    cmp.select_prev_item({ behavior = cmp.SelectBehavior.Select })
                else
                    fallback()
                end
            end, { "c" }),
        }),
        sources = cmp.config.sources({
            { name = 'path', option = { trailing_slash = true } },
        }, {
            { name = 'cmdline' },
        }),
    })
    end
}

```

To ensure your completion source is always up-to-date, add this to your configuration:

lua/config/keymap.lua

```lua
-- ctag generate
local function update_tags(silent)
    local ft = vim.bo.filetype
    if ft == "rust" then
        vim.fn.jobstart("rusty-tags vi -O tags", {
            on_exit = function(_, code)
                if code == 0 then
                    if not silent then
                        print("Rust tags updated")
                    end
                else
                    print("Rust tags failed!")
                end
            end
        })
    else
        local cmd = "ctags --exclude='*.vim' --exclude='build' --exclude='venv' --exclude='target' -R ."
        vim.fn.jobstart(cmd, {
            on_exit = function(_, code)
                if code == 0 then
                    if not silent then
                        print("Tags updated")
                    end
                else
                    print("Tags update failed!")
                end
            end
        })
    end
end

-- Manual trigger
vim.keymap.set("n", "<F2>", update_tags, { desc = "Update ctags" })

-- Toggle Tag Signature Help
vim.keymap.set({ "n", "i" }, "<leader>k", function()
    require("cmp_nvim_tags_plus").toggle_signature()
end, { desc = "Toggle Tag Signature Help" })

-- Auto-update tags on save
vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = { "*.rs", "*.c", "*.cpp", "*.h", "*.go" },
    callback = function()
        update_tags(true)
    end,
})

```

## Credits

Based on the original [cmp-nvim-tags](https://github.com/quangnguyen30192/cmp-nvim-tags) by quangnguyen30192.
