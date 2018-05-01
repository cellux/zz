local re = require('re')

local M = {}

local function assert_true(x, err, level)
   err = err or "assertion failed!"
   level = level or 2
   if x ~= true then
      error(err, level)
   end
end

local function assert_false(x, err, level)
   level = level or 2
   assert_true(x==false, err, level+1)
end

M.is_false = assert_false

local function assert_nil(x, err, level)
   level = level or 2
   assert_true(x==nil, err, level+1)
end

M.is_nil = assert_nil

local function assert_type(x, t, name_of_x, level)
   level = level or 2
   if name_of_x then
      assert_true(type(x)==t, sf("type(%s)==%s, expected %s", name_of_x, type(x), t), level+1)
   else
      assert_true(type(x)==t, sf("type(%s)==%s, expected %s", tostring(x), type(x), t), level+1)
   end
end

M.type = assert_type

local function assert_equals(x, y, name_of_x, level)
   level = level or 2
   --assert_true(type(x) == type(y), sf("x.type (%s: %s) != y.type (%s: %s)", type(x), x, type(y), y), level+1)
   if type(x)=="table" then
      assert_true(#x==#y, sf("#x=%d != #y=%d", #x, #y), level+1)
      for i=1,#x do
         assert_equals(x[i], y[i], name_of_x and sf("%s[%d]", name_of_x, i), level+1)
      end
      for k,v in pairs(x) do
         assert_equals(x[k], y[k], name_of_x and sf("%s[%s]", name_of_x, k), level+1)
      end
      for k,v in pairs(y) do
         assert_equals(y[k], x[k], name_of_x, level+1)
      end
   else
      if name_of_x then
         assert_true(x==y, sf("%s is %s, expected %s", name_of_x, tostring(x), tostring(y)), level+1)
      else
         assert_true(x==y, sf("%s != %s", tostring(x), tostring(y)), level+1)
      end
   end
end

M.equals = assert_equals

local function assert_match(pattern, value, err, level)
   level = level or 2
   local m = re.match(pattern, value)
   assert_true(m ~= nil, err, level+1)
end

M.match = assert_match

local function assert_throws(pattern, f)
   local ok, err = pcall(f)
   assert_false(ok, sf("%s expected to throw", f), 3)
   assert_match(pattern, err, sf("%s expected to throw an error matching '%s', got: %s", f, pattern, err), 3)
   return err
end

M.throws = assert_throws

local M_mt = {}

function M_mt:__call(x, err)
   assert_true(x ~= nil and x ~= false, err, 3)
   return x
end

return setmetatable(M, M_mt)
