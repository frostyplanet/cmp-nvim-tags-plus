local M = {}
local util = require('vim.lsp.util')
local ns_id = vim.api.nvim_create_namespace('cmp_nvim_tags_plus')

M.config = {
  max_items = 10,
  keyword_length = 3,
  signature_help = {
    enabled = true,
    virt_lines = true,
    trigger_character = "(", -- Default trigger character, set to nil to disable auto trigger
  }
}

--- Internal state
local setup_done = false
M.timer = nil

function M.toggle_signature()
  local extmarks = vim.api.nvim_buf_get_extmarks(0, ns_id, 0, -1, {})
  if #extmarks > 0 then
    M.close_signature()
  else
    M.show_signature()
  end
end

--- Setup function to configure the plugin and optional keybindings
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  if setup_done then return end

  if M.config.signature_help.enabled then
    local group = vim.api.nvim_create_augroup("CmpNvimTagsPlus", { clear = true })
    M.timer = vim.loop.new_timer()

    -- Auto-update on cursor move in insert mode with debounce
    vim.api.nvim_create_autocmd("CursorMovedI", {
      group = group,
      callback = function()
        if M.timer then
          M.timer:stop()
          M.timer:start(100, 0, vim.schedule_wrap(function()
            M.show_signature()
          end))
        end
      end,
    })

    -- Auto-cleanup on leave
    vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave" }, {
      group = group,
      callback = function()
        if M.timer then M.timer:stop() end
        M.close_signature()
      end,
    })

    -- Automatic bracket trigger
    local trigger_char = M.config.signature_help.trigger_character
    if trigger_char then
      vim.keymap.set("i", trigger_char, function()
        vim.api.nvim_feedkeys(trigger_char, "n", true)
        if M.timer then
          M.timer:stop()
          M.timer:start(50, 0, vim.schedule_wrap(function()
            M.show_signature()
          end))
        end
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
  if not list_tags_ok or type(tags) ~= "table" then return {} end

  local current_file = vim.api.nvim_buf_get_name(0)

  -- Priority rules:
  -- 1. Matches prefix (implementation/struct/class/enum)
  -- 2. Belongs to the current buffer
  table.sort(tags, function(a, b)
    local a_match_prefix = prefix and (a.implementation == prefix or a.struct == prefix or a.class == prefix or a.enum == prefix)
    local b_match_prefix = prefix and (b.implementation == prefix or b.struct == prefix or b.class == prefix or b.enum == prefix)

    if a_match_prefix ~= b_match_prefix then
      return a_match_prefix
    end

    local a_is_current = a.filename == current_file
    local b_is_current = b.filename == current_file
    if a_is_current ~= b_is_current then
      return a_is_current
    end
    return false
  end)

  for i, tag in ipairs(tags) do
    if i > M.config.max_items then break end
    local filename = vim.fn.fnamemodify(tag.filename, ":t")
    local title = '# ' .. filename .. ' [' .. tag.kind .. ']'
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

  -- Fast fail if line ends with space or is empty
  if line_to_cursor:match("%s$") or #line_to_cursor == 0 then
    M.close_signature()
    return
  end

  -- Fast fail if trigger character is enabled but not present in line before cursor
  local trigger_char = M.config.signature_help.trigger_character
  if trigger_char then
    local escaped_trigger = trigger_char:gsub("([^%w])", "%%%1")
    if not line_to_cursor:find(escaped_trigger) then
      M.close_signature()
      return
    end
  end

  local prefix, func, is_method
  prefix, func = line_to_cursor:match("([%a_][%w_]*)::([%a_][%w_]*)%s*%([^)]*$")
  is_method = false
  if not func then
    prefix, func = line_to_cursor:match("([%a_][%w_]*)%.([%a_][%w_]*)%s*%([^)]*$")
    is_method = true
  end
  if not func then
    func = line_to_cursor:match("([%a_][%w_]*)%s*%([^)]*$")
    is_method = false
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
  local source_file = first_doc:match("# ([^%s]+)")

  if not signature then
    M.close_signature()
    return
  end

  -- Clean up signature: take first line or sensible part
  signature = signature:gsub("\n", " "):gsub("%s+", " "):gsub("^%s*", "")
  local param_part = signature:match("(%(.*)$")
  if param_part then signature = param_part end

  M.close_signature()
  local indent = line:match("^%s*") or ""
  local display_text = ""
  if source_file then
    display_text = "  (" .. source_file .. ") => " .. signature
  else
    display_text = "  => " .. signature
  end

  if M.config.signature_help.virt_lines then
    vim.api.nvim_buf_set_extmark(0, ns_id, row, 0, {
      virt_lines = {{ { indent .. display_text, "Comment" } }},
      virt_lines_above = false,
    })
  else
    vim.api.nvim_buf_set_extmark(0, ns_id, row, 0, {
      virt_text = {{ display_text, "Comment" }},
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

  local line = request.context.cursor_before_line
  local prefix, input, is_method

  -- Fallback to regex
  -- 1. Static/Assoc: Type::func
  prefix, input = line:match("([%a_][%w_]*)::([%w_]*)$")
  is_method = false
  -- 2. Method: obj.func
  if not prefix then
    prefix, input = line:match("([%a_][%w_]*)%.([%w_]*)$")
    is_method = true
  end
  -- 3. Fallback
  if not prefix then
    input = string.sub(line, request.offset)
    is_method = false
  end

  if string.len(input) >= M.config.keyword_length or (prefix and #input >= 0) then
    if prefix then
      local ok, list = pcall(vim.fn.taglist, "^" .. input)
      if ok and type(list) == "table" then
        local seen = {}
        local current_file = vim.api.nvim_buf_get_name(0)

        -- Check if there are any tags matching prefix type
        local has_any_match = false
        for _, t in ipairs(list) do
          if t.implementation == prefix or t.struct == prefix or t.class == prefix or t.enum == prefix then
            has_any_match = true
            break
          end
        end

        if has_any_match then
          -- Normal mode: strict filtering by prefix type
          for _, t in ipairs(list) do
            if t.implementation == prefix or t.struct == prefix or t.class == prefix or t.enum == prefix then
              if not seen[t.name] then
                table.insert(items, {
                  label = t.name,
                  kind = cmp.lsp.CompletionItemKind.Method,
                })
                seen[t.name] = true
              end
            end
          end
        else
          -- Fallback mode: no type matches prefix. Priority to current buffer tags.
          local matched_items = {}
          for _, t in ipairs(list) do
            if not seen[t.name] then
              local is_current = (t.filename == current_file)
              table.insert(matched_items, {
                tag = t,
                is_current = is_current
              })
              seen[t.name] = true
            end
          end

          table.sort(matched_items, function(a, b)
            if a.is_current ~= b.is_current then
              return a.is_current
            end
            return false
          end)

          for _, item in ipairs(matched_items) do
            table.insert(items, {
              label = item.tag.name,
              kind = cmp.lsp.CompletionItemKind.Method,
              sortText = string.format("%04d_%s", item.is_current and 1 or 2, item.tag.name),
            })
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
end

function M:is_available() return true end

return M
