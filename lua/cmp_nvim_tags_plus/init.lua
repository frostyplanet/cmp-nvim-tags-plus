local M = {}
local util = require('vim.lsp.util')
local ns_id = vim.api.nvim_create_namespace('cmp_nvim_tags_plus')

M.config = {
  max_items = 10,
  keyword_length = 3,
  signature_help = {
    enabled = true,
    virt_lines = true,
    trigger_on_bracket = true, -- Automatically trigger on '('
    manual_key = nil,          -- Key to manually trigger (e.g., "<leader>k")
  }
}

--- Internal state to prevent multiple setups
local setup_done = false

--- Setup function to configure the plugin and optional keybindings
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  if setup_done then return end

  if M.config.signature_help.enabled then
    local group = vim.api.nvim_create_augroup("CmpNvimTagsPlus", { clear = true })

    -- Auto-update on cursor move in insert mode
    vim.api.nvim_create_autocmd("CursorMovedI", {
      group = group,
      callback = function() M.show_signature() end,
    })

    -- Auto-cleanup on leave
    vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave" }, {
      group = group,
      callback = function() M.close_signature() end,
    })

    -- Manual Keybinding (Supports both Normal and Insert mode)
    if M.config.signature_help.manual_key then
      vim.keymap.set({ "n", "i" }, M.config.signature_help.manual_key, function()
        local extmarks = vim.api.nvim_buf_get_extmarks(0, ns_id, 0, -1, {})
        if #extmarks > 0 then
          M.close_signature()
        else
          M.show_signature()
        end
      end, { desc = "Toggle Tag Signature Help" })
    end

    -- Automatic bracket trigger
    if M.config.signature_help.trigger_on_bracket then
      vim.keymap.set("i", "(", function()
        vim.api.nvim_feedkeys("(", "n", true)
        vim.schedule(function() M.show_signature() end)
      end, { desc = "Auto Tag Signature Help" })
    end
  end

  setup_done = true
end

-- --- Internal Logic: Tag Processing ---

function M.get_full_signature(tag)
  if not tag.filename or not tag.cmd then return nil end
  local f = io.open(tag.filename, "r")
  if not f then return nil end

  local pattern = tag.cmd:sub(3, -3):gsub("\\", "")
  local lines = {}
  local found = false
  local count = 0
  for line in f:lines() do
    if not found then
      if line:find(pattern, 1, true) then found = true end
    end
    if found then
      table.insert(lines, line)
      count = count + 1
      if line:find(")") and (line:find("{") or line:find(";") or count > 10) then break end
    end
  end
  f:close()
  return found and table.concat(lines, "\n") or nil
end

--- Enhanced check for comments or strings using both synstack and Treesitter
local function is_in_comment_or_string()
  -- 1. Try Treesitter (Modern approach)
  local ts_available, ts_utils = pcall(require, 'nvim-treesitter.ts_utils')
  if ts_available then
    local node = ts_utils.get_node_at_cursor()
    if node then
      local type = node:type():lower()
      if type:find("comment") or type:find("string") then
        return true
      end
    end
  end

  -- 2. Fallback to synstack (Legacy approach)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1], cursor[2]
  local ok, stack = pcall(vim.fn.synstack, row, col + 1)
  if ok and stack then
    for _, id in ipairs(stack) do
      local name = vim.fn.synIDattr(id, "name"):lower()
      if name:find("comment") or name:find("string") then
        return true
      end
    end
  end

  return false
end

function M.build_documentation(word, prefix)
  local document = {}
  local list_tags_ok, tags = pcall(vim.fn.taglist, "^" .. word .. "$")
  if not list_tags_ok or type(tags) ~= "table" then return "" end

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
    if i > M.config.max_items then break end
    local title = '# ' .. tag.filename .. ' [' .. tag.kind .. ']'
    local body = ""
    local full_sig = M.get_full_signature(tag)
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

-- --- Signature Help Logic ---

function M.close_signature()
  vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)
end

function M.show_signature()
  if not M.config.signature_help.enabled then return end
  if is_in_comment_or_string() then
    M.close_signature()
    return
  end

  local line = vim.api.nvim_get_current_line()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local line_to_cursor = line:sub(1, col)

  -- Logic for finding function call context:
  -- We look for the most recent unclosed parenthesis.
  local prefix, func = line_to_cursor:match("([%a_][%w_]*)::([%a_][%w_]*)%s*%([^)]*$")
  if not func then
    func = line_to_cursor:match("([%a_][%w_]*)%s*%([^)]*$")
  end

  -- Fallback for Normal Mode: if cursor is ON a parenthesis or just after it
  if not func and vim.api.nvim_get_mode().mode == 'n' then
    local line_after = line:sub(col + 1)
    -- Try to match if cursor is on/before '('
    prefix, func = line:match("([%a_][%w_]*)::([%a_][%w_]*)%s*%(")
    if not func then func = line:match("([%a_][%w_]*)%s*%(") end
  end

  if not func then
    M.close_signature()
    return
  end

  local docs_table = M.build_documentation(func, prefix)
  if #docs_table == 0 then
    M.close_signature()
    return
  end

  local first_doc = docs_table[1]
  local signature = first_doc:match("```rust\n(.-)\n```") or first_doc:match("__(.-)__")
  if not signature then
    M.close_signature()
    return
  end

  signature = signature:gsub("\n", " "):gsub("%s+", " "):gsub("^%s*", "")
  local param_part = signature:match("(%(.*)$")
  if param_part then signature = param_part end

  M.close_signature()
  local indent = line:match("^%s*") or ""

  if M.config.signature_help.virt_lines then
    vim.api.nvim_buf_set_extmark(0, ns_id, row, 0, {
      virt_lines = {{ { indent .. "  => " .. signature, "Comment" } }},
      virt_lines_above = false,
    })
  else
    vim.api.nvim_buf_set_extmark(0, ns_id, row, 0, {
      virt_text = {{ "  => " .. signature, "Comment" }},
      virt_text_pos = 'eol',
    })
  end
end

-- --- nvim-cmp Source ---

M.new = function() return setmetatable({}, { __index = M }) end
M.get_keyword_pattern = function() return '\\%([^[:alnum:][:blank:]]\\|\\k\\+\\)' end
function M:get_debug_name() return 'tags' end

function M:complete(request, callback)
  local items = {}
  local cmp_ok, cmp = pcall(require, 'cmp')
  if not cmp_ok then return callback({ items = {}, isIncomplete = false }) end

  vim.defer_fn(function()
    local line = request.context.cursor_before_line
    local prefix, input = line:match("([%a_][%w_]*)::([%w_]*)$")
    if not prefix then input = string.sub(line, request.offset) end

    if string.len(input) >= M.config.keyword_length or (prefix and #input >= 0) then
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
        local _, list = pcall(function() return vim.fn.getcompletion(input, "tag") end)
        for _, value in pairs(list or {}) do
          table.insert(items, { label = value, kind = cmp.lsp.CompletionItemKind.Tag })
        end
      end
    end
    callback({ items = items, isIncomplete = true })
  end, 100)
end

function M:resolve(completion_item, callback)
  local cmp_ok, cmp = pcall(require, 'cmp')
  if not cmp_ok then return callback(completion_item) end

  local prefix = completion_item.data and completion_item.data.prefix
  local docs = M.build_documentation(completion_item.label, prefix)
  local formartDocument = util.convert_input_to_markdown_lines(docs)
  completion_item.documentation = {
    kind = cmp.lsp.MarkupKind.Markdown,
    value = table.concat(formartDocument, '\n')
  }
  callback(completion_item)
end

function M:is_available() return true end

return M
