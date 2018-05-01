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

testing("execvp", function()
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
   local pid, sp = process.fork(function()
      process.chdir("/tmp")
      assert.equals(process.getcwd(), "/tmp")
   end)
   process.waitpid(pid)
   sp:close()
end)

testing:nosched("exit", function()
   local pid, sp = process.fork(function()
      process.exit(84)
   end)
   sp:close()
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

testing("start", function()
   local p = process.start {
      command = "true"
   }
   -- p.pid is the process id of the started subprocess
   assert.type(p.pid, "number")
   -- p:wait() waits for the process to exit
   local rv = p:wait()
   -- p:wait() returns self to ease chaining
   assert.equals(rv, p)
   assert.equals(p.exit_status, 0)
   assert.equals(p.term_signal, 0)

   local p = process.start {
      command = "false"
   }
   p:wait()
   assert.equals(p.exit_status, 1)
   assert.equals(p.term_signal, 0)
end)

testing("start with args and pre_exec", function()
   local sp, sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM, 0)
   local p = process.start {
      command = { "echo", "hello", "world" },
      pre_exec = function()
         sp:close()
         -- redirect stdout of child into sc
         assert.equals(ffi.C.dup2(sc.fd, 1), 1)
         -- sc will be closed automatically when the subprocess exits
      end
   }
   sc:close()
   p:wait()
   assert.equals(stream(sp):readln(), "hello world")
   sp:close()
end)

testing("start with capture", function()
   local p = process.start {
      command = "echo 'hello world'; echo -n 'bad' >&2",
      stdout = "capture",
      stderr = "capture",
   }
   p:wait()
   assert.equals(p.stdout, "hello world\n")
   assert.equals(p.stderr, "bad")
end)

testing("start with a string on stdin", function()
   local p = process.start {
      command = { "sed", "-e", "s/Joe/Mike/" },
      stdin = "Hello, Joe\n",
      stdout = "capture",
   }
   p:wait()
   assert.equals(p.stdout, "Hello, Mike\n")
end)

testing("system", function()
   local status = process.system("exit 123")
   assert.equals(status, 123)
end)

testing("capture", function()
   -- a string argument is passed to the system shell
   local status, stdout, stderr = process.capture("(echo hello; echo world) | tr a-z A-Z")
   assert.equals(status, 0)
   assert.equals(stdout, "HELLO\nWORLD\n")
   assert.equals(stderr, "")

   -- a table argument is executed via execvp()
   local status, stdout, stderr = process.capture {
      "bash", "-c",
      "(echo hello; echo world >&2) | tr a-z A-Z"
   }
   assert.equals(status, 0)
   assert.equals(stdout, "HELLO\n")
   assert.equals(stderr, "world\n")

   local status, stdout, stderr = process.capture("exit 123")
   assert.equals(status, 123)
   assert.equals(stdout, "")
   assert.equals(stderr, "")
end)

testing("process groups", function()
   local pg = process.Group()
   local echo = pg:create {
      command = { "echo", "Hello, Joe" }
   }
   local sed = pg:create {
      command = { "sed", "-e", "s/Joe/Mike/" },
      stdin = echo.stdout,
      stdout = "capture"
   }
   pg:wait()
   assert.equals(sed.stdout, "Hello, Mike\n")
end)
