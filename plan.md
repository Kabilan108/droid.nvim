# Context Injection Implementation Plan

## Overview

This document outlines the implementation plan for adding context injection features to `droid.nvim`. The goal is to allow users to reference files, code symbols, git information, and custom data sources using `@reference` syntax in their LLM conversations.

## Current Architecture Understanding

**Core Components:**
- Single file plugin: `lua/droid.lua` (~1200+ lines)
- Streaming LLM API client using OpenAI-compatible endpoints
- Conversation parsing with `=== ASSISTANT BEGIN/END ===` markers
- Dedicated chat buffers (`droid://chat-N`) with Telescope picker
- Dependencies: `plenary.nvim`, `telescope.nvim`, `mini.notify`, `curl`
- Organized into `M` (module) and `util` namespaces for better structure

**Key Functions:**
- `get_conversation_context(mode)` - Extracts messages from buffer/selection
- `parse_conversation(lines)` - Parses chat history from buffer content
- `invoke_llm_and_stream_into_editor(mode)` - Main API call orchestrator
- `make_openai_spec_curl_args(mode, messages)` - Builds API request
- **NEW:** `parse_context_references(text)` - Extracts all reference patterns
- **NEW:** `resolve_context_reference(ref)` - Resolves references to content
- **NEW:** `build_prompt(prompt)` - Builds PromptContext with resolved references
- **NEW:** `register_context_provider(name, handler)` - Custom provider registry

## Target Context Injection System

### Implemented Syntax
- ✅ `@filename` - Include entire file content
- ✅ `@filename:10:20` - Include lines 10-20 of file
- ✅ `@filename:10:-1` - Include from line 10 to end of file (negative line support)
- ✅ `@!\`command\`` - Execute shell commands and include output
- ✅ `#provider_name` - Use registered custom context providers
- ✅ `#provider_name:path` - Provider with path argument
- ✅ `#provider_name:path:10:20` - Provider with path and line range
- ✅ `#diagnostics` - Include LSP diagnostics for current file

### Planned Custom Context Providers
- `#def:symbol` - Include symbol definition via LSP
- `#ref:symbol` - Include all references to symbol via LSP
- `#diff` - Include current git diff
- `#diff:path` - Include git diff for specific path
- `#tree` - Include project file tree structure
- `#harpoon` - Include all harpooned files

### Architecture (Achieved & Goals)
1. ✅ **Extensible**: Plugin authors can register custom context providers via `M.register_context_provider()`
2. ✅ **Priority-based**: Parsing order: path refs → shell refs → custom refs
3. ✅ **Path-smart**: Resolves relative paths via git root and cwd
4. ✅ **Error-resilient**: Graceful handling of missing files, invalid references with user notifications
5. ✅ **Debug visibility**: Shows `[references]: @file, @!\`cmd\`, #provider` before responses
6. ✅ **Clean separation**: Debug info visible to users but filtered from LLM context
7. ⏳ **Performance-conscious**: Need to add size limits and truncation

## Implementation Steps

### Step 1: Core Context Parser Infrastructure ✅ COMPLETED
**Goal:** Build the foundation for parsing and resolving `@references`

**Completed Tasks:**
- ✅ Created `parse_context_references(text)` function that extracts all reference patterns
- ✅ Implemented `resolve_context_reference(ref)` dispatcher function
- ✅ Added context provider registry system via `M.register_context_provider()`
- ✅ Created utility functions for path resolution (relative to git root/cwd)
- ✅ Added error handling and user notifications for invalid references
- ✅ Integrated parser into message preparation pipeline before API calls
- ✅ Added XML-formatted context injection: `<reference match="@file">content</reference>`
- ✅ Implemented debug info display: `[references]: @file.txt, @!\`ls\`, #provider`
- ✅ Debug info filtered from LLM conversation parsing

**Achieved:**
- Parse `@filename`, `@!\`command\``, and `#provider` references
- File reading with absolute and relative paths (git root fallback)
- Shell command execution with output capture
- Custom provider registration and execution
- Error messages via `mini.notify` for failures
- Context properly injected into API requests
- No breaking changes to existing functionality

**Testing:**
- Create test files in project directory
- Try `@relative/path.txt` and `@/absolute/path.txt` references
- Verify error handling for missing files
- Check that normal chat functionality still works

### Step 2: File and Directory Context Enhancement
**Goal:** Complete file system context injection

**Already Completed:**
- ✅ Basic file content reading implemented
- ✅ Line range parsing and extraction (`@file:START:END`)
- ✅ Support negative line numbers (`-1` = end of file)
- ✅ XML-formatted context injections

