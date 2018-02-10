local assert = require('assert')
local re = require('re')
local sf = string.format

local function test_assert_true()
   assert(5==3, "5!=3")
end

local function test_assert_type()
   local s = "hello"
   assert.type(s, 'number', "s")
end

local function test_assert_equals()
   local a = {'a','b',{c={5,8}},true,false}
   local b = {'a','b',{c={5,9}},true,false}
   assert.equals(a, b, "a")
end

local status, err = pcall(test_assert_true)
assert(not status)
assert(re.match("5!=3", err), sf("err=%s does not match 5!=3", err))

local status, err = pcall(test_assert_type)
assert(not status)
assert(re.match("type\\(s\\)==string, expected number", err))

local status, err = pcall(test_assert_equals)
assert(not status)
assert(re.match("a\\[3\\]\\[c\\]\\[2\\] is 8, expected 9", err))
