local source = {}
local util = require('vim.lsp.util')

function source.get_full_signature(tag)
  if not tag.filename or not tag.cmd then return nil end
  local f = io.open(tag.filename, "r")
  if not f then return nil end
  
  local pattern = tag.cmd:sub(3, -3):gsub("\\", "") -- 去掉 /^ 和 $/ 并处理转义
  local lines = {}
  local found = false
  local count = 0
  for line in f:lines() do
    if not found then
      if line:find(pattern, 1, true) then
        found = true
      end
    end
    
    if found then
      table.insert(lines, line)
      count = count + 1
      -- 启发式停止条件：包含 ) 且 (包含 { 或 ; 或 下一行开始缩进减少)
      if line:find(")") and (line:find("{") or line:find(";") or count > 10) then
        break
      end
    end
  end
  f:close()
  return found and table.concat(lines, "\n") or nil
end

function source.build_documentation(word, prefix)
  local document = {}
  local list_tags_ok, tags = pcall(vim.fn.taglist, "^" .. word .. "$")

  if not list_tags_ok or type(tags) ~= "table" then
    return ""
  end

  -- 如果有前缀，优先显示匹配前缀的标签
  if prefix then
    local filtered = {}
    for _, t in ipairs(tags) do
      if t.implementation == prefix or t.struct == prefix or t.class == prefix or t.enum == prefix then
        table.insert(filtered, t)
      end
    end
    if #filtered > 0 then tags = filtered end
  end

  for i, tag in ipairs(tags) do
    if i > 5 then break end
    local title = '# ' .. tag.filename .. ' [' .. tag.kind .. ']'
    local body = ""
    
    local full_sig = source.get_full_signature(tag)
    if full_sig then
      body = "```rust\n" .. full_sig .. "\n```"
    elseif #tag.cmd >= 5 then
      body = '  __' .. tag.cmd:sub(3, -3):gsub('%s+', ' ') .. '__'
    end

    local doc = title .. "\n" .. body
    if tag.implementation then doc = doc .. '\n  impl: _' .. tag.implementation .. '_' end
    if tag.struct then doc = doc .. '\n  in ' .. tag.struct end
    table.insert(document, doc)
  end

  return document
end

local default_options = {
  complete_defer = 100,
  max_items = 10,
  keyword_length = 3,
  exact_match = false,
  current_buffer_only = false,
}
local global_options = {}

source.new = function()
  return setmetatable({}, { __index = source })
end

source.get_keyword_pattern = function()
  return '\\%([^[:alnum:][:blank:]]\\|\\k\\+\\)'
end

function source:get_debug_name()
  return 'tags'
end

function source:complete(request, callback)
  local items = {}
  local cmp = require('cmp')
  global_options = vim.tbl_deep_extend('keep', request.option or {}, default_options)
  vim.defer_fn(function()
    local line = request.context.cursor_before_line
    local prefix, input = line:match("([%a_][%w_]*)::([%w_]*)$")
    
    if not prefix then
      input = string.sub(line, request.offset)
    end

    if string.len(input) >= global_options.keyword_length or (prefix and #input >= 0) then
      if prefix then
        local ok, list = pcall(vim.fn.taglist, "^" .. input)
        if ok and type(list) == "table" then
          local seen = {}
          for _, t in ipairs(list) do
            if t.implementation == prefix or t.struct == prefix or t.class == prefix or t.enum == prefix then
              if not seen[t.name] then
                table.insert(items, {
                  label = t.name,
                  kind = cmp.lsp.CompletionItemKind.Method,
                  detail = prefix,
                  data = { prefix = prefix }
                })
                seen[t.name] = true
              end
            end
          end
        end
      else
        local _, list = pcall(function()
          return vim.fn.getcompletion(input, "tag")
        end)
        for _, value in pairs(list or {}) do
          table.insert(items, {
            label = value,
            kind = cmp.lsp.CompletionItemKind.Tag,
          })
        end
      end
    end

    callback({
      items = items,
      isIncomplete = true
    })
  end, global_options.complete_defer)
end

function source:resolve(completion_item, callback)
  local cmp = require('cmp')
  local prefix = completion_item.data and completion_item.data.prefix
  local docs = source.build_documentation(completion_item.label, prefix)
  local formartDocument = util.convert_input_to_markdown_lines(docs)
  
  completion_item.documentation = {
    kind = cmp.lsp.MarkupKind.Markdown,
    value = table.concat(formartDocument, '\n')
  }

  callback(completion_item)
end

function source:is_available()
  return true
end

return source