**Success Criteria:**
- `@filename` includes full file content with proper formatting
- `@dir/` lists all files in directory (respecting common ignore patterns)
- Line ranges work correctly: `@file.txt:1:10`, `@file.txt:5:-1`

**Testing:**
- Test with various file types (.lua, .md, .json, etc.)
- Test directory inclusion with nested structures
- Verify line range edge cases (out of bounds, reverse ranges)

### Step 3: LSP Integration
**Goal:** Add code intelligence context via Neovim's LSP

**Tasks:**
- [ ] Research Neovim LSP API functions needed
- [ ] Implement `@def:symbol` using `vim.lsp.buf.definition()`
- [ ] Implement `@func:name` with symbol search and definition retrieval
- [ ] Implement `@ref:symbol` using `vim.lsp.buf.references()`
- [x] Add `@diagnostics` for current file/buffer diagnostics
- [x] Support `@diagnostics:path` for specific file diagnostics
- [ ] Handle cases where LSP is not available or symbol not found
- [ ] Format LSP responses into structured context

**Success Criteria:**
- `@def:MyClass` shows class definition with file location
- `@func:calculate` shows function implementation
- `@ref:someVar` lists all usage locations
- `@diagnostics` shows current file errors/warnings in readable format
- Graceful fallback when LSP unavailable
- Clear error messages for unfound symbols

**Testing:**
- Test in projects with active LSP (lua-language-server, etc.)
- Try symbol lookups across files
- Test with symbols that don't exist
- Verify diagnostic information accuracy

### Step 4: Git Integration
**Goal:** Add version control context

**Tasks:**
- [ ] Implement `@diff` using `git diff` command
- [ ] Support `@diff:path` for specific file/directory diffs
- [ ] Add `@tree` using `git ls-files`
- [ ] Handle non-git repositories gracefully
- [ ] Support git worktree scenarios
- [ ] Format git output for LLM consumption

**Success Criteria:**
- `@diff` shows current working directory changes
- `@diff:src/` shows changes only in src directory
- `@tree` provides clean file listing for project overview
- Works in git repos and shows appropriate errors otherwise
- Handles empty diffs and clean trees gracefully

**Testing:**
- Test in git repo with staged/unstaged changes
- Test with specific path diffs
- Test in non-git directory
- Verify tree output format is LLM-friendly

### Step 5: Harpoon Integration
**Goal:** Add Harpoon integration as a custom context provider

**Tasks:**
- [x] Study Harpoon API documentation (COMPLETED)
- [ ] Implement `#harpoon` provider to include all harpooned files
- [ ] Add proper error handling for when Harpoon isn't installed
- [ ] Format harpooned files with clear headers
- [ ] Document usage in README

**Implementation Details (from Harpoon v2 docs):**
```lua
-- Check if Harpoon is available
local ok, harpoon = pcall(require, "harpoon")
if not ok then
  return nil, "Harpoon not installed"
end

-- Get all harpooned files
local list = harpoon:list()
local items = list.items  -- Array of harpooned items

-- Access specific file by index
local item = list:get(index)  -- Gets item at index
-- item.value contains the file path

-- Provider implementation sketch:
M.register_context_provider("harpoon", function(ref)
  if ref.path then  -- #harpoon:2 (specific index)
    local index = tonumber(ref.path)
    -- Get and read specific harpooned file
  else  -- #harpoon (all files)
    -- Iterate through all items and read files
  end
end)
```

**Success Criteria:**
- `#harpoon` includes content of all harpooned files with index labels
- Graceful error when Harpoon not installed: "Harpoon not installed"
- Clear structured formatting
- Handles empty harpoon list gracefully

**Testing:**
- Test with Harpoon installed and files marked
- Test without Harpoon installed
- Test with empty harpoon list
- Verify formatting is LLM-friendly

### Step 6: Shell Command Security & Limits
**Goal:** Add security and performance limits to shell command execution

**Current State:**
- ✅ Basic shell command execution via `@!\`command\``
- ✅ Output capture and error handling

**Tasks:**
- [ ] Add timeout for shell commands (default 5 seconds)
- [ ] Implement output size limits (max 50KB)
- [ ] Add configurable command whitelist/blacklist
- [ ] Improve error messages for command failures
- [ ] Add option to show stderr in debug mode
- [ ] Document security considerations

**Success Criteria:**
- Commands timeout after configured duration
- Large outputs are truncated with warning
- Dangerous commands can be blocked
- Clear error messages for failures

**Success Criteria:**
- `@harpoon` works and includes all harpooned files
- API documented with clear examples
- Third-party providers can be registered easily
- Provider errors don't crash the plugin
- Provider execution is reasonably fast

**Testing:**
- Implement Harpoon provider as proof of concept
- Test provider error handling
- Verify API documentation with example usage

