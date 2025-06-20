--- @diagnostic disable: deprecated
-- based on yacineMTB/dingllm.nvim

local Job = require "plenary.job"
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local previewers = require "telescope.previewers"
local mini_notify = require('mini.notify')

mini_notify.setup()
local notify = mini_notify.make_notify({
  ERROR = { duration = 5000 },
  WARN = { duration = 3000 },
  INFO = { duration = 3000 },
})

-- TODO: there should be a way to persist the conversation to a sqlite db or json file
--       need to figure out a writing strategy that won't hang the editor
--       potentially as an after-effect after a completion is done.
--       the record would be updaetd every time a new generation is made to account for
--       changes in the prompts.

-- modules
local M = {}
local util = {}

-- state
local config = {}
local active_job = nil
local group = vim.api.nvim_create_augroup('Droid_AutoGroup', { clear = true })
local droid_buffer_counter = 0
local droid_buffers = {} -- track active droid buffers

--- @type table<string, fun(args: string): string, string>
local context_providers = {}

-- >>>public api

M.available_models = {
  "openai/gpt-4.1",
  "openai/o4-mini-high",
  "anthropic/claude-sonnet-4",
  "anthropic/claude-3.5-sonnet-20240620",
  "google/gemini-2.5-pro-preview",
  "google/gemini-2.5-flash-preview-05-20:thinking",
  "x-ai/grok-3-mini-beta",
}

--- @class Droid.Opts
--- @field base_url string?
--- @field api_key_name string
--- @field edit_prompt string?
--- @field help_prompt string?
--- @field default_model string?
--- @field available_models string[]?

--- setup function to initialize the plugin
--- @param opts Droid.Opts?
function M.setup(opts)
  local defaults = {
    base_url = "https://openrouter.ai/api/v1",
    edit_prompt =
    "You should replace the code that you are sent, only following the comments. Do not talk at all. Only output valid code. Do not provide any backticks that surround the code. Never ever output backticks like this ```. Any comment that is asking you for something should be removed after you satisfy them. Other comments should left alone. Do not output backticks",
    help_prompt =
    "you are a helpful assistant. you're working with me in neovim. i'll send you contents of the buffer(s) im working in along with notes, questions or comments. you are very curt, yet helpful and a bit sarcastic.",
    default_model = M.available_models[1],
    available_models = M.available_models,
    api_key_name = "OPENROUTER_API_KEY", -- must be provided
  }

  config = vim.tbl_deep_extend("force", defaults, opts or {})

  if not (type(config.api_key_name) == "string" and config.api_key_name ~= "") then
    error("api_key_name must be provided in droid.setup()")
  end

  -- load persisted model if available, otherwise use default
  local persisted_model = util.load_persisted_model()
  if persisted_model and vim.tbl_contains(config.available_models, persisted_model) then
    config.current_model = persisted_model
  else
    config.current_model = config.default_model
  end
end

--- @return string
function M.get_current_model()
  return config.current_model or config.default_model
end

---@param model string
function M.set_current_model(model)
  if vim.tbl_contains(config.available_models, model) then
    config.current_model = model
    if not util.save_persisted_model(model) then
      notify("droid: model set but failed to persist", vim.log.levels.WARN)
    end
    notify("droid: using " .. model, vim.log.levels.INFO)
  else
    notify("droid: invalid model " .. model, vim.log.levels.ERROR)
  end
end

function M.cancel_completion()
  if active_job then
    active_job:shutdown()
    notify("droid: streaming cancelled", vim.log.levels.INFO)
    active_job = nil
  end
end

function M.help_completion()
  if not config.api_key_name then
    error("droid.setup() must be called before using completions")
  end
  util.invoke_llm_and_stream_into_editor("help")
end

function M.edit_completion()
  if not config.api_key_name then
    error("droid.setup() must be called before using completions")
  end
  util.invoke_llm_and_stream_into_editor("edit")
end

