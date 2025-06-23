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

M.builtin["harpoon"] = {
  description = "gets the content of files marked in harpoon. specify an index or get all.",
  handler = function(ref)
    -- Safely check if harpoon is available
    local ok, harpoon = pcall(require, 'harpoon')
    if not ok then
      return nil, "harpoon plugin not installed or not available"
    end

    -- Get the harpoon list
    local list = harpoon:list()
    if not list or not list.items or #list.items == 0 then
      return nil, "harpoon list is empty"
    end

    -- Check if specific index is requested
    if ref.path and ref.path ~= "" then
      local index = tonumber(ref.path)
      if not index then
        return nil, "invalid harpoon index: " .. ref.path
      end

      if index < 1 or index > #list.items then
        return nil, string.format("harpoon index %d out of range (1-%d)", index, #list.items)
      end

      -- Get specific item
      local item = list:get(index)
      if not item or not item.value then
        return nil, string.format("harpoon item at index %d is invalid", index)
      end

      -- Read file content
      local file_path = item.value
      local content = vim.fn.system(string.format("cat %s", vim.fn.shellescape(file_path)))
      if vim.v.shell_error ~= 0 then
        return nil, string.format("failed to read harpoon file: %s", file_path)
      end

      return string.format("--- HARPOON [%d]: %s ---\n%s", index, file_path, content), nil
    else
      -- Get all items
      local result_lines = {}
      for i, item in ipairs(list.items) do
        if item and item.value then
          local file_path = item.value
          local content = vim.fn.system(string.format("cat %s", vim.fn.shellescape(file_path)))
          if vim.v.shell_error == 0 then
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