### Step 7: Keybind Helpers and UX Improvements
**Goal:** Add convenience functions for common context injection workflows

**Updated Tasks Based on Current Implementation:**
- [ ] Create `M.add_file_reference(filename)` - adds `@filename` to current position
- [ ] Add `M.add_current_file_reference()` - adds `@current_file` reference
- [ ] Implement `M.add_visual_selection_reference()` - adds `@file:start:end` for selection
- [ ] Add `M.add_diagnostics_reference()` - adds `@diagnostics` reference
- [ ] Create `M.jump_to_latest_chat()` function
- [ ] Update `M.create_droid_buffer()` to optionally add initial reference
- [ ] Add completion/snippet support for reference syntax

**Success Criteria:**
- Keybinds can quickly add current file to most recent chat
- Visual selections can be added as context with line numbers
- Functions handle edge cases (no chat buffers, invalid selections)
- Clear user feedback for successful/failed context injection
- Smooth UX flow from any buffer to chat with context

**Testing:**
- Map test keybinds and verify functionality
- Test with multiple chat buffers open
- Test edge cases (no chat buffers, empty selections)
- Verify context appears correctly formatted in chat

## Implementation Guidelines

### Code Organization (Updated Based on Implementation)
- All code remains in single `lua/droid.lua` file
- Functions organized under `M` (public API) and `util` (internal helpers)
- Context reference functions follow pattern:
  - `parse_*_refs()` - for parsing specific reference types
  - `resolve_context_reference()` - central dispatcher
  - `format_reference()` - XML formatting
- Type annotations added for better code clarity
- Error handling via `mini.notify` with appropriate log levels

### Error Handling Strategy
- Never crash the plugin due to context resolution failures
- Show user-friendly notifications for common errors
- Log detailed errors for debugging
- Gracefully degrade when external tools unavailable
- Provide helpful suggestions in error messages

### Performance Considerations
- Set reasonable file size limits (suggest 50KB per file)
- Implement lazy loading where possible
- Cache expensive operations (LSP lookups, git commands)
- Add timeouts for external commands
- Warn users about large context injections

### Testing Strategy for Each Step
1. Create minimal test cases in project directory
2. Test both success and failure scenarios
3. Verify no regressions in existing functionality
4. Test with realistic file sizes and project structures
5. Get user approval before proceeding to next step

### Context Formatting Standards (Implemented)
Context is formatted as XML for clear LLM consumption:
```xml
<reference match="@file.txt" path="/full/path/file.txt">
file content here
</reference>

<reference match="@!`ls -la`" shell_command="ls -la">
command output here
</reference>

<reference match="#provider:arg" provider="provider" path="arg">
provider output here
</reference>
```

Debug info shown to user (filtered from LLM):
```
[references]: @file.txt, @!`ls`, #provider:arg
=== ASSISTANT BEGIN [model-name] ===
```

## Progress Tracking

**Current Status:** Step 1 COMPLETED - Core infrastructure fully implemented

**Completed:**
- ✅ Step 1: Core Context Parser Infrastructure
- ✅ Step 2: File/Directory enhancements

- All three reference types parsing: `@file`, `@!`cmd``, `#provider`
- Path resolution with git root fallback
- Custom provider registry system
- Debug info display and filtering
- XML-formatted context injection
- Error handling with notifications

**Next Actions:**
2. Begin Step 3: LSP Integration (most requested feature)
3. Begin Step 4: Git Integration (useful for code reviews)

**Implementation Order (Revised):**
2. LSP integration (`@def:`, `@ref:`, `@diagnostics`)
3. Git integration (`@diff`, `@tree`)
4. Harpoon integration (after documentation provided)
5. Shell command security/limits
6. Keybind helpers

**Implementation Notes:**
- The core parsing and registry system is solid and extensible
- Three parallel parsing functions handle different reference types
- Custom providers use the `#name` syntax to avoid conflicts
- Shell commands use `@!`backticks`` for clarity
- All references are shown in debug but filtered from LLM conversation
- The `util.build_prompt()` function is the central orchestrator
- Path resolution tries cwd first, then git root
- Error handling is user-friendly via `mini.notify`

**Key Functions for Extension:**
- `M.register_context_provider(name, handler)` - Add new providers
- `parse_context_references()` - Extracts all refs from text  
- `resolve_context_reference()` - Dispatcher for resolution
- `format_reference()` - Consistent XML formatting

## Success Metrics

**Technical Success:**
- All context reference types work as specified
- No breaking changes to existing functionality
- Code remains maintainable and well-documented
- Performance impact is minimal

**User Success:**
- Natural and intuitive syntax for context injection
- Helpful error messages and user feedback
- Smooth integration with existing chat workflow
- Extensible system for future enhancements