function M.select_model()
  if not config.api_key_name then
    error("droid.setup() must be called before using completions")
  end

  local entries = vim.tbl_map(function(model)
    local prefix = (model == config.current_model) and "● " or "  "
    return {
      display = prefix .. model,
      model = model,
      ordinal = model, -- search key
    }
  end, config.available_models)

  pickers.new({}, {
    prompt_title = "select model (current: " .. config.current_model .. ")",
    finder = finders.new_table {
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.ordinal,
        }
      end
    },
    sorter = conf.generic_sorter({}),
    previewer = false,
    layout_strategy = "cursor",
    layout_config = {
      cursor = {
        height = math.min(#config.available_models + 2, 15),
        width = 60,
      }
    },
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection and selection.value then
          M.set_current_model(selection.value.model)
        end
      end)
      return true
    end,
  }):find()
end

function M.jump_to_new()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- add some spacing if buffer isn't empty
  if #lines > 0 and lines[#lines] ~= "" then
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "", "", "---", "", "" })
  end

  -- move cursor to end
  local last_line = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(0, { last_line, 0 })
end

--- creates a new dedicated droid buffer for llm conversations
--- @return number buffer id of the created buffer
function M.create_droid_buffer()
  droid_buffer_counter = droid_buffer_counter + 1
  local buffer_name = "droid://chat-" .. droid_buffer_counter

  -- create new buffer (unlisted to hide from regular buffer list)
  local buf = vim.api.nvim_create_buf(false, false) -- listed=false, scratch=false
  vim.api.nvim_buf_set_name(buf, buffer_name)

  -- set buffer options for markdown and better chat experience
  vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  vim.api.nvim_buf_set_option(buf, 'wrap', true)
  vim.api.nvim_buf_set_option(buf, 'linebreak', true)
  vim.api.nvim_buf_set_option(buf, 'conceallevel', 2)
  vim.api.nvim_buf_set_option(buf, 'concealcursor', 'nc')

  -- add initial content template
  local initial_content = {
    "# Droid Chat " .. droid_buffer_counter,
    "",
    "Welcome to your dedicated LLM chat buffer! Start typing your message below.",
    "",
    "---",
    "",
    ""
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_content)

  -- track the buffer
  droid_buffers[buf] = {
    id = droid_buffer_counter,
    name = buffer_name,
    created = os.time(),
    model = config.current_model
  }

  -- set up autocommand to clean up when buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf,
    callback = function()
      droid_buffers[buf] = nil
    end,
    group = group
  })

  -- switch to the new buffer in current window
  vim.api.nvim_set_current_buf(buf)

  -- position cursor at end
  local last_line = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(0, { last_line, 0 })

  notify("droid: created new chat buffer " .. buffer_name, vim.log.levels.INFO)
  return buf
end

--- lists all active droid buffers
--- @return table list of droid buffer info
function M.list_droid_buffers()
  local active_buffers = {}
  for buf_id, info in pairs(droid_buffers) do
    if vim.api.nvim_buf_is_valid(buf_id) then
      table.insert(active_buffers, {
        buffer = buf_id,
        id = info.id,
        name = info.name,
        created = info.created,
        model = info.model
      })
    else
      -- cleanup invalid buffers
      droid_buffers[buf_id] = nil
    end
  end
  return active_buffers
end

--- checks if a buffer is a droid buffer
--- @param buf_id number? buffer id (defaults to current buffer)
--- @return boolean
function M.is_droid_buffer(buf_id)
  buf_id = buf_id or vim.api.nvim_get_current_buf()
  return droid_buffers[buf_id] ~= nil
end

