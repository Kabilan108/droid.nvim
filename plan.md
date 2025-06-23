### **droid.nvim: phase 2 implementation spec**

**objective:** expand `droid.nvim`'s context awareness by implementing lsp, git, and harpoon providers.

**core directive for all provider agents (steps 1-3):**

your operational theater is **exclusively** `lua/providers.lua`. you will not touch any other file. your mission is to add new entries to the `M.builtin` table.

*   **pattern:** use the existing `M.builtin['diagnostics']` provider as your exemplar. each new provider is a table with a `description` (string) and a `handler` (function).
*   **handler signature:** your handler function MUST match this signature: `function(ref: CustomRef): string?, string?`. it receives a `ref` object and returns either `content, nil` on success or `nil, error_message` on failure.
*   **idempotency & safety:** your code must be resilient. assume external tools (`git`) or plugins (`harpoon`) might not be present. use `pcall` for requires and check for `vim.v.shell_error` after `vim.fn.system` calls. a missing dependency should result in a clean error message, not a catastrophic failure.

---

### **step 1: lsp integration agent**

**objective:** implement lsp-based context providers for code definition and references.

**providers to implement in `lua/providers.lua`:**

1.  `#def`
    *   **description:** "gets the lsp definition for a symbol in the current buffer."
    *   **syntax:** `#def:symbol_name`
    *   **handler logic:**
        *   the symbol name will be in `ref.path`.
        *   use `vim.lsp.buf.definition()` to find the symbol. this is an async call, so you'll need to handle it properly, likely by wrapping it in a coroutine or using `vim.lsp.util.synchronous_request`. for simplicity, a synchronous approach is probably fine here.
        *   if a definition is found, read the content of the target file and format the output to include the file path, line number, and a snippet of the code.
        *   **error handling:** return an error if the lsp is not active, the symbol is not found, or the request times out.

2.  `#ref`
    *   **description:** "gets all lsp references for a symbol in the current buffer."
    *   **syntax:** `#ref:symbol_name`
    *   **handler logic:**
        *   the symbol name will be in `ref.path`.
        *   use `vim.lsp.buf.references()` to find all references. this is also async.
        *   format the output as a list of locations (`file:line:col`).
        *   **error handling:** return an error if lsp is not active, the symbol is not found, or no references exist.

---

### **step 2: git integration agent**

**objective:** implement git-based context providers for diffs and file trees.

**providers to implement in `lua/providers.lua`:**

1.  `#diff`
    *   **description:** "gets the output of `git diff` for the current repository, optionally scoped to a path."
    *   **syntax:** `#diff` or `#diff:path/to/file_or_dir`
    *   **handler logic:**
        *   construct a `git diff` command. if `ref.path` exists, append it to the command.
        *   execute using `vim.fn.system()`.
        *   check `vim.v.shell_error` to ensure the command succeeded.
        *   return the raw command output.
        *   **error handling:** return an error if not in a git repository or if the command fails. if there's no diff, return a simple "no changes" message.

2.  `#tree`
    *   **description:** "gets the project file tree from `git ls-files`."
    *   **syntax:** `#tree`
    *   **handler logic:**
        *   this is dead simple. execute `git ls-files` using `vim.fn.system()`.
        *   check `vim.v.shell_error`.
        *   return the raw command output.
        *   **error handling:** return an error if not in a git repository.

---

### **step 3: harpoon integration agent**

**objective:** implement a context provider for the harpoon neovim plugin.

**provider to implement in `lua/providers.lua`:**

1.  `#harpoon`
    *   **description:** "gets the content of files marked in harpoon. specify an index or get all."
    *   **syntax:** `#harpoon` or `#harpoon:index`
    *   **handler logic:**
        *   use `pcall(require, 'harpoon')` to safely check if the plugin is available.
        *   get the list of items via `harpoon:list()`.
        *   if `ref.path` contains an index, get that specific item using `list:get(tonumber(ref.path))`. read its file content.
        *   if no index is provided, iterate through `list.items`, read the content of each file, and concatenate them with clear headers (e.g., `--- HARPOON [1]: path/to/file.lua ---`).
        *   **error handling:** return an error if harpoon is not installed, the harpoon list is empty, or an invalid index is provided.
