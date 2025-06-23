--- providers.lua
--- this file contains the default context providers available in droid.nvim

local M = {}

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
    -- Check if LSP clients are active
    local bufnr = vim.api.nvim_get_current_buf()
    local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
    
    if #clients == 0 then
      return nil, "no active lsp clients for current buffer"
    end

    -- Extract symbol name from ref.text (format: symbol_name)
    if not ref.text or ref.text == "" then
      return nil, "no symbol name provided. use syntax: #def:symbol_name"
    end

    local symbol_name = ref.text

    -- Find the symbol in the buffer
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_pos = nil
    
    for i, line in ipairs(lines) do
      local col = line:find(symbol_name, 1, true) -- plain text search
      if col then
        found_pos = { i - 1, col - 1 } -- convert to 0-based indexing
        break
      end
    end

    if not found_pos then
      return nil, string.format("symbol '%s' not found in current buffer", symbol_name)
    end

    -- Set cursor to symbol position temporarily
    local original_pos = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_win_set_cursor(0, { found_pos[1] + 1, found_pos[2] })

    -- Use a coroutine to handle the async LSP request
    local result = nil
    local error_msg = nil
    local completed = false

    local params = vim.lsp.util.make_position_params()
    
    vim.lsp.buf_request(bufnr, 'textDocument/definition', params, function(err, definitions, _, _)
      if err then
        error_msg = string.format("lsp error: %s", err.message or tostring(err))
      elseif not definitions or (vim.tbl_islist(definitions) and #definitions == 0) then
        error_msg = string.format("no definition found for symbol '%s'", symbol_name)
      else
        -- Handle single definition or first definition from list
        local def = vim.tbl_islist(definitions) and definitions[1] or definitions
        
        if def.uri then
          local file_path = vim.uri_to_fname(def.uri)
          local start_line = def.range.start.line + 1 -- convert to 1-based
          local start_col = def.range.start.character + 1
          
          -- Read the file content
          local success, file_lines = pcall(vim.fn.readfile, file_path)
          if not success then
            error_msg = string.format("failed to read definition file: %s", file_path)
          else
            -- Extract a snippet around the definition (5 lines before and after)
            local context_start = math.max(1, start_line - 5)
            local context_end = math.min(#file_lines, start_line + 5)
            local snippet_lines = {}
            
            for i = context_start, context_end do
              local prefix = (i == start_line) and ">>> " or "    "
              table.insert(snippet_lines, string.format("%s%d: %s", prefix, i, file_lines[i] or ""))
            end
            
            result = string.format(
              "definition for '%s':\nfile: %s\nline: %d, column: %d\n\n%s",
              symbol_name,
              file_path,
              start_line,
              start_col,
              table.concat(snippet_lines, "\n")
            )
          end
        else
          error_msg = "definition response missing uri information"
        end
      end
      completed = true
    end)

    -- Wait for completion with timeout
    local timeout = 5000 -- 5 seconds
    local start_time = vim.loop.now()
    
    while not completed and (vim.loop.now() - start_time) < timeout do
      vim.wait(100)
    end

    -- Restore original cursor position
    vim.api.nvim_win_set_cursor(0, original_pos)

    if not completed then
      return nil, "lsp definition request timed out"
    end

    if error_msg then
      return nil, error_msg
    end

    return result, nil
  end
}

M.builtin["ref"] = {
  description = "gets all lsp references for a symbol in the current buffer.",
  handler = function(ref)
    -- Check if LSP clients are active
    local bufnr = vim.api.nvim_get_current_buf()
    local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
    
    if #clients == 0 then
      return nil, "no active lsp clients for current buffer"
    end

    -- Extract symbol name from ref.text (format: symbol_name)
    if not ref.text or ref.text == "" then
      return nil, "no symbol name provided. use syntax: #ref:symbol_name"
    end

    local symbol_name = ref.text

    -- Find the symbol in the buffer
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_pos = nil
    
    for i, line in ipairs(lines) do
      local col = line:find(symbol_name, 1, true) -- plain text search
      if col then
        found_pos = { i - 1, col - 1 } -- convert to 0-based indexing
        break
      end
    end

    if not found_pos then
      return nil, string.format("symbol '%s' not found in current buffer", symbol_name)
    end

    -- Set cursor to symbol position temporarily
    local original_pos = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_win_set_cursor(0, { found_pos[1] + 1, found_pos[2] })

    -- Use a coroutine to handle the async LSP request
    local result = nil
    local error_msg = nil
    local completed = false

    local params = vim.lsp.util.make_position_params()
    params.context = { includeDeclaration = true }
    
    vim.lsp.buf_request(bufnr, 'textDocument/references', params, function(err, references, _, _)
      if err then
        error_msg = string.format("lsp error: %s", err.message or tostring(err))
      elseif not references or #references == 0 then
        error_msg = string.format("no references found for symbol '%s'", symbol_name)
      else
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
        
        result = table.concat(lines, "\n")
      end
      completed = true
    end)

    -- Wait for completion with timeout
    local timeout = 5000 -- 5 seconds
    local start_time = vim.loop.now()
    
    while not completed and (vim.loop.now() - start_time) < timeout do
      vim.wait(100)
    end

    -- Restore original cursor position
    vim.api.nvim_win_set_cursor(0, original_pos)

    if not completed then
      return nil, "lsp references request timed out"
    end

    if error_msg then
      return nil, error_msg
    end

    return result, nil
  end
}

return M
