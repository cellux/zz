local testing = require('testing')('globals')
local assert = require('assert')
local process = require('process')
local ffi = require('ffi')
local net = require('net')
local sched = require('sched')
local stream = require('stream')

testing("sf", function()
   assert.equals(sf("Hello, %s", "world"), "Hello, world")
end)

testing:nosched("pf", function()
   local sp, sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM, 0)
   local pid = process.fork()
   if pid == 0 then
      -- child
      sp:close()
      ffi.C.dup2(sc.fd, 1)
      pf("Hello, %s\n", "world")
      sc:close()
      process.exit()
   else
      -- parent
      sc:close()
      sp = stream(sp)
      assert.equals(sp:read(13), "Hello, world\n")
      sp:close()
      process.waitpid(pid)
   end
end)

testing:nosched("ef", function()
   local test_path = debug.getinfo(1,"S").short_src
   local status, err = pcall(function() ef("Hello, %s", "world") end)
   assert.equals(status, false)
   assert.type(err, "string")
   assert.equals(err, sf("%s:35: Hello, world", test_path))

   -- if we throw an error from a coroutine running inside the scheduler,
   -- we'd like to get a valid backtrace which correctly shows where the
   -- error happened
   
   local function throwit()
      ef("Hello, %s", "world")
   end
   sched(function() throwit() end)
   local status, err = pcall(sched)
   assert.equals(status, false)
   assert.type(err, "string")
   -- we check only the first part of the error
   --
   -- the second part contains the global (non-coroutine-specific)
   -- traceback appended by error()
   local expected = test_path..[[:45: Hello, world
stack traceback:
	]]..test_path..[[:45: in function 'throwit'
	]]..test_path..[[:47: in function <]]..test_path..[[:47>]]
   assert.equals(err:sub(1,#expected), expected)
end)