--- creates a telescope picker for droid chat buffers
function M.pick_droid_buffer()
  if not config.api_key_name then
    error("droid.setup() must be called before using completions")
  end

  local active_buffers = M.list_droid_buffers()

  if #active_buffers == 0 then
    notify("droid: no active chat buffers", vim.log.levels.INFO)
    return
  end

  -- prepare entries for telescope
  local entries = vim.tbl_map(function(buf_info)
    local time_str = os.date("%H:%M", buf_info.created)
    return {
      display = string.format("Chat %d • %s • %s", buf_info.id, buf_info.model, time_str),
      buffer = buf_info.buffer,
      id = buf_info.id,
      name = buf_info.name,
      model = buf_info.model,
      created = buf_info.created,
      ordinal = string.format("chat %d %s %s", buf_info.id, buf_info.model, buf_info.name)
    }
  end, active_buffers)

  pickers.new({}, {
    prompt_title = "Droid Chat Buffers",
    finder = finders.new_table {
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.ordinal,
          buffer = entry.buffer
        }
      end
    },
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      title = "Chat Preview",
      define_preview = function(self, entry, status)
        -- preview the buffer content
        if entry.buffer and vim.api.nvim_buf_is_valid(entry.buffer) then
          local lines = vim.api.nvim_buf_get_lines(entry.buffer, 0, -1, false)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          -- set markdown filetype for syntax highlighting in preview
          vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', 'markdown')
        end
      end
    }),
    layout_strategy = "horizontal",
    layout_config = {
      horizontal = {
        width = 0.9,
        height = 0.8,
        preview_width = 0.6,
      }
    },
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection and selection.buffer then
          -- switch to the selected droid buffer
          vim.api.nvim_set_current_buf(selection.buffer)
          -- position cursor at end
          local last_line = vim.api.nvim_buf_line_count(selection.buffer)
          vim.api.nvim_win_set_cursor(0, { last_line, 0 })
        end
      end)

      -- add mapping to delete buffer
      map('i', '<C-d>', function()
        local selection = action_state.get_selected_entry()
        if selection and selection.buffer then
          vim.api.nvim_buf_delete(selection.buffer, { force = true })
          -- refresh the picker
          actions.close(prompt_bufnr)
          M.pick_droid_buffer()
        end
      end)

      return true
    end,
  }):find()
end

--- registers a custom context provider
--- @param name string the provider name (used in @name:args syntax)
--- @param handler fun(args: string): string, string function that takes args and returns content, error
function M.register_context_provider(name, handler)
  if type(name) ~= "string" or type(handler) ~= "function" then
    error("register_context_provider requires string name and function handler")
  end
  context_providers[name] = handler
  notify("droid: registered context provider '" .. name .. "'", vim.log.levels.INFO)
end

-- >>>utilities

--- gets the path to the model persistence file
--- @return string
function util.get_persistence_file_path()
  local data_dir = vim.fn.stdpath('data')
  local droid_dir = data_dir .. '/droid'
  return droid_dir .. '/model.json'
end

--- saves the current model to persistence file
--- @param model string
--- @return boolean success
function util.save_persisted_model(model)
  local file_path = util.get_persistence_file_path()
  local dir_path = vim.fn.fnamemodify(file_path, ':h')

  -- ensure directory exists
  if vim.fn.isdirectory(dir_path) == 0 then
    vim.fn.mkdir(dir_path, 'p')
  end

  local data = { current_model = model }
  local json_str = vim.json.encode(data)

  local file = io.open(file_path, 'w')
  if not file then
    return false
  end

  file:write(json_str)
  file:close()
  return true
end

--- loads the persisted model from file
--- @return string? model name if found
function util.load_persisted_model()
  local file_path = util.get_persistence_file_path()
  local file = io.open(file_path, 'r')

  if not file then
    return nil
  end

  local content = file:read('*all')
  file:close()

  if not content or content == '' then
    return nil
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok or not data or not data.current_model then
    return nil
  end

  return data.current_model
end

--- retrieves an api key from environment variables
--- @param name string
--- @return string?
function util.get_api_key(name)
  return os.getenv(name)
end

