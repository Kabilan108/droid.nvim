#!/usr/bin/env lua

-- Structural test for LSP providers (no Neovim APIs required)
print("Testing LSP provider structure...")
print("=================================")

-- Test provider source code structure
local function test_source_structure()
  print("\n1. Testing source code structure...")
  
  local providers_file = io.open("lua/providers.lua", "r")
  assert(providers_file, "Could not open providers.lua")
  local source = providers_file:read("*all")
  providers_file:close()
  
  -- Test for critical fixes
  print("   Checking for ref.path usage...")
  assert(not source:find('ref%.text'), "❌ CRITICAL: Still using ref.text instead of ref.path")
  assert(source:find('ref%.path'), "❌ CRITICAL: Not using ref.path for symbol name")
  
  print("   Checking for cursor movement elimination...")
  assert(not source:find("nvim_win_set_cursor"), "❌ CRITICAL: Still moving cursor")
  assert(not source:find("original_pos"), "❌ CRITICAL: Still tracking cursor position")
  
  print("   Checking for helper functions...")
  assert(source:find("get_lsp_clients"), "❌ Missing get_lsp_clients helper")
  assert(source:find("find_symbol_position"), "❌ Missing find_symbol_position helper")
  assert(source:find("make_lsp_request"), "❌ Missing make_lsp_request helper")
  
  print("   Checking for proper symbol matching...")
  assert(source:find("vim%.pesc"), "❌ Should use vim.pesc for pattern escaping")
  assert(source:find("\\\\b"), "❌ Should use word boundary matching")
  
  print("   Checking for programmatic position params...")
  assert(source:find("textDocument.*make_text_document_params"), "❌ Should create textDocument params programmatically")
  assert(source:find("position.*=.*pos"), "❌ Should set position programmatically")
  
  print("✓ Source code structure is correct")
end

-- Test that code duplication has been eliminated
local function test_code_deduplication()
  print("\n2. Testing code deduplication...")
  
  local providers_file = io.open("lua/providers.lua", "r")
  local source = providers_file:read("*all")
  providers_file:close()
  
  -- Count occurrences of common patterns that should now be in helper functions
  local lsp_client_checks = 0
  local timeout_waits = 0
  
  for line in source:gmatch("[^\r\n]+") do
    if line:find("get_active_clients") and not line:find("local function get_lsp_clients") then
      lsp_client_checks = lsp_client_checks + 1
    end
    if line:find("vim%.wait.*100") then
      timeout_waits = timeout_waits + 1
    end
  end
  
  -- Should only have LSP client checks in the helper function, not duplicated
  assert(lsp_client_checks <= 1, "❌ LSP client validation still duplicated")
  
  -- Should only have timeout logic in helper function
  assert(timeout_waits <= 1, "❌ Timeout logic still duplicated")
  
  print("✓ Code deduplication successful")
end

-- Test error handling consistency
local function test_error_handling()
  print("\n3. Testing error handling consistency...")
  
  local providers_file = io.open("lua/providers.lua", "r")
  local source = providers_file:read("*all")
  providers_file:close()
  
  -- Both handlers should follow the same error pattern
  local def_handler = source:match('M%.builtin%["def"%].-handler = function%(ref%)(.-)\n  end\n}')
  local ref_handler = source:match('M%.builtin%["ref"%].-handler = function%(ref%)(.-)\n  end\n}')
  
  assert(def_handler, "❌ Could not extract def handler")
  assert(ref_handler, "❌ Could not extract ref handler")
  
  -- Both should validate clients the same way
  assert(def_handler:find("get_lsp_clients"), "❌ def handler should use get_lsp_clients helper")
  assert(ref_handler:find("get_lsp_clients"), "❌ ref handler should use get_lsp_clients helper")
  
  -- Both should validate input the same way
  assert(def_handler:find("not ref%.path"), "❌ def handler should validate ref.path")
  assert(ref_handler:find("not ref%.path"), "❌ ref handler should validate ref.path")
  
  print("✓ Error handling is consistent")
end

-- Run all tests
local function run_tests()
  local tests = {
    test_source_structure,
    test_code_deduplication,
    test_error_handling
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
  
  print(string.format("\n================================="))
  print(string.format("Tests completed: %d/%d passed", passed, total))
  
  if passed == total then
    print("🎉 LSP providers successfully rewritten!")
    print("\n✅ CRITICAL ISSUES FIXED:")
    print("   • Uses ref.path instead of ref.text for symbol names")
    print("   • No cursor movement side effects")
    print("   • Proper word boundary symbol matching")
    print("   • Abstracted common logic into helper functions")
    print("   • Programmatic LSP position parameter creation")
    print("   • Consistent error handling patterns")
  else
    print("❌ Critical issues remain in the implementation.")
    os.exit(1)
  end
end

-- Execute tests
run_tests()