local testing = require('testing')('env')
local env = require('env')
local assert = require('assert')
local process = require('process')
local ffi = require('ffi')
local fs = require('fs') -- for dup2
local net = require('net')

testing("env", function()
   assert.type(env.PATH, "string")
   assert(env.NONEXISTENT==nil)
   env.ZZ_ENV_TEST=5
   assert.type(env.ZZ_ENV_TEST, "string")
   assert.equals(env.ZZ_ENV_TEST, "5")

   local sp, sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM, 0)
   local pid = process.fork()
   if pid == 0 then
      -- child
      sp:close()
      assert.equals(ffi.C.dup2(sc.fd, 1), 1)
      env.ZZ_ENV_TEST=6
      process.execvp("sh", {"sh", "-c", 'echo "in the child, ZZ_ENV_TEST=$ZZ_ENV_TEST"'})
   else
      -- parent
      sc:close()
      assert.equals(env.ZZ_ENV_TEST, "5")
      assert.equals(sp:read(), "in the child, ZZ_ENV_TEST=6\n")
      sp:close()
      process.waitpid(pid)
   end
end)