--- utility function to resolve file paths relative to git root or cwd
--- @param path string the file path to resolve
--- @return string? resolved absolute path
--- @return string? error message if resolution fails
function util.resolve_file_path(path)
  -- handle absolute paths
  if path:match("^/") then
    if vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1 then
      return path, nil
    else
      return nil, "file or directory not found: " .. path
    end
  end

  -- try relative to current working directory first
  local cwd_path = vim.fn.getcwd() .. "/" .. path
  if vim.fn.filereadable(cwd_path) == 1 or vim.fn.isdirectory(cwd_path) == 1 then
    return cwd_path, nil
  end

  -- try relative to git root if in a git repository
  local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n$", "")
  if vim.v.shell_error == 0 and git_root ~= "" then
    local git_path = git_root .. "/" .. path
    if vim.fn.filereadable(git_path) == 1 or vim.fn.isdirectory(git_path) == 1 then
      return git_path, nil
    end
  end

  return nil, "file or directory not found: " .. path
end

-- >>>context injection

--- @class ContextReference
--- @field reference string the complete @reference match (e.g., "@filename", "@file:1:10")

--- parses context references from text, extracting all @reference patterns
--- @param text string the text to parse for context references
--- @return ContextReference[] array of context reference objects
function util.parse_context_references(text)
  local references = {}

  -- pattern to match @references (handles various syntaxes)
  -- supports: @filename, @dir/, @file:10:20, @def:symbol, @!`cmd args`
  local patterns = {
    -- @!`cmd args` (backtick syntax for shell commands)
    "(@!`[^`]+`)",
    -- @command:args (colon syntax for LSP and other commands)
    "(@%w+:[^%s]+)",
    -- @path/file:line:range (file with line ranges)
    "(@[^%s:]+:%d+[:%d%-+]*)",
    -- @file or @dir/ (simple file/directory references, excluding @! which needs backticks)
    "(@[^%s:`!]+/?)"
  }

  for _, pattern in ipairs(patterns) do
    for match in text:gmatch(pattern) do
      table.insert(references, {
        reference = match
      })
    end
  end

  return references
end

--- resolves a single context reference and returns formatted content
--- @param reference string the reference to resolve (e.g., "@filename", "@def:symbol", "@!`ls -la`")
--- @return string? resolved content
--- @return string? error message if resolution fails
function util.resolve_context_reference(reference)
  -- remove @ prefix for processing
  local ref_content = reference:sub(2)

  -- handle shell command syntax: @!`cmd args`
  local shell_cmd = ref_content:match("^!`(.+)`$")
  if shell_cmd then
    -- execute shell command and capture output
    local output = vim.fn.system(shell_cmd)
    local exit_code = vim.v.shell_error

    if exit_code ~= 0 then
      return nil, string.format("shell command failed (exit code %d): %s", exit_code, shell_cmd)
    end

    -- remove trailing newline if present
    output = output:gsub("\n$", "")

    return string.format("--- SHELL: %s ---\n%s\n--- END SHELL ---", shell_cmd, output), nil
  end

  -- handle custom context providers and LSP commands: @def:symbol, @func:name, @ref:symbol, @diagnostics
  local provider_name, provider_arg = ref_content:match("^(%w+):(.+)$")
  if provider_name then
    -- check if we have a custom provider for this
    if context_providers[provider_name] then
      local content, err = context_providers[provider_name](provider_arg)
      if content then
        return string.format("--- %s: %s ---\n%s\n--- END %s ---",
          provider_name:upper(), provider_arg, content, provider_name:upper()), nil
      else
        return nil, err or ("provider " .. provider_name .. " failed")
      end
    end

    -- handle built-in LSP commands
    if provider_name == "def" or provider_name == "func" or provider_name == "ref" then
      return nil, "LSP integration not yet implemented"
    elseif provider_name == "diagnostics" then
      return nil, "diagnostics integration not yet implemented"
    else
      return nil, "unknown context provider: " .. provider_name
    end
  end

  -- handle git commands: @diff, @tree
  if ref_content == "diff" then
    return nil, "git diff integration not yet implemented"
  elseif ref_content == "tree" then
    return nil, "git tree integration not yet implemented"
  end

  -- handle file references with optional line ranges
  local file_path, line_start, line_end = ref_content:match("^([^:]+):(%d+):(.+)$")
  if file_path then
    local resolved_path, err = util.resolve_file_path(file_path)
    if not resolved_path then
      return nil, err
    end

    -- parse line range
    local start_num = tonumber(line_start)
    local end_num = nil

    if line_end == "-1" then
      end_num = -1 -- end of file
    elseif line_end:match("^%+(%d+)$") then
      local offset = tonumber(line_end:match("^%+(%d+)$"))
      end_num = start_num + offset - 1
    elseif line_end:match("^%-(%d+)$") then
      -- negative line number from end
      return nil, "negative line numbers not yet implemented"
    else
      end_num = tonumber(line_end)
    end

    if not start_num or not end_num then
      return nil, "invalid line range format"
    end

    -- read file content with line range
    local lines = {}
    local file = io.open(resolved_path, 'r')
    if not file then
      return nil, "cannot read file: " .. resolved_path
    end

    local line_num = 1
    for line in file:lines() do
      if line_num >= start_num and (end_num == -1 or line_num <= end_num) then
        table.insert(lines, line)
      elseif line_num > end_num and end_num ~= -1 then
        break
      end
      line_num = line_num + 1
    end
    file:close()

    local content = table.concat(lines, '\n')
    return string.format("--- FILE: %s (%d-%s) ---\n%s\n--- END FILE ---",
      file_path, start_num, end_num == -1 and "EOF" or tostring(end_num), content), nil
  end

  -- handle simple file/directory references
  local resolved_path, err = util.resolve_file_path(ref_content)
  if not resolved_path then
    return nil, err
  end

  -- check if it's a directory (ends with / or is actually a directory)
  if ref_content:match("/$") or vim.fn.isdirectory(resolved_path) == 1 then
    return nil, "directory listing not yet implemented"
  end

  -- read entire file
  local file = io.open(resolved_path, 'r')
  if not file then
    return nil, "cannot read file: " .. resolved_path
  end

  local content = file:read('*all')
  file:close()

  if not content then
    return nil, "file is empty or unreadable: " .. resolved_path
  end

  return string.format("--- FILE: %s ---\n%s\n--- END FILE ---", ref_content, content), nil
