local testing = require('testing')('process')
local process = require('process')
local signal = require('signal')
local ffi = require('ffi')
local assert = require('assert')
local fs = require('fs')
local net = require('net')
local stream = require('stream')

testing("getpid", function()
   local pid = process.getpid()
   assert.type(pid, "number")
   assert(pid > 0)
end)

-- forking while the scheduler is running is a non-trivial operation
--
-- thus :nosched which executes this test before scheduler startup

testing:nosched("getpid, fork, waitpid", function()
   local parent_pid = process.getpid()
   assert.type(parent_pid, "number")
   local sp, sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM, 0)
   local pid = process.fork()
   assert.type(pid, "number")
   if pid == 0 then
      -- child
      sp:close()
      local child_pid = process.getpid()
      assert(child_pid ~= parent_pid)
      stream(sc):write(sf("%u\n", child_pid))
      sc:close()
      process.exit()
   else
      -- parent
      sc:close()
      assert(process.getpid() == parent_pid)
      local child_pid = tonumber(stream(sp):readln())
      sp:close()
      assert.equals(child_pid, pid)
      assert.equals(process.waitpid(pid), pid)
   end
end)

-- the same as above, using some sugar:

testing:nosched("fork(child_fn)", function()
   local parent_pid = process.getpid()
   local pid, sp = process.fork(function(sc)
      -- child
      -- sp has been closed for us
      assert(process.getpid() ~= parent_pid)
      -- sc is already a stream
      assert(stream.is_stream(sc))
      sc:write(sf("%u\n", process.getpid()))
      -- sc:close() and process.exit() will be called
   end)
   -- parent
   -- sc has been closed for us
   assert(process.getpid() == parent_pid)
   assert(stream.is_stream(sp))
   local child_pid = tonumber(sp:readln())
   sp:close()
   assert.equals(child_pid, pid)
   assert.equals(process.waitpid(pid), pid)
end)

testing:nosched("execvp", function()
   local pid, sp = process.fork(function(sc)
      -- redirect command's stdout to parent through socket
      assert.equals(ffi.C.dup2(sc.fd, 1), 1)
      process.execvp("echo", {"echo", "hello", "world!"})
      -- process.execvp() doesn't return
   end)
   assert.equals(sp:read(0), "hello world!\n")
   sp:close()
   assert.equals(process.waitpid(pid), pid)
end)

testing:nosched("system", function()
   local pid, sp = process.fork(function(sc)
      -- redirect command's stdout to parent through socket
      assert.equals(ffi.C.dup2(sc.fd, 1), 1)
      -- a string argument is passed to the system shell
      local status = process.system("(echo hello; echo world) | tr a-z A-Z")
      assert.equals(status, 0)
      -- a table argument is executed via execvp()
      local status = process.system { "bash", "-c", "(echo hello; echo world) | tr a-z A-Z" }
      assert.equals(status, 0)
      local status = process.system "exit 123"
      assert.equals(status, 123)
   end)
   -- read(0) means read until EOF
   assert.equals(sp:read(0), "HELLO\nWORLD\n".."HELLO\nWORLD\n")
   sp:close()
   assert.equals(process.waitpid(pid), pid)
end)

testing:nosched("kill, waitpid", function()
   local pid, sp = process.fork(function(sc)
     assert.equals(sc:readln(), "prepare")
     sc:read() -- blocks until SIGTERM
   end)
   sp:writeln("prepare")
   -- kill with signal 0 can be used to check if a process exists
   assert.equals(process.kill(pid, 0), 0)
   assert.equals(process.kill(pid, signal.SIGTERM), 0)
   local wpid, ret, sig = process.waitpid(pid)
   assert.equals(wpid, pid) -- pid of the process which terminated
   assert.equals(ret, 0) -- value returned from main()
   assert.equals(sig, signal.SIGTERM) -- terminating signal
   sp:close()
end)

testing:nosched("getcwd, chdir", function()
   local pid = process.fork(function()
      process.chdir("/tmp")
      assert.equals(process.getcwd(), "/tmp")
   end)
   process.waitpid(pid)
end)

testing:nosched("exit", function()
   local pid = process.fork(function()
      process.exit(84)
   end)
   local rv, ret, sig = process.waitpid(pid)
   assert.equals(rv, pid)
   assert.equals(ret, 84) -- return value
   assert.equals(sig, 0) -- normal termination
end)

testing:exclusive("umask", function()
   -- umask() without arguments returns the current umask
   local old_umask = process.umask()
   local new_umask = tonumber("077", 8)
   -- umask(x) sets the current umask and returns the previous one
   assert.equals(process.umask(new_umask), old_umask)
   assert.equals(process.umask(), new_umask)
   local tmpdir = sf("/tmp/process_test_%d", process.getpid())
   assert.equals(fs.mkdir(tmpdir, tonumber("777", 8)), 0)
   assert(fs.is_dir(tmpdir))
   assert.equals(fs.stat(tmpdir).perms, tonumber("700", 8))
   assert.equals(fs.rmdir(tmpdir), 0)
   assert.equals(process.umask(old_umask), new_umask)
   assert.equals(process.umask(), old_umask)
end)
