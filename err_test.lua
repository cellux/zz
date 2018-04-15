local testing = require('testing')
local err = require('err')
local assert = require('assert')

testing("err", function()
   local e = err(1234, "this is an error message")
   assert.equals(e.code, 1234)
   assert.equals(e.msg, "this is an error message")
   assert.equals(tostring(e), "this is an error message (1234)")
end)