end

--- processes a message content string and resolves all context references
--- @param content string the message content to process
--- @return string processed content with resolved references
--- @return string[] array of any error messages encountered
function util.process_context_references(content)
  local references = util.parse_context_references(content)
  local processed_content = content
  local errors = {}

  -- process references in reverse order to maintain string positions
  for i = #references, 1, -1 do
    local ref = references[i]
    local resolved_content, err = util.resolve_context_reference(ref.reference)

    if resolved_content then
      -- replace the reference with resolved content
      processed_content = processed_content:gsub(vim.pesc(ref.reference), resolved_content, 1)
    else
      -- collect error for reporting
      table.insert(errors, string.format("Failed to resolve %s: %s", ref.reference, err or "unknown error"))
    end
  end

  return processed_content, errors
end

-- >>>completions

--- @class Message
--- @field role "user"|"assistant"
--- @field content string
--- @field model string? only for assistant messages

--- writes a string at the current cursor position in the buffer
--- @param str string
--- @return nil
function util.write_string_at_cursor(str)
  -- vim.schedule ensures this runs on the main event loop (thread-safe for async operations)
  vim.schedule(function()
    local current_window = vim.api.nvim_get_current_win()
    local cursor_position = vim.api.nvim_win_get_cursor(current_window)
    local row, col = cursor_position[1], cursor_position[2]

    -- split incoming text into lines for proper insertion
    local lines = vim.split(str, '\n')
    -- nvim_put: 'c' = character-wise, true = after cursor, true = follow cursor
    vim.api.nvim_put(lines, 'c', true, true)

    -- calculate new cursor position after text insertion
    local num_lines = #lines
    local last_line_length = #lines[num_lines]
    vim.api.nvim_win_set_cursor(current_window, { row + num_lines - 1, col + last_line_length })
  end)
end

