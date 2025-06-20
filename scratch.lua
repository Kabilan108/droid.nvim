--- @class Reference
--- @field type "file" | "dir" | "shell" | "command" | "error"
--- @field error? string
--- @field raw string

--- @class PathRef : Reference
--- @field type "file" | "dir"
--- @field path string
--- @field start_line? number
--- @field end_line? number

--- @class ShellRef : Reference
--- @field type "shell"
--- @field command string

--- @class Command
--- @field name string

--- @class CommandRef : Reference
--- @field type "command"
--- @field command Command
--- @field path? string
--- @field start_line? number
--- @field end_line? number

--- @alias ContextRef PathRef | CommandRef | Reference

---@param cmd string
---@param registered_commands Command[]
---@return Command | nil
local function validate_command(cmd, registered_commands)
  for _, registered_cmd in ipairs(registered_commands) do
    if registered_cmd.name == cmd then
      return registered_cmd
    end
  end
  return nil
end

--- parse command references from text (#command:file:start:end, #command:file, #command)
--- @param text string
--- @param registered_commands Command[]
local function parse_command_refs(text, registered_commands)
  local refs = {}

  for candidate in text:gmatch("#([%w_%-]+[^%s]*)") do
    local cmd, file, start_ln, end_ln = candidate:match("^([%w_%-]+):([^:]+):(%d+):([%d%+%-]+)$")
    if not cmd then
      cmd, file = candidate:match("^([%w_%-]+):(.+)$")
    end
    if not cmd then
      cmd = candidate:match("^([%w_%-]+)$")
    end

    if cmd then
      local command_obj = validate_command(cmd, registered_commands)
      if command_obj then
        local parsed_ref = {
          type = "command",
          command = command_obj,
          raw = "#" .. candidate,
        }
        if file then
          parsed_ref.path = file
          if start_ln then
            parsed_ref.start_line = tonumber(start_ln)
            parsed_ref.end_line = tonumber(end_ln)
          end
        end
        table.insert(refs, parsed_ref)
      else
        table.insert(refs, {
          type = "error",
          error = "Unknown command: " .. cmd,
          raw = "#" .. candidate,
        })
      end
    end
  end

  return refs
end

--- parse path references from text (e.g. @path/to/file.txt, @file.txt:1:10)
--- @param text string
--- @return PathRef[]
local function parse_path_refs(text)
  local refs = {}

  for candidate in text:gmatch("@([%w%.%/%:_]+)") do
    local parsed_ref = nil

    -- check for file with line range: @path:start:end
    if candidate:match("^[^:]+:%d+:[%d%+-]+$") then
      local path, start_ln, end_ln = candidate:match("^([^:]+):(%d+):([%d%+-]+)$")
      if path and start_ln and end_ln then
        parsed_ref = {
          type = "file",
          path = path,
          start_line = tonumber(start_ln),
          end_line = tonumber(end_ln),
          raw = "@" .. candidate,
        }
      end
    end

    -- no matches, check for file/dir
    if not parsed_ref then
      if candidate:sub(-1) == '/' then
        -- directories: @dir/
        parsed_ref = { type = "dir", path = candidate, raw = "@" .. candidate }
      elseif candidate:match(":") then
        -- malformed reference
        parsed_ref = { type = "error", error = "malformed reference", raw = "@" .. candidate }
      else
        -- default to @file
        parsed_ref = { type = "file", path = candidate, raw = "@" .. candidate }
      end
    end

    table.insert(refs, parsed_ref)
  end

  return refs
end

--- parse shell commands from text (e.g. @!`ls -la`)
--- @param text string
--- @return ShellRef[]
local function parse_shell_refs(text)
  local refs = {}
  for cmd in text:gmatch("@!`([^`]+)`") do
    table.insert(refs, { type = "shell", command = cmd, raw = "@!`" .. cmd .. "`" })
  end
  return refs
end

--- parses context references from text, extracting all @reference patterns into
--- structured, typed objects
--- @param text string the text to parse for context references
--- @param registered_commands Command[] registered commands
--- @return ContextRef[] array of parsed reference objectsl
local function parse_context_references(text, registered_commands)
  local refs = {}
  for _, parser in ipairs({ parse_path_refs, parse_shell_refs, function(t)
    return parse_command_refs(t, registered_commands)
  end }) do
    for _, ref in ipairs(parser(text)) do
      table.insert(refs, ref)
    end
  end
  return refs
end

local test_text = [[
I'm working on a neovim plugin and need help debugging an issue. Looking at @README.md, the droid.nvim plugin should support streaming completions, but I'm getting errors in @lua/init.lua when testing the help_completion function.

The error occurs at @tests/test_file.lua:10:20 where I'm trying to call the function. Can you check @tests/test_file.lua:10: and see if there's a syntax issue? The problem might be in the range @tests/test_file.lua::20 where I define the test cases.

I suspect the issue is in the @lua/ directory structure or maybe in @tests/ setup. The @.git/ history shows this worked before, #diff:foo.txt  #diff:./foo/bar.txt #diff:./foo/ so something changed recently. @!`dump -d foo/bar -g '**.go'`

Looking at @def:myFunction and @ref:myVariable, I think there might be a scoping issue. Can you also check @diagnostics for any linting errors, specifically @diagnostics:1:50 which shows type mismatches?

Finally, can you review the @diff and @diff:lua/init.lua to see what changed that might have broken the streaming functionality? @!`ls -la` fsdfdsfsd #diagnostics:./foo.txt:0:+10

#diagnostics
#diff

Pretty comprehensive  #diagnostics:foo.txt:1:+10 reference soup you got there. Most of these look like LSP/editor references for jumping@!`ls -la`dfsfsdafsd fsadfsd around code. The @ syntax is doing a lot of heavy lifting.
  ]]

local cmds = { { name = "diagnostics" }, { name = "diff" } }
local refs = parse_context_references(test_text, cmds)
local out = "found " .. #refs .. " references\n\n"
for _, r in ipairs(refs) do
  if r.type == "error" then
    out = out .. r.raw .. " ==> INVALID: '" .. r.error .. "'\n"
  elseif r.type == "shell" then
    out = out .. r.raw .. " ==> SHELL: `" .. r.command .. "`\n"
  elseif r.type == "file" then
    if r.start_line and r.end_line then
      out = out .. r.raw .. " ==> FILE: " .. r.path .. "[" .. r.start_line .. "," .. r.end_line .. "]\n"
    else
      out = out .. r.raw .. " ==> FILE: " .. r.path .. "\n"
    end
  elseif r.type == "dir" then
    out = out .. r.raw .. " ==> DIR: " .. r.path .. "\n"
  elseif r.type == "command" then
    if r.path and r.start_line and r.end_line then
      out = out ..
          r.raw ..
          " ==> COMMAND: " .. r.command.name .. "[" .. r.path .. ":" .. r.start_line .. "," .. r.end_line .. "]\n"
    elseif r.path then
      out = out .. r.raw .. " ==> COMMAND: " .. r.command.name .. "[" .. r.path .. "]\n"
    else
      out = out .. r.raw .. " ==> COMMAND: " .. r.command.name .. "\n"
    end
  end
end
print(out)
