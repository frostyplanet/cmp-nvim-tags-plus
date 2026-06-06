[README_en](README.md) | README_zh

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

## 使用建议

### 保存时自动更新 Tags (推荐)

为了确保补全源始终是最新的，建议添加以下配置：

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

## 致谢

本插件基于 quangnguyen30192 的原始项目 [cmp-nvim-tags](https://github.com/quangnguyen30192/cmp-nvim-tags) 进行深度定制。
