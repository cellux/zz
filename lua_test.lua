local testing = require('testing')('lua')
local assert = require('assert')

testing('error', function()
   local function with_error_position()
      error("message")
   end
   local ok, err = pcall(with_error_position)
   assert.is_false(ok)
   -- "Usually, error adds some information about the error position
   -- at the beginning of the message."
   assert.match("^\\S+/lua_test\\.lua:\\d+: message$", err)

   -- "Passing a level 0 avoids the addition of error position information to the message."
   local function without_error_position()
      error("message", 0)
   end
   local ok, err = pcall(without_error_position)
   assert.is_false(ok)
   assert.equals(err, "message")
end)

testing('VM errors', function()
   local function thrower()
      local t = {}
      t.a.b = 5
   end
   local ok, err = pcall(thrower)
   assert.is_false(ok)
   assert.match("^\\S+/lua_test\\.lua:\\d+: attempt to index field 'a' \\(a nil value\\)$", err)
end)

testing('xpcall', function()
   local function thrower()
      local t = {}
      t.a.b = 5
   end
   local function error_handler(err)
      -- this function executes at the same stack level as thrower
      -- it can retrieve all kinds of information from the context
      local info = debug.getinfo(1)
      info.message = err
      info.traceback = debug.traceback("TRACEBACK_MESSAGE", 2)
      return info
   end
   local ok, err = xpcall(thrower, error_handler)
   assert.is_false(ok)
   assert.type(err, "table")
   assert.type(err.currentline, "number")
   assert.type(err.source, "string")
   assert.match("^\\S+/lua_test\\.lua$", err.source)
   assert.match("^\\S+/lua_test\\.lua:\\d+: attempt to index field 'a' \\(a nil value\\)$", err.message)
   assert.match("^TRACEBACK_MESSAGE\\s+stack traceback:", err.traceback)
end)
