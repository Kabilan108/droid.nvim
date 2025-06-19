# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is `droid.nvim`, a Neovim plugin for LLM completion and chat using OpenAI-compatible APIs. The plugin provides streaming completions, dedicated chat buffers, and multi-turn conversation support.

## Core Architecture

### Single File Structure
- The entire plugin is contained in `lua/droid.lua` (~760 lines)
- Uses Neovim's built-in Lua API for buffer/window management
- Implements streaming HTTP responses via `plenary.job` and curl
- Chat conversation parsing with custom markdown-like markers

### Key Components
- **Streaming API Client**: OpenAI-compatible HTTP streaming via curl with server-sent events parsing
- **Conversation Parser**: Multi-turn chat parsing using `=== ASSISTANT BEGIN/END ===` markers
- **Buffer Management**: Dedicated chat buffers (`droid://chat-N`) with markdown syntax
- **Telescope Integration**: Model selection and chat buffer picker UI
- **Visual Selection Handling**: Extract text from visual/cursor contexts for completions

### Dependencies
- `plenary.nvim` - Job control for async curl processes
- `telescope.nvim` - Model/buffer picker UI
- `mini.notify` - User notifications
- `curl` - HTTP requests to LLM APIs

## Development Environment

### Nix Flake Setup
The repository includes a Nix flake that provides:
- Node.js 20 for Claude Code CLI
- Auto-installs `@anthropic-ai/claude-code` and `ccusage` globally

Enter development shell:
```bash
nix develop
```

### No Traditional Build System
- No package.json, Makefile, or traditional build files
- Plugin loads directly via Neovim's Lua runtime
- No compilation or bundling steps required

## Key Functions and Flow

### Completion Modes
- `help_completion()`: Appends AI response with conversation markers for multi-turn chat
- `edit_completion()`: Replaces selected text with AI-generated content
- Both use `invoke_llm_and_stream_into_editor()` with different system prompts

### Conversation Parsing
- `parse_conversation()` extracts message history from buffer content
- Handles malformed conversations and validates message alternation
- Returns structured `Message[]` array for API requests

### Streaming Response Handling
- `handle_openai_spec_data()` processes server-sent events from streaming APIs
- `write_string_at_cursor()` safely writes streamed content to buffer via `vim.schedule`
- Tracks usage statistics and formats them in conversation markers

### Buffer Management
- `create_droid_buffer()` creates dedicated chat buffers with markdown filetype
- `pick_droid_buffer()` provides Telescope UI for buffer selection with preview
- Buffers use `droid://chat-N` naming scheme and auto-cleanup on deletion

## Configuration

Default models and prompts are defined in `M.available_models` and setup defaults. The plugin expects:
- Environment variable for API key (configurable name)
- OpenAI-compatible API endpoint
- Streaming JSON response format

## API Integration Notes

- Uses OpenAI chat completions format with streaming
- Sends conversation history as message array with system prompt
- Handles both anthropic and OpenAI response formats (though currently uses OpenAI spec)
- Temperature set to 0.7 for balanced creativity/consistency