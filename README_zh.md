[README_en](README.md) | README 中文

# cmp-nvim-tags-plus

这是一个为 `nvim-cmp` 设计的强大补全源，利用 `ctags` 提供类 LSP 的功能，且内存占用极低。非常适合 `rust-analyzer` 导致内存泄漏或资源占用过高的 Rust 项目。

## 功能特性

- **上下文感知补全**：利用 tags 字段（implementation, struct, class）智能过滤 Rust 的 `Type::method` 语法。
- **动态签名提取**：自动读取源文件，在文档窗口提供完整的函数签名（包括跨行定义的参数列表）。
- **幽灵文字签名助手**：输入时在光标下方以虚拟行（virt_lines）形式显示非侵入式的参数提示，不阻挡输入。
- **安全检测**：智能检测，防止在注释或字符串中误触发。
- **轻量快速**：纯 Lua 实现，几乎没有性能开销。

## 安装

使用 [lazy.nvim](https://github.com/folke/lazy.nvim):

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
            manual_key = "<leader>k",  -- 主动唤醒文档窗口，按第二次则消失。
        }
    })
    local cmp = require("cmp")
    cmp.setup({
        sources = {
            { name = "tags" },
        },
    })
  end,
}```

## 默认配置

```lua
require('cmp_nvim_tags_plus').setup({
  max_items = 10,
  keyword_length = 3,
  signature_help = {
    enabled = true,            -- 是否启用签名助手
    virt_lines = true,         -- true: 行下显示; false: 行末显示
    trigger_on_bracket = true, -- 输入 '(' 时是否自动触发
  }
})
```

## 工作原理

- **触发**: 输入 `(` 。在插入模式下移动光标时，利用 `CursorMovedI` 自动更新显示。
- **消失**: 当键入闭合的 `)` 或退出插入模式时自动消失。
- **精准度**: 使用正则表达式确保仅在未闭合的函数调用内部显示签名，且自动避开注释和字符串。

## 我的推荐配置

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
                manual_key = "<leader>k",
            }
        })
        local cmp = require("cmp")
         -- 光标前是否有有效字符检测
        local has_words_before = function()
            local cursor = vim.api.nvim_win_get_cursor(0)
            local line, col = cursor[1], cursor[2]
            if col == 0 then return false end
            local lines = vim.api.nvim_buf_get_lines(0, line - 1, line, true)
            if not lines or #lines == 0 then return false end
            -- 获取光标左侧紧贴着的那个字符
            local char_before = lines[1]:sub(col, col)
            -- 如果它不是空白字符（空格、制表符等），则返回 true
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
                        -- 如果窗口已经弹出了，Tab 自动高亮选中/移动到下一个
                        -- 使用 Select 行为确保它能立刻在视觉上高亮第一项
                        cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
                    elseif has_words_before() then
                        -- 如果窗口没开（比如你按 Esc 关掉了），但前面有单词，Tab 键可以手动强制唤起
                        cmp.complete()
                    else
                        -- 如果前面是空格、行首或缩进，直接执行原生的 Tab 缩进
                        fallback()
                    end
                end, { "i", "s" }),
                ["<CR>"] = cmp.mapping.confirm({ select = true }), -- 回车确认
                --["<Esc>"] = cmp.mapping.abort(), -- Esc 退出（绝对不会卡死）
            }),
            sources = {
                {
                    name = "buffer",
                    option = {
                        get_bufnrs = function()
                            -- 返回所有缓冲区列表, 而不是仅仅当前 buffer
                            return vim.api.nvim_list_bufs()
                        end
                    }
                },
                { name = "tags" },
            },
        })

    cmp.setup.cmdline(':', {
        mapping = cmp.mapping.preset.cmdline({
            -- nvim-cmp 不能支持 up/down 的定制，所以我们使用左右来代替
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

为了确保补全源始终是最新的，建议添加以下配置：

lua/config/keymap.lua

```lua
-- ctag generate
local function update_tags()
    local ft = vim.bo.filetype
    if ft == "rust" then
        print("rusty-tags indexing started...")
        vim.fn.jobstart("rusty-tags vi -O tags", {
            on_exit = function(_, code)
                if code == 0 then
                    print("Rust tags updated!")
                else
                    print("Rust tags failed, check RUST_SRC_PATH")
                end
            end
        })
    else
        local cmd = "ctags --exclude='*.vim' --exclude='build' --exclude='venv' --exclude='target' -R ."
        print("Tags indexing started...")
        vim.fn.jobstart(cmd, {
            on_exit = function(_, code)
                if code == 0 then
                    print("Tags updated!")
                end
            end
        })
    end
end

-- Manual trigger
vim.keymap.set("n", "<F2>", update_tags, { desc = "Update ctags" })

-- Auto-update tags on save
vim.api.nvim_create_autocmd("BufWritePost", {
    pattern = { "*.rs", "*.c", "*.cpp", "*.h", "*.go" },
    callback = function()
        update_tags()
    end,
})
```


## 致谢

本插件基于 quangnguyen30192 的原始项目 [cmp-nvim-tags](https://github.com/quangnguyen30192/cmp-nvim-tags) 进行深度定制。
