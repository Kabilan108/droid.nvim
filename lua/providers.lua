--- providers.lua
--- this file contains the default context providers available in droid.nvim

local M = {}

--- @return boolean
local function is_in_git_repo()
  vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null")
  return vim.v.shell_error == 0
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

M.builtin["diff"] = {
  description = "gets the output of `git diff` for the current repository, optionally scoped to a path.",
  handler = function(ref)
    -- Check if we're in a git repository
    if not is_in_git_repo() then
      return nil, "not in a git repository"
    end

    -- Construct git diff command
    local cmd = "git diff"
    if ref.path then
      cmd = cmd .. " " .. vim.fn.shellescape(ref.path)
    end

    -- Execute git diff
    local output = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      return nil, "git diff command failed"
    end

    -- Handle empty diff
    if output:match("^%s*$") then
      return "no changes", nil
    end

    return output, nil
  end
}

M.builtin["tree"] = {
  description = "gets the project file tree from `git ls-files`.",
  handler = function(ref)
    -- Check if we're in a git repository
    if not is_in_git_repo() then
      return nil, "not in a git repository"
    end

    -- Execute git ls-files
    local output = vim.fn.system("git ls-files")
    if vim.v.shell_error ~= 0 then
      return nil, "git ls-files command failed"
    end

    -- Handle empty repository
    if output == "" or output:match("^%s*$") then
      return "no files tracked by git", nil
    end

    return output, nil
  end
}

return M