--- extracts the currently selected text in visual mode
--- @return table? Array selected lines
function util.get_visual_selection()
  -- get selection start ('v') and end ('.') positions
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')

  -- line-wise visual mode (V): select entire lines
  if vim.fn.mode() == 'V' then
    if srow > erow then
      return vim.api.nvim_buf_get_lines(0, erow - 1, srow, true)
    else
      return vim.api.nvim_buf_get_lines(0, srow - 1, erow, true)
    end
  end

  -- character-wise visual mode (v): select partial text within/across lines
  if vim.fn.mode() == 'v' then
    if srow < erow or (srow == erow and scol <= ecol) then
      return vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
    else
      return vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
    end
  end

  -- block-wise visual mode (ctrl-v): select rectangular text blocks
  if vim.fn.mode() == '\22' then
    local lines = {}
    -- normalize selection boundaries
    if srow > erow then
      srow, erow = erow, srow
    end
    if scol > ecol then
      scol, ecol = ecol, scol
    end
    -- extract text from each row within the column range
    for i = srow, erow do
      table.insert(lines,
        vim.api.nvim_buf_get_text(0, i - 1, math.min(scol - 1, ecol), i - 1, math.max(scol - 1, ecol), {})[1])
    end
    return lines
  end
end

--- parse conversation from buffer lines
--- @param lines string[]
--- @return Message[]?
--- @return string? error
function util.parse_conversation(lines)
  local messages = {}
  local current_content = {}
  local in_assistant_block = false
  local assistant_model = nil
  local last_was_assistant = false

  local assistant_begin_pattern = "^=== ASSISTANT BEGIN %[(.-)%] ===$"
  local assistant_end_pattern = "^=== ASSISTANT END %[(.-)%] ===$"

  for i, line in ipairs(lines) do
    local begin_model = line:match(assistant_begin_pattern)
    local end_model = line:match(assistant_end_pattern)

    if begin_model then
      -- store pending user message
      if #current_content > 0 then
        local content = table.concat(current_content, '\n'):gsub("^%s*(.-)%s*$", "%1")
        if content ~= "" then
          table.insert(messages, { role = "user", content = content })
          last_was_assistant = false
        end
        current_content = {}
      end

      in_assistant_block = true
      assistant_model = begin_model
    elseif end_model then
      -- extract just the model name from end marker (ignore usage stats)
      local end_model_name = end_model:match("^([^|]+)") or end_model
      end_model_name = end_model_name:gsub("%s+$", "") -- trim trailing spaces

      if not in_assistant_block or end_model_name ~= assistant_model then
        return nil, "malformed conversation: mismatched assistant markers at line " .. i
      end

      -- store assistant message
      local content = table.concat(current_content, '\n'):gsub("^%s*(.-)%s*$", "%1")
      if content == "" and last_was_assistant then
        return nil, "malformed conversation: consecutive assistant messages without user input"
      end

      table.insert(messages, {
        role = "assistant", content = content, model = assistant_model
      })

      in_assistant_block = false
      assistant_model = nil
      current_content = {}
      last_was_assistant = true
    else
      table.insert(current_content, line)
    end
  end

  -- hanlde remaining content
  if in_assistant_block then
    return nil, "malformed conversation: unclosed assistant block"
  end

  if #current_content > 0 then
    local content = table.concat(current_content, '\n'):gsub("^%s*(.-)%s*$", "%1")
    if content ~= "" then
      table.insert(messages, { role = "user", content = content })
    end
  end

  -- validate we don't end with empty user message
  if #messages > 0 and messages[#messages].role == "user" and messages[#messages].content == "" then
    table.remove(messages)
  end

  return messages, nil
end

