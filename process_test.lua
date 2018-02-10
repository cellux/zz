local process = require('process')
local ffi = require('ffi')
local assert = require('assert')
local fs = require('fs') -- for dup2
local net = require('net')

-- getpid

local ppid = process.getpid()
assert(type(ppid) == "number")

-- fork, waitpid

local sp, sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM, 0)
local pid = process.fork()
assert(type(pid)=="number")
if pid == 0 then
   -- child
   sp:close()
   sc:write(sf("%u\n", process.getpid()))
   sc:close()
   assert(process.getpid() ~= ppid)
   process.exit()
else
   -- parent
   sc:close()
   assert(process.getpid() == ppid)
   local child_pid = tonumber(sp:read())
   sp:close()
   assert.equals(child_pid, pid)
   assert.equals(process.waitpid(pid), pid)
end

-- the same, using some sugar

local pid, sp = process.fork(function(sc)
   sc:write(sf("%u\n", process.getpid()))
   sc:close()
   assert(process.getpid() ~= ppid)
end)
assert(process.getpid() == ppid)
local child_pid = tonumber(sp:read())
sp:close()
assert.equals(child_pid, pid)
assert.equals(process.waitpid(pid), pid)

-- system

local sp, sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM, 0)
local pid = process.fork()
if pid == 0 then
   sp:close()
   -- redirect command's stdout to parent through socket
   assert.equals(ffi.C.dup2(sc.fd, 1), 1)
   process.system("echo hello; echo world")
   sc:close()
   process.exit()
else
   sc:close()
   -- read(0) means read until EOF
   assert.equals(sp:read(0), "hello\nworld\n")
   sp:close()
   assert.equals(process.waitpid(pid), pid)
end

-- execvp

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
   assert.equals(sp:read(), "hello world!\n")
   sp:close()
   assert.equals(process.waitpid(pid), pid)
end

-- waitpid, exit

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

-- chdir, getcwd

local pid = process.fork()
if pid == 0 then
   process.chdir("/tmp")
   assert.equals(process.getcwd(), "/tmp")
   process.exit()
else
   process.waitpid(pid)
end
