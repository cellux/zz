local testing = require('testing')('process')
local process = require('process')
local ffi = require('ffi')
local assert = require('assert')
local fs = require('fs') -- for dup2
local net = require('net')
local stream = require('stream')

testing:nosched("getpid, fork, waitpid", function()
   local ppid = process.getpid()
   assert(type(ppid) == "number")
   local sp, sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM, 0)
   local pid = process.fork()
   assert(type(pid)=="number")
   if pid == 0 then
      -- child
      sp:close()
      sc = stream(sc)
      assert(process.getpid() ~= ppid)
      sc:write(sf("%u\n", process.getpid()))
      sc:close()
      process.exit()
   else
      -- parent
      sc:close()
      sp = stream(sp)
      assert(process.getpid() == ppid)
      local child_pid = tonumber(sp:readln())
      sp:close()
      assert.equals(child_pid, pid)
      assert.equals(process.waitpid(pid), pid)
   end
end)

testing:nosched("process.fork(child_fn)", function()
   local ppid = process.getpid()
   local pid, sp = process.fork(function(sc)
      assert(process.getpid() ~= ppid)
      sc:write(sf("%u\n", process.getpid()))
   end)
   assert(process.getpid() == ppid)
   local child_pid = tonumber(sp:readln())
   sp:close()
   assert.equals(child_pid, pid)
   assert.equals(process.waitpid(pid), pid)
end)

testing:nosched("system", function()
   local sp, sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM, 0)
   local pid = process.fork()
   if pid == 0 then
      sp:close()
      -- redirect command's stdout to parent through socket
      assert.equals(ffi.C.dup2(sc.fd, 1), 1)
      -- a string argument is passed to the system shell
      local status = process.system("(echo hello; echo world) | tr a-z A-Z")
      assert.equals(status, 0)
      -- a table argument is executed via execvp()
      local status = process.system { "bash", "-c", "(echo hello; echo world) | tr a-z A-Z" }
      assert.equals(status, 0)
      local status = process.system "bash -c 'exit 123'"
      assert.equals(status, 123)
      sc:close()
      process.exit()
   else
      sc:close()
      sp = stream(sp)
      -- read(0) means read until EOF
      assert.equals(sp:read(0), "HELLO\nWORLD\n".."HELLO\nWORLD\n")
      sp:close()
      assert.equals(process.waitpid(pid), pid)
   end
end)

testing:nosched("execvp", function()
   local sp, sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM, 0)
   local pid = process.fork()
   if pid == 0 then
      sp:close()
      -- redirect command's stdout to parent through socket
      assert.equals(ffi.C.dup2(sc.fd, 1), 1)
      process.execvp("echo", {"echo", "hello", "world!"})
      -- doesn't return
   else
      sc:close()
      sp = stream(sp)
      assert.equals(sp:read(), "hello world!\n")
      sp:close()
      assert.equals(process.waitpid(pid), pid)
   end
end)

testing:nosched("waitpid, exit", function()
   local pid = process.fork()
   if pid == 0 then
      process.exit(84)
   else
      local rv, status = process.waitpid(pid)
      assert.equals(rv, pid)
      -- status is a 16-bit word
      -- high byte is the exit status
      -- low byte is the cause of termination (0 = normal exit)
      assert.equals(status, 84*256,
                    sf("expected=%x, actual=%x", 84*256, status))
   end
end)
   
testing:nosched("chdir, getcwd", function()
   local pid = process.fork()
   if pid == 0 then
      process.chdir("/tmp")
      assert.equals(process.getcwd(), "/tmp")
      process.exit()
   else
      process.waitpid(pid)
   end
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