--- extracts the prompt text from visual selection or text until cursor
--- @param mode "edit"|"help"
--- @return Message[]?
--- @return string? error
local function get_conversation_context(mode)
  local visual_lines = util.get_visual_selection()
  local lines

  if visual_lines then
    -- in visual mode, only use selected text as latest userr message
    local content = table.concat(visual_lines, '\n')
    if mode == "edit" then
      -- delete selected text if we're in edit mode (llm will overwrite selection)
      vim.api.nvim_command 'normal! d'
      vim.api.nvim_command 'normal! k'
    else
      -- exit visual mode without modifying selection (llm appends after selection)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
    end
    return { { role = "user", content = content } }, nil
  else
    -- parse entire buffer up to cursor for conversation history
    local current_buffer = vim.api.nvim_get_current_buf()
    local current_window = vim.api.nvim_get_current_win()
    local cursor_position = vim.api.nvim_win_get_cursor(current_window)
    local row = cursor_position[1]
    lines = vim.api.nvim_buf_get_lines(current_buffer, 0, row, true)
  end

  local messages, err = util.parse_conversation(lines)
  if err or messages == nil then
    return nil, err
  end

  -- ensure we have at least one user message
  if #messages == 0 or messages[#messages].role ~= "user" then
    -- if no proper conversation structure, treat all content as a single user message
    local content = table.concat(lines, '\n'):gsub("^%s*(.-)%s*$", "%1")
    if content ~= "" then
      return { { role = "user", content = content } }, nil
    else
      return nil, "No content to send"
    end
  end

  return messages, nil
end

