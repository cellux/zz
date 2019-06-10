local testing = require('testing')('assert')
local assert = require('assert')
local re = require('re')
local sf = string.format

testing("true", function()
   local function test_assert_true()
      assert(5==3, "5!=3")
   end
   local status, err = pcall(test_assert_true)
   assert(not status)
   assert(re.match("5!=3", tostring(err)), sf("err=%s does not match 5!=3", err))
end)

testing("type", function()
   local function test_assert_type()
      local s = "hello"
      assert.type(s, 'number', "s")
   end
   local status, err = pcall(test_assert_type)
   assert(not status)
   assert(re.match("type\\(s\\)==string, expected number", tostring(err)))
end)

testing("equals", function()
   local function test_assert_equals()
      local a = {'a','b',{c={5,8}},true,false}
      local b = {'a','b',{c={5,9}},true,false}
      assert.equals(a, b)
   end
   local status, err = pcall(test_assert_equals)
   assert(not status)
   local pattern = [[^got:

{ "a", "b", {
    c = { 5, 8 }
  }, true, false }

expected:

{ "a", "b", {
    c = { 5, 9 }
  }, true, false }
$]]
   assert(re.match(pattern, err.message), sf("%s does not match %s", err, pattern))
end)
