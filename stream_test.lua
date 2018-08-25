local testing = require('testing')('stream')
local stream = require('stream')
local buffer = require('buffer')
local assert = require('assert')

testing("memory streams (fifos)", function()
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

testing("read_until", function()
   local buf = buffer.copy("\"This is not too good\", he said.")
   local s = stream(buf)
   assert.equals(s:read_until('"'), "")
   assert.equals(s:read_until('"'), "This is not too good")
end)
