--- types.lua
--- this file contains type definitions for droid.nvim

--- @class Droid.Opts
--- @field base_url string?
--- @field api_key_name string
--- @field edit_prompt string?
--- @field help_prompt string?
--- @field default_model string?
--- @field available_models string[]?
--- @field enable_helicone boolean?
--- @field context_providers table<string, fun(ref: CustomRef): string?, string?>?

--- @class Ref
--- @field type "file" | "shell" | "ctx_provider" | "error"
--- @field error? string
--- @field raw string

--- @class PathRef : Ref
--- @field type "file"
--- @field path string
--- @field start_line? number
--- @field end_line? number

--- @class ShellRef : Ref
--- @field type "shell"
--- @field command string

--- @class CustomRef : Ref
--- @field type "ctx_provider"
--- @field name string
--- @field path? string
--- @field start_line? number
--- @field end_line? number

--- @alias ContextRef PathRef | ShellRef | CustomRef | Ref

--- @class ResolvedRef
--- @field ref ContextRef
--- @field content? string
--- @field error? string

--- @class PromptContext
--- @field prompt string
--- @field context string
--- @field debug string
--- @field error string?
--- @field refs ContextRef[

--- @class Message
--- @field role "user"|"assistant"
--- @field content string
--- @field model string? only for assistant messages
