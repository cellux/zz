local testing = require('testing')('stream')
local stream = require('stream')
local assert = require('assert')

testing("memory streams", function()
   local s = stream()

   assert(s:eof())
   s:write("hello")
   assert(not s:eof())
   assert.equals(s:read(), "hello")
   assert(s:eof())

   s:write("hello\nworld\n")
   assert.equals(s:readln(), "hello")
   assert.equals(s:readln(), "world")
   assert(s:eof())

   s:write("hello\nworld\n")
   assert.equals(s:read(0), "hello\nworld\n")
   assert(s:eof())

   s:write("hello\nworld\n")
   assert.equals(s:read(2), "he")
   assert.equals(s:read(5), "llo\nw")
   assert.equals(s:read(0), "orld\n")
   assert(s:eof())

   -- writeln works with numbers
   s:writeln(1234)
   assert.equals(s:readln(), "1234")
end)
