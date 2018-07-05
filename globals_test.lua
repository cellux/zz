local testing = require('testing')('globals')
local assert = require('assert')
local process = require('process')
local ffi = require('ffi')
local net = require('net')
local sched = require('sched')
local stream = require('stream')
local util = require('util')

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
   assert(util.is_error(err))
   assert.equals(tostring(err), "Hello, world")

   -- if we throw an error from a coroutine running inside the scheduler,
   -- we'd like to get a valid traceback which correctly shows where the
   -- error happened

   local function throwit()
      ef("Hello, %s", "world")
   end
   sched(function() throwit() end)
   local status, err = pcall(sched)
   assert.equals(status, false)
   assert(util.is_error(err))
   assert.equals(tostring(err), "Hello, world")
   local expected_traceback = [[Hello, world
stack traceback:
	]]..test_path..[[:46: in function 'throwit'
	]]..test_path..[[:48: in function <]]..test_path..[[:48>]]
   assert.equals(err.traceback, expected_traceback)
end)
