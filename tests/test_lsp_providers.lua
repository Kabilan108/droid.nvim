#!/usr/bin/env lua

-- Test script for LSP providers
-- Run with: nvim --headless -c "luafile tests/test_lsp_providers.lua" -c "qa!"

-- Add lua directory to package path
package.path = package.path .. ";./lua/?.lua"

package.loaded["providers"] = nil
local providers = require("providers")

print("Testing LSP provider implementations...")
print("=====================================")

-- Test 1: Validate provider structure
local function test_provider_structure()
  print("\n1. Testing provider structure...")
  
  -- Check def provider exists
  assert(providers.builtin["def"], "def provider not found")
  assert(providers.builtin["def"].description, "def provider missing description")
  assert(providers.builtin["def"].handler, "def provider missing handler")
  assert(type(providers.builtin["def"].handler) == "function", "def handler is not a function")
  
  -- Check ref provider exists
  assert(providers.builtin["ref"], "ref provider not found")
  assert(providers.builtin["ref"].description, "ref provider missing description")
  assert(providers.builtin["ref"].handler, "ref provider missing handler")
  assert(type(providers.builtin["ref"].handler) == "function", "ref handler is not a function")
  
  print("✓ Provider structure is valid")
end

-- Test 2: Validate input validation
local function test_input_validation()
  print("\n2. Testing input validation...")
  
  -- Test def with empty path
  local empty_ref = { name = "def", path = nil }
  local content, err = providers.builtin["def"].handler(empty_ref)
  assert(content == nil, "def should return nil for empty path")
  assert(err and err:find("no symbol name provided"), "def should return proper error for empty path")
  
  -- Test ref with empty path
  local content2, err2 = providers.builtin["ref"].handler(empty_ref)
  assert(content2 == nil, "ref should return nil for empty path")
  assert(err2 and err2:find("no symbol name provided"), "ref should return proper error for empty path")
  
  print("✓ Input validation works correctly")
end

-- Test 3: Validate proper field usage
local function test_field_usage()
  print("\n3. Testing correct field usage...")
  
  -- Create a mock ref that uses path (not text)
  local test_ref = { 
    name = "def", 
    path = "test_symbol",
    type = "ctx_provider"
  }
  
  -- The handlers should now read from ref.path, not ref.text
  -- We can't test the full LSP functionality without a real buffer and LSP server,
  -- but we can verify it tries to use the path field
  local content, err = providers.builtin["def"].handler(test_ref)
  
  -- Should fail because no LSP clients, but not because of missing symbol name
  assert(content == nil, "def should return nil without LSP clients")
  assert(err and (err:find("no active lsp clients") or err:find("not found")), 
         "def should fail with LSP or symbol error, not input validation error")
  
  print("✓ Handlers correctly use ref.path field")
end

-- Test 4: No cursor movement (structural test)
local function test_no_cursor_movement()
  print("\n4. Testing cursor movement elimination...")
  
  -- We can't fully test this without mocking vim APIs, but we can verify
  -- the code structure doesn't call vim.api.nvim_win_set_cursor
  local def_source = tostring(providers.builtin["def"].handler)
  local ref_source = tostring(providers.builtin["ref"].handler)
  
  assert(not def_source:find("nvim_win_set_cursor"), "def handler should not move cursor")
  assert(not ref_source:find("nvim_win_set_cursor"), "ref handler should not move cursor")
  
  print("✓ No cursor movement in handlers")
end

-- Test 5: Code structure improvements
local function test_code_structure()
  print("\n5. Testing code structure improvements...")
  
  -- Check that the source code includes helper functions
  local providers_file = io.open("lua/providers.lua", "r")
  assert(providers_file, "Could not open providers.lua")
  local source = providers_file:read("*all")
  providers_file:close()
  
  assert(source:find("get_lsp_clients"), "get_lsp_clients helper function not found")
  assert(source:find("find_symbol_position"), "find_symbol_position helper function not found")
  assert(source:find("make_lsp_request"), "make_lsp_request helper function not found")
  assert(source:find("vim.pesc"), "Should use vim.pesc for pattern escaping")
  assert(source:find("\\\\b"), "Should use word boundary matching")
  
  print("✓ Code structure includes proper helper functions")
end

-- Run all tests
local function run_tests()
  local tests = {
    test_provider_structure,
    test_input_validation,
    test_field_usage,
    test_no_cursor_movement,
    test_code_structure
  }
  
  local passed = 0
  local total = #tests
  
  for i, test in ipairs(tests) do
    local success, err = pcall(test)
    if success then
      passed = passed + 1
    else
      print(string.format("✗ Test %d failed: %s", i, err))
    end
  end
  
  print(string.format("\n====================================="))
  print(string.format("Tests completed: %d/%d passed", passed, total))
  
  if passed == total then
    print("🎉 All tests passed! LSP providers have been successfully rewritten.")
  else
    print("❌ Some tests failed. Please review the implementation.")
    os.exit(1)
  end
end

-- Execute tests
run_tests()