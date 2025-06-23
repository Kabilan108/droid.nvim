--- providers.lua
--- this file contains the default context providers available in droid.nvim

local M = {}

--- @return boolean
local function is_in_git_repo()
  vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null")
  return vim.v.shell_error == 0
end

--- get active lsp clients for current buffer
--- @return table?, string?
local function get_lsp_clients()
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_active_clients({ bufnr = bufnr })

  if #clients == 0 then
    return nil, "no active lsp clients for current buffer"
  end

  return clients, nil
end

--- find symbol position in buffer using proper word boundary matching
--- @param symbol_name string
--- @param bufnr number
--- @return table?, string?
local function find_symbol_position(symbol_name, bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Use word boundary pattern to find exact symbol matches
  local pattern = "\\b" .. vim.pesc(symbol_name) .. "\\b"

  for i, line in ipairs(lines) do
    local col = line:find(pattern)
    if col then
      return { line = i - 1, character = col - 1 }, nil -- 0-based indexing for LSP
    end
  end

  return nil, string.format("symbol '%s' not found in current buffer", symbol_name)
end

--- make lsp request with timeout and proper error handling
--- @param method string
--- @param params table
--- @param timeout number
--- @return any?, string?
local function make_lsp_request(method, params, timeout)
  local bufnr = vim.api.nvim_get_current_buf()
  local result = nil
  local error_msg = nil
  local completed = false

  vim.lsp.buf_request(bufnr, method, params, function(err, response, _, _)
    if err then
      error_msg = string.format("lsp error: %s", err.message or tostring(err))
    else
      result = response
    end
    completed = true
  end)

  -- wait for completion with timeout
  local start_time = vim.loop.now()

  while not completed and (vim.loop.now() - start_time) < timeout do
    vim.wait(100)
  end

  if not completed then
    return nil, "lsp request timed out"
  end

  if error_msg then
    return nil, error_msg
  end

  return result, nil
end

--- @type table<string, ContextProvider>
M.builtin = {}

M.builtin["diagnostics"] = {
  description = "provides lsp diagnostics for the current or a specified buffer.",
  handler = function(ref)
    local bufnr

    if ref.path then
      bufnr = vim.fn.bufnr(ref.path, false)
      if bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
        return nil, "buffer not loaded. open the file to get diagnostics."
      end
    else
      bufnr = vim.api.nvim_get_current_buf()
    end

    local diagnostics = vim.diagnostic.get(bufnr)

    if not diagnostics or #diagnostics == 0 then
      return "no diagnostics available", nil
    end

    if ref.start_line and ref.end_line then
      if ref.start_line < 1 or ref.end_line < 1 then
        return nil, "invalid line range"
      end
      diagnostics = vim.tbl_filter(function(d)
        return (d.lnum + 1) >= ref.start_line and (d.lnum + 1) <= ref.end_line
      end, diagnostics)
    end

    if #diagnostics == 0 then
      return "no diagnostics found in the specified range", nil
    end

    local lines = { string.format("diagnostics for buffer %d (%s):", bufnr, vim.api.nvim_buf_get_name(bufnr)) }
    local sevmap = { "error", "warn", "info", "hint" }

    for _, d in ipairs(diagnostics) do
      local sevstr = sevmap[d.severity] or "unknown"
      table.insert(lines, string.format(
        "- [%s] L%d:%d: %s (%s)",
        sevstr:upper(),
        d.lnum + 1, -- lnum is 0-indexed
        d.col + 1,  -- col is 0-indexed
        d.message:gsub("\n", " "),
        d.source or "lsp"
      ))
    end

    return table.concat(lines, "\n"), nil
  end
}

M.builtin["def"] = {
  description = "gets the lsp definition for a symbol in the current buffer.",
  handler = function(ref)
    -- Validate LSP clients
    local clients, err = get_lsp_clients()
    if not clients then
      return nil, err
    end

    -- Extract symbol name from ref.path (format: symbol_name)
    if not ref.path or ref.path == "" then
      return nil, "no symbol name provided. use syntax: #def:symbol_name"
    end

    local symbol_name = ref.path
    local bufnr = vim.api.nvim_get_current_buf()

    if not symbol_name then
      return nil, "no symbol name provided. use syntax: #def:symbol_name"
    end

    -- Find symbol position without moving cursor
    local pos, find_err = find_symbol_position(symbol_name, bufnr)
    if not pos then
      return nil, find_err
    end

    -- Create LSP position params programmatically
    local params = {
      textDocument = vim.lsp.util.make_text_document_params(),
      position = pos
    }

    -- Make LSP request
    local definitions, lsp_err = make_lsp_request('textDocument/definition', params, 5000)
    if not definitions then
      return nil, lsp_err
    end

    if not definitions or (vim.tbl_islist(definitions) and #definitions == 0) then
      return nil, string.format("no definition found for symbol '%s'", symbol_name)
    end

    -- Handle single definition or first definition from list
    local def = vim.tbl_islist(definitions) and definitions[1] or definitions

    if not def.uri then
      return nil, "definition response missing uri information"
    end

    local file_path = vim.uri_to_fname(def.uri)
    local start_line = def.range.start.line + 1 -- convert to 1-based
    local start_col = def.range.start.character + 1

    -- Read the file content
    local success, file_lines = pcall(vim.fn.readfile, file_path)
    if not success then
      return nil, string.format("failed to read definition file: %s", file_path)
    end

    -- Extract a snippet around the definition (5 lines before and after)
    local context_start = math.max(1, start_line - 5)
    local context_end = math.min(#file_lines, start_line + 5)
    local snippet_lines = {}

    for i = context_start, context_end do
      local prefix = (i == start_line) and ">>> " or "    "
      table.insert(snippet_lines, string.format("%s%d: %s", prefix, i, file_lines[i] or ""))
    end

    local result = string.format(
      "definition for '%s':\nfile: %s\nline: %d, column: %d\n\n%s",
      symbol_name,
      file_path,
      start_line,
      start_col,
      table.concat(snippet_lines, "\n")
    )

    return result, nil
  end
}

M.builtin["ref"] = {
  description = "gets all lsp references for a symbol in the current buffer.",
  handler = function(ref)
    -- Validate LSP clients
    local clients, err = get_lsp_clients()
    if not clients then
      return nil, err
    end

    -- Extract symbol name from ref.path (format: symbol_name)
    if not ref.path or ref.path == "" then
      return nil, "no symbol name provided. use syntax: #ref:symbol_name"
    end

    local symbol_name = ref.path
    local bufnr = vim.api.nvim_get_current_buf()

    if not symbol_name then
      return nil, "no symbol name provided. use syntax: #ref:symbol_name"
    end

    -- Find symbol position without moving cursor
    local pos, find_err = find_symbol_position(symbol_name, bufnr)
    if not pos then
      return nil, find_err
    end

    -- Create LSP position params programmatically
    local params = {
      textDocument = vim.lsp.util.make_text_document_params(),
      position = pos,
      context = { includeDeclaration = true }
    }

    -- Make LSP request
    local references, lsp_err = make_lsp_request('textDocument/references', params, 5000)
    if not references then
      return nil, lsp_err
    end

    if not references or #references == 0 then
      return nil, string.format("no references found for symbol '%s'", symbol_name)
    end

    local lines = { string.format("references for '%s' (%d found):", symbol_name, #references) }

    for i, ref_item in ipairs(references) do
      if ref_item.uri then
        local file_path = vim.uri_to_fname(ref_item.uri)
        local line_num = ref_item.range.start.line + 1 -- convert to 1-based
        local col_num = ref_item.range.start.character + 1

        -- Get relative path if possible for cleaner display
        local display_path = file_path
        local cwd = vim.fn.getcwd()
        if file_path:sub(1, #cwd) == cwd then
          display_path = file_path:sub(#cwd + 2) -- remove cwd and leading /
        end

        table.insert(lines, string.format("  %d. %s:%d:%d", i, display_path, line_num, col_num))
      end
    end

    return table.concat(lines, "\n"), nil
  end
}

M.builtin["diff"] = {
  description = "gets the output of `git diff` for the current repository, optionally scoped to a path.",
  handler = function(ref)
    if not is_in_git_repo() then
      return nil, "not in a git repository"
    end

    local cmd = "git diff"
    if ref.path then
      cmd = cmd .. " " .. vim.fn.shellescape(ref.path)
    end

    local output = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      return nil, "git diff command failed"
    end

    if output:match("^%s*$") then
      return "no changes", nil
    end

    return output, nil
  end
}

M.builtin["tree"] = {
  description = "gets the project file tree from `git ls-files`.",
  handler = function(ref)
    if not is_in_git_repo() then
      return nil, "not in a git repository"
    end

    local output = vim.fn.system("git ls-files")
    if vim.v.shell_error ~= 0 then
      return nil, "git ls-files command failed"
    end

    if output == "" or output:match("^%s*$") then
      return "no files tracked by git", nil
    end

    return output, nil
  end
}

M.builtin["harpoon"] = {
  description = "gets the content of files marked in harpoon. specify an index or get all.",
  handler = function(ref)
    local ok, harpoon = pcall(require, 'harpoon')
    if not ok then
      return nil, "harpoon plugin not installed or not available"
    end

    local list = harpoon:list()
    if not list or not list.items or #list.items == 0 then
      return nil, "harpoon list is empty"
    end

    -- check if specific index is requested
    if ref.path and ref.path ~= "" then
      local index = tonumber(ref.path)
      if not index then
        return nil, "invalid harpoon index: " .. ref.path
      end

      if index < 1 or index > #list.items then
        return nil, string.format("harpoon index %d out of range (1-%d)", index, #list.items)
      end

      -- get specific item
      local item = list:get(index)
      if not item or not item.value then
        return nil, string.format("harpoon item at index %d is invalid", index)
      end

      -- read file content
      local file_path = item.value
      local lines, err = vim.fn.readfile(file_path)
      if err or not lines then
        return nil, string.format("failed to read harpoon file: %s", file_path)
      end
      local content = table.concat(lines, "\n")

      return string.format("--- HARPOON [%d]: %s ---\n%s", index, file_path, content), nil
    else
      -- get all items
      local result_lines = {}
      for i, item in ipairs(list.items) do
        if item and item.value then
          local file_path = item.value
          local lines, err = vim.fn.readfile(file_path)
          if not err and lines then
            local content = table.concat(lines, "\n")
            table.insert(result_lines, string.format("--- HARPOON [%d]: %s ---", i, file_path))
            table.insert(result_lines, content)
            table.insert(result_lines, "") -- Empty line separator
          else
            table.insert(result_lines, string.format("--- HARPOON [%d]: %s (failed to read) ---", i, file_path))
            table.insert(result_lines, "") -- Empty line separator
          end
        end
      end

      if #result_lines == 0 then
        return nil, "no valid harpoon files found"
      end

      return table.concat(result_lines, "\n"), nil
    end
  end
}

return M

