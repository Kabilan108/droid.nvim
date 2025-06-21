package.loaded["droid"] = nil
local droid = require("droid")
local util = droid.util

local test_text = [[
I'm working on a neovim plugin and need help debugging an issue. Looking at @README.md, the droid.nvim plugin should support streaming completions, but I'm getting errors in @lua/init.lua when testing the help_completion function.

@README.md:10:15

The error occurs at @tests/test_file.lua:10:20 where I'm trying to call the function. Can you check @tests/test_file.lua:10: and see if there's a syntax issue? The problem might be in the range @tests/test_file.lua::20 where I define the test cases.

@file.txt:15:-1
I suspect the issue is in the @lua/ directory structure or maybe in @tests/ setup. The @.git/ history shows this worked before, #diff:foo.txt  #diff:./foo/bar.txt #diff:./foo/ so something changed recently. @!`dump -d foo/bar -g '**.go'`

Looking at @def:myFunction and @ref:myVariable, I think there might be a scoping issue. Can you also check @diagnostics for any linting errors, specifically @diagnostics:1:50 which shows type mismatches?

Finally, can you review the @diff and @diff:lua/init.lua to see what changed that might have broken the streaming functionality? @!`ls -la` fsdfdsfsd #diagnostics:./foo.txt:0:+10

#diagnostics
#diff

Pretty comprehensive  #diagnostics:foo.txt:1:+10 reference soup you got there. Most of these look like LSP/editor references for jumping@!`ls -la`dfsfsdafsd fsadfsd around code. The @ syntax is doing a lot of heavy lifting. #diagnostics:foo.txt:10:-1
  ]]


local prompt = build_prompt(test_text)
print(prompt.context)

local file = io.open("prompt_output.json", "w")
if file then
  file:write(vim.fn.json_encode(prompt))
  file:close()
end
