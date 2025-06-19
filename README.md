# droid.nvim

a neovim plugin for llm completion and chat using openai-compatible apis.

## features

- streaming llm completions directly in your buffer
- edit mode: replace selected text with ai-generated content
- help mode: append ai responses with conversation tracking
- model selection via telescope picker
- dedicated chat buffers with conversation history
- multi-turn conversations with proper parsing
- support for visual selection and cursor-based text extraction

## installation

using lazy.nvim:

```lua
{
  "kabilan108/droid.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
    "echasnovski/mini.notify"
  },
  config = function()
    require("droid").setup({
      api_key_name = "OPENROUTER_API_KEY", -- environment variable name
      base_url = "https://openrouter.ai/api/v1", -- optional: defaults to openrouter
      default_model = "anthropic/claude-3.5-sonnet-20240620", -- optional
    })
  end
}
```

## configuration

```lua
require("droid").setup({
  api_key_name = "YOUR_API_KEY_ENV_VAR", -- required: env var containing your api key
  base_url = "https://openrouter.ai/api/v1", -- optional: api endpoint
  default_model = "anthropic/claude-3.5-sonnet-20240620", -- optional: default model
  available_models = { -- optional: custom model list
    "openai/gpt-4.1",
    "anthropic/claude-sonnet-4",
    -- add your preferred models
  },
  edit_prompt = "custom edit instructions", -- optional: customize edit behavior
  help_prompt = "custom help instructions", -- optional: customize help behavior
})
```

## keybindings

map the plugin functions to your preferred keys:

```lua
-- basic completions
vim.keymap.set({"n", "v"}, "<leader>ll", require("droid").help_completion, { desc = "llm: help" })
vim.keymap.set({"n", "v"}, "<leader>le", require("droid").edit_completion, { desc = "llm: edit" })

-- model and buffer management  
vim.keymap.set({"n", "v"}, "<leader>lm", require("droid").select_model, { desc = "llm: select model" })
vim.keymap.set("n", "<leader>ln", require("droid").jump_to_new, { desc = "llm: jump to new" })
vim.keymap.set("n", "<leader>lc", require("droid").cancel_completion, { desc = "llm: cancel stream" })

-- chat buffers
vim.keymap.set("n", "<leader>ld", require("droid").create_droid_buffer, { desc = "llm: new chat buffer" })
vim.keymap.set("n", "<leader>lp", require("droid").pick_droid_buffer, { desc = "llm: pick chat buffer" })
```

## functions

### completion functions

- `help_completion()` - appends ai response after cursor/selection with conversation markers
- `edit_completion()` - replaces selected text or content at cursor with ai-generated text
- `cancel_completion()` - stops active streaming completion

### model management

- `select_model()` - opens telescope picker to choose from available models
- `get_current_model()` - returns currently selected model name
- `set_current_model(model)` - programmatically set the active model

### buffer management

- `jump_to_new()` - adds separator and moves cursor to end of buffer
- `create_droid_buffer()` - creates new dedicated chat buffer
- `pick_droid_buffer()` - telescope picker for existing chat buffers
- `list_droid_buffers()` - returns list of active chat buffers
- `is_droid_buffer(buf_id)` - checks if buffer is a droid chat buffer

## usage

### edit mode
select text in visual mode and call `edit_completion()`. the selected text will be replaced with ai-generated content based on your selection and any comments within it.

### help mode
place cursor anywhere or select text, then call `help_completion()`. the ai response will be appended with conversation markers for multi-turn discussions.

### chat buffers
use `create_droid_buffer()` to start dedicated llm conversations. these buffers support full conversation history and can be managed via the telescope picker.

## requirements

- neovim 0.7+
- plenary.nvim
- telescope.nvim  
- mini.notify
- curl (for api requests)
- api key from openrouter or compatible service

## acknowledgements

the original version of this was modified from @yacineMTB's [dingllm.nvim](https://github.com/yacineMTB/dingllm.nvim)

## license

[apache](LICENSE)
