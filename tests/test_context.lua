package.loaded["droid"] = nil
local droid = require("droid")
local util = droid.util

droid.setup({})

local test_text = [[
@flake.nix
#diagnostics
  ]]


local prompt = util.build_prompt(test_text)
print(vim.inspect(prompt))
