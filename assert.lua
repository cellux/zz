local re = require('re')
local util = require('util')
local inspect = require('inspect')

local M = {}

local function assert_true(x, err, level)
   err = err or "assertion failed!"
   if x ~= true then
      level = (level or 1) + 1
      util.throwat(level, "assertion-error", err)
   end
end

M.is_true = assert_true

local function assert_false(x, err, level)
   level = (level or 1) + 1
   assert_true(x == false, err, level)
end

M.is_false = assert_false

local function assert_nil(x, err, level)
   level = (level or 1) + 1
   assert_true(x == nil, err, level)
end

M.is_nil = assert_nil

local function assert_not_nil(x, err, level)
   level = (level or 1) + 1
   assert_true(x ~= nil, err, level)
end

M.not_nil = assert_not_nil

local function assert_type(x, t, name_of_x, level)
   level = (level or 1) + 1
   assert_true(type(x) == t, sf("type(%s)==%s, expected %s", name_of_x or tostring(x), type(x), t), level)
end

M.type = assert_type

local function table_eq(x, y)
   if type(x) ~= type(y) then
      return false
   end
   for k,v in pairs(x) do
      if type(x[k]) == "table" then
         if not table_eq(x[k], y[k]) then
            return false
         end
      elseif x[k] ~= y[k] then
         return false
      end
   end
   for k,v in pairs(y) do
      if type(y[k]) == "table" then
         if not table_eq(y[k], x[k]) then
            return false
         end
      elseif y[k] ~= x[k] then
         return false
      end
   end
   return true
end

local function assert_equals(x, y, name_of_x, level)
   level = (level or 1) + 1
   if type(x)=="table" then
      assert_true(table_eq(x, y), sf("got:\n\n%s\n\nexpected:\n\n%s\n\n", inspect(x), inspect(y)), level)
   else
      if name_of_x then
         assert_true(x == y, sf("%s is %s, expected %s", name_of_x, tostring(x), tostring(y)), level)
      else
         assert_true(x == y, sf("%s != %s", tostring(x), tostring(y)), level)
      end
   end
end

M.equals = assert_equals

local function assert_match(pattern, value, err, level)
   level = (level or 1) + 1
   assert_type(pattern, "string", "assert_match pattern", level)
   assert_type(value, "string", "assert_match value", level)
   local m = re.match(pattern, value)
   if m == nil then
      err = err or sf("pattern '%s' does not match value:\n%s", pattern, value)
      util.throwat(level, "assertion-error", err)
   end
end

M.match = assert_match

local function assert_throws(pattern, f, level)
   level = (level or 1) + 1
   local ok, err = pcall(f)
   assert_false(ok, sf("%s expected to throw", f), level)
   assert_match(pattern, tostring(err), sf("%s expected to throw an error matching '%s', got: %s", f, pattern, err), level)
   return err
end

M.throws = assert_throws

local M_mt = {}

function M_mt:__call(x, err)
   assert_true(x ~= nil and x ~= false, err, 2)
   return x
end

return setmetatable(M, M_mt)