--- creates curl arguments for anthropic api requests
--- @param mode "edit"|"help"
--- @param prompt string
--- @return string[] Array curl command arguments
function util.make_anthropic_spec_curl_args(mode, prompt)
  local base_url = config.base_url .. "/chat/completions"
  local api_key = config.api_key_name and util.get_api_key(config.api_key_name)
  local data = {
    system = mode == "edit" and config.edit_prompt or config.help_prompt,
    messages = { { role = 'user', content = prompt } },
    model = config.current_model,
    stream = true,
    max_tokens = 4096,
  }
  local args = { '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
  if api_key then
    table.insert(args, '-H')
    table.insert(args, 'x-api-key: ' .. api_key)
    table.insert(args, '-H')
    table.insert(args, 'anthropic-version: 2023-06-01')
  end
  table.insert(args, base_url)
  return args
end

--- creates curl arguments for openai-compatible api requests
--- @param mode "edit"|"help"
--- @param messages Message[]
--- @return string[] Array curl command arguments
function util.make_openai_spec_curl_args(mode, messages)
  local base_url = config.base_url .. "/chat/completions"
  local api_key = config.api_key_name and util.get_api_key(config.api_key_name)

  local convhist = {
    { role = 'system', content = mode == "edit" and config.edit_prompt or config.help_prompt }
  }

  for _, msg in ipairs(messages) do
    table.insert(convhist, { role = msg.role, content = msg.content })
  end

  local data = {
    messages = convhist,
    model = config.current_model,
    temperature = 0.7,
    stream = true,
  }

  local args = { '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', vim.json.encode(data) }
  if api_key then
    table.insert(args, '-H')
    table.insert(args, 'Authorization: Bearer ' .. api_key)
  end
  table.insert(args, base_url)
  return args
end

--- handles streaming response data from anthropic api
--- @param data_stream string the json data from the stream
--- @param event_state string? the current sse event type
--- @param usage_stats_ref table? reference to store usage stats
--- @return nil
function util.handle_anthropic_spec_data(data_stream, event_state, usage_stats_ref)
  if event_state == 'content_block_delta' then
    local json = vim.json.decode(data_stream)

    -- capture usage stats from final chunk
    if json.usage and usage_stats_ref then
      usage_stats_ref.usage = json.usage
    end

    if json.delta and json.delta.text then
      util.write_string_at_cursor(json.delta.text)
    end
  end
end

--- handles streaming response data from openai-compatible apis
--- @param data_stream string the json data from the stream
--- @param usage_stats_ref table? reference to store usage stats
--- @return nil
function util.handle_openai_spec_data(data_stream, usage_stats_ref)
  if data_stream:match '"delta":' then
    local json = vim.json.decode(data_stream)

    -- capture usage stats from final chunk
    if json.usage and usage_stats_ref then
      usage_stats_ref.usage = json.usage
    end

    if json.choices and json.choices[1] and json.choices[1].delta then
      local content = json.choices[1].delta.content
      if content then
        util.write_string_at_cursor(content)
      end
    end
  end
end

--- formats usage stats from streaming response for display
--- @param usage table the usage object from streaming response
--- @return string formatted stats string
local function format_usage_stats(usage)
  local parts = {}
  if usage.prompt_tokens then
    table.insert(parts, "P: " .. usage.prompt_tokens .. " toks")
  end
  if usage.completion_tokens then
    table.insert(parts, "C: " .. usage.completion_tokens .. " toks")
  end
  return table.concat(parts, " | ")
end

--- invokes an llm api and streams the response directly into the editor
--- @param mode "edit"|"help"
--- @return table? active job instance
function util.invoke_llm_and_stream_into_editor(mode)
  vim.api.nvim_clear_autocmds { group = group }

  local messages, err = get_conversation_context(mode)
  if err then
    notify("droid: " .. err, vim.log.levels.ERROR)
    return nil
  end

  -- process context references in all messages
  local processed_messages = {}
  local all_errors = {}

  if messages then
    for _, message in ipairs(messages) do
      local processed_content, errors = util.process_context_references(message.content)

      -- collect any errors from context resolution
      for _, error_msg in ipairs(errors) do
        table.insert(all_errors, error_msg)
      end

      -- add processed message
      table.insert(processed_messages, {
        role = message.role,
        content = processed_content,
        model = message.model
      })
    end
  end

  -- notify user of any context resolution errors
  if #all_errors > 0 then
    for _, error_msg in ipairs(all_errors) do
      notify("droid: " .. error_msg, vim.log.levels.WARN)
    end
  end

  local args = util.make_openai_spec_curl_args(mode, processed_messages)
  local curr_event_state = nil

  -- track assistant markers and usage stats
  local first_output = true
  local usage_stats_ref = {}
  local marker_prefix = "\n\n=== ASSISTANT BEGIN [" .. config.current_model .. "] ===\n"

  -- parse server-sent events (sse) format: "event: type\ndata: json"
  local function parse_and_call(line)
    local event = line:match '^event: (.+)$'
    if event then
      curr_event_state = event
      return
    end
    local data_match = line:match '^data: (.+)$'
    if data_match then
      -- add opening marker on first content
      if first_output and data_match:match '"delta":' then
        local json = vim.json.decode(data_match)
        if mode == "help" and json.choices and json.choices[1] and json.choices[1].delta and json.choices[1].delta.content then
          util.write_string_at_cursor(marker_prefix)
          first_output = false
        end
      end
      util.handle_openai_spec_data(data_match, usage_stats_ref)
      -- util.handle_anthropic_spec_data(data_match, curr_event_state, usage_stats_ref)
    end
  end

  -- cancel any existing job before starting new one
  if active_job then
    active_job:shutdown()
    active_job = nil
  end

  -- plenary.job provides async process management for long-running curl streams
  active_job = Job:new {
    command = 'curl',
    args = args,
    on_stdout = function(_, out)
      parse_and_call(out)
    end,
    on_stderr = function(_, errdata)
      notify("droid: api error - " .. errdata, vim.log.levels.DEBUG)
    end,
    on_exit = function(_, return_val)
      if mode == "help" and return_val == 0 and not first_output then
        -- add closing marker with usage stats if available
        vim.schedule(function()
          local stats_text = ""
          if usage_stats_ref.usage then
            local formatted_stats = format_usage_stats(usage_stats_ref.usage)
            if formatted_stats ~= "" then
              stats_text = " | " .. formatted_stats
            end
          end
          local final_marker = "\n=== ASSISTANT END [" .. config.current_model .. stats_text .. "] ==="
          util.write_string_at_cursor(final_marker)
        end)
      end
      active_job = nil
    end,
  }

  notify("droid: generating " .. mode .. " completion", vim.log.levels.INFO)
  active_job:start()
  return active_job
end

return M
