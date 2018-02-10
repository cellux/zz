local net = require('net')
local assert = require('assert')
local process = require('process')
local buffer = require('buffer')
local stream = require('stream')
local fs = require('fs')
local ffi = require('ffi')
local util = require('util')
local sched = require('sched')
local epoll = require('epoll')
local digest = require('digest')

-- open/close

assert.equals(net.PF_LOCAL, 1)
assert.equals(net.SOCK_DGRAM, 2)
local s = net.socket(net.PF_LOCAL, net.SOCK_DGRAM)
assert.type(s.fd, "number")
assert(s.fd > 0)
assert.equals(s:close(), 0)

-- shutdown
local s = net.socket(net.PF_LOCAL, net.SOCK_DGRAM)
assert.equals(s:shutdown(net.SHUT_RD), 0)
assert.equals(s:shutdown(net.SHUT_WR), 0)
assert.equals(s:close(), 0)

local s = net.socket(net.PF_LOCAL, net.SOCK_DGRAM)
assert.equals(s:shutdown(net.SHUT_RDWR), 0)
assert.equals(s:close(), 0)

-- socketpair
local s1, s2 = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM)
assert(s1 ~= nil)
assert(s2 ~= nil)
s1:write("hello")
assert.equals(s2:read(5), "hello")
s2:write("world")
assert.equals(s1:read(5), "world")
s1:close()
s2:close()

-- socket read/write using streams
local s1, s2 = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM)
assert(s1 ~= nil)
assert(s2 ~= nil)
local f = fs.open("testdata/arborescence.jpg")
local s_f = stream(f)
sched(function()
   local s = stream(s1)
   while not s_f:eof() do
      s:write(s_f:read())
   end
   s1:close() -- otherwise the other side gets stuck in poll
end)
local buf = buffer.new()
sched(function()
   local s = stream(s2)
   while not s:eof() do
      buf:append(s:read())
   end
   s2:close()
end)
sched()
f:close()
assert.equals(util.hexstr(digest.md5(buf)), '58823f6d5e1d154d37d9aa2dbaf27371')

-- IPC using socketpair
local sp, sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM)
local pid = process.fork()
if pid == 0 then
   -- child
   sp:close()
   assert.equals(sc:read(5), "hello")
   sc:write("world")
   assert.equals(sc:read(), "quit")
   sc:close()
   process.exit(0)
else
   -- parent
   sc:close()
   sp:write("hello")
   assert.equals(sp:read(5), "world")
   sp:write("quit")
   sp:close()
   -- closing sp causes an EOF condition on sc in the child
   -- at this point, sc:read() returns and the child exits
   process.waitpid(pid)
end

-- IPC using socketpair with line-oriented protocol
local sp, sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM)
local pid = process.fork()
if pid == 0 then
   -- child
   sp:close()
   local s = stream(sc)
   assert.equals(s:readln(), "hello")
   s:writeln("world")
   assert.equals(s:readln(), "quit")
   -- check that plain read() still works
   assert.equals(s:read(10), "extra-data")
   sc:close()
   process.exit()
else
   -- parent
   sc:close()
   local s = stream(sp)
   s:writeln("hello")
   -- sending quit immediately after hello shouldn't confuse the child
   s:writeln("quit")
   assert.equals(s:readln(), "world")
   s:write("extra-data")
   process.waitpid(pid)
   sp:close()
end

-- sockaddr

local socket_addr = net.sockaddr(net.AF_LOCAL, "/tmp/socket")
assert.equals(socket_addr.address, "/tmp/socket")
assert.equals(tostring(socket_addr), "/tmp/socket")

local socket_addr = net.sockaddr(net.AF_INET, "127.0.0.1", 54321)
assert.equals(socket_addr.address, "127.0.0.1")
assert.equals(socket_addr.port, 54321)
assert.equals(tostring(socket_addr), "127.0.0.1:54321")

local socket_addr_1 = net.sockaddr(net.AF_INET, "127.0.0.1", 54321)
local socket_addr_2 = net.sockaddr(net.AF_INET, "127.0.0.1", 54321)
assert(socket_addr_1 == socket_addr_2)

-- listen, accept, connect (with local sockets)

local socket_path = fs.mktemp("zzlua-test-socket")
local socket_addr = net.sockaddr(net.AF_LOCAL, socket_path)

local pid, sp = process.fork(function(sc)
   assert.equals(sc:read(13), "server-ready\n")
   function send(msg)
      local client = net.socket(net.PF_LOCAL, net.SOCK_STREAM)
      client:connect(socket_addr)
      local cs = stream(client)
      cs:writeln(msg)
      assert.equals(cs:readln(), msg)
      client:close()
   end
   send("hello, world!")
   send("quit")
   -- process.fork() will close sc for us
end)

local server = net.socket(net.PF_LOCAL, net.SOCK_STREAM)
server.SO_REUSEADDR = true
server:bind(socket_addr)
server:listen()
sp:write("server-ready\n")
while true do
   local client = server:accept()
   local cs = stream(client)
   local msg = cs:readln()
   cs:writeln(msg)
   client:close()
   if msg == "quit" then
      break
   end
end
server:close()
sp:close()
process.waitpid(pid)

if fs.exists(socket_path) then
   fs.unlink(socket_path)
end

-- listen, accept, connect (with TCP sockets)
-- getsockname, getpeername

local server_host, server_port = "127.0.0.1", 54321
local server_addr = net.sockaddr(net.AF_INET, server_host, server_port)

local pid, sp = process.fork(function(sc)
      assert.equals(sc:read(13), "server-ready\n")
      function send(msg)
         local client = net.socket(net.PF_INET, net.SOCK_STREAM)
         client:connect(server_addr)
         local client_addr = client:getsockname()
         assert.equals(client_addr.address, "127.0.0.1")
         assert.type(client_addr.port, "number")
         local cs = stream(client)
         cs:writeln(client_addr.address)
         cs:writeln(client_addr.port)
         cs:writeln(msg)
         assert.equals(cs:readln(), msg)
         client:close()
      end
      send("hello, world!")
      send("quit")
end)

local server = net.socket(net.PF_INET, net.SOCK_STREAM)
server.SO_REUSEADDR = true
server:bind(server_addr)
server:listen()
sp:write("server-ready\n")
while true do
   local client = server:accept()
   local peer_addr = client:getpeername()
   local cs = stream(client)
   local peer_address = cs:readln()
   assert.equals(peer_address, "127.0.0.1")
   assert.equals(peer_address, peer_addr.address)
   local peer_port = tonumber(cs:readln())
   assert.equals(peer_port, peer_addr.port)
   local msg = cs:readln()
   cs:writeln(msg)
   client:close()
   if msg == "quit" then
      break
   end
end
server:close()
sp:close()
process.waitpid(pid)

-- sendto

local dst_addr = net.sockaddr(net.AF_INET, "127.0.0.1", 54321)
local s = net.socket(net.PF_INET, net.SOCK_DGRAM)
s:sendto("this message should be dropped to the floor", dst_addr)
s:close()

-- UDP sockets

local server_host, server_port = "127.0.0.1", 54321
local server_addr = net.sockaddr(net.AF_INET, server_host, server_port)

local pid, sp = process.fork(function(sc)
      assert.equals(sc:read(13), "server-ready\n")
      function send(msg)
         local client = net.socket(net.PF_INET, net.SOCK_DGRAM)
         client:sendto(msg, server_addr)
         local reply, peer_addr = client:recvfrom()
         assert.equals(reply, msg)
         assert.equals(peer_addr.address, "127.0.0.1")
         assert.equals(peer_addr.port, 54321)
         client:close()
      end
      send("hello, world!")
      send("quit")
end)

local server = net.socket(net.PF_INET, net.SOCK_DGRAM)
server.SO_REUSEADDR = true
server:bind(server_addr)
--server:listen() -- not supported by SOCK_DGRAM style sockets
sp:write("server-ready\n")
while true do
   -- local client = server:accept() -- not supported
   local msg, peer_addr = server:recvfrom()
   assert.equals(peer_addr.address, "127.0.0.1")
   assert(type(peer_addr.port)=="number")
   server:sendto(msg, peer_addr)
   if msg == "quit" then
      break
   end
end
server:close()
sp:close()
process.waitpid(pid)

-- a TCP server

local server_host, server_port = "127.0.0.1", 54321
local server_addr = net.sockaddr(net.AF_INET, server_host, server_port)

local n_req = 500 -- number of requests to send within a second

local requests = {}

-- generate a bunch of numerical expressions
--
-- the server will read the expression and reply with the evaluated
-- result

local function make_expr(sub_expr)
   if not sub_expr then
      return make_expr(tostring(math.random(10)))
   elseif #sub_expr > 20 then
      return sub_expr
   else
      local ops = "+-*" -- no / to avoid division by zero
      local i = math.random(#ops)
      local op = string.sub(ops,i,i)
      local lhs = sub_expr
      local rhs = tostring(math.random(10))
      if math.random() >= 0.5 then
         lhs, rhs = rhs, lhs
      end
      return make_expr(sf("(%s%s%s)", lhs, op, rhs))
   end
end

for i=1,n_req do
   table.insert(requests, make_expr())
end

local responses = {}

local function server()
   local socket = net.socket(net.PF_INET, net.SOCK_STREAM)
   socket.SO_REUSEADDR = true
   socket:bind(server_addr)
   socket:listen()
   for i=1,n_req do
      local client = socket:accept()
      sched(function()
            local peer_addr = client:getpeername()
            local cs = stream(client)
            local expr = cs:readln()
            local chunk = assert(loadstring("return "..expr))
            local value = tostring(chunk())
            cs:writeln(value)
            client:close()
      end)
   end
   socket:close()
end

sched(server)

local function client(expr)
   -- distribute client requests evenly within one second
   sched.sleep(math.random())
   local client = net.socket(net.PF_INET, net.SOCK_STREAM)
   client:connect(server_addr)
   local cs = stream(client)
   cs:writeln(expr)
   local response = cs:readln()
   client:close()
   responses[expr] = response
end

for i=1,n_req do
   sched(client, requests[i])
end

sched()

for e,v in pairs(responses) do
   assert.equals(tostring(assert(loadstring("return "..e))()), v)
end

-- graceful way to shut down a network server:

local server_host, server_port = "127.0.0.1", 54321
local server_addr = net.sockaddr(net.AF_INET, server_host, server_port)

local tcp_server_gracefully_shut_down = false

local function tcp_server(s)
   s.SO_REUSEADDR = true
   s:bind(server_addr)
   s:listen()
   net.qpoll(s.fd, function()
      local client_fd = s:accept()
      -- handle connection
   end)
   s:close()
   tcp_server_gracefully_shut_down = true
end

local s = net.socket(net.PF_INET, net.SOCK_STREAM)
sched(tcp_server, s)
sched(function() sched.quit() end)
sched()
assert.equals(tcp_server_gracefully_shut_down, true)

-- connecting an UDP socket to the broadcast address and then calling
-- getsockname() on it returns the IP address of the interface which
-- would be used to send outgoing packets

local s = net.socket(net.PF_INET, net.SOCK_DGRAM)
s.SO_BROADCAST = true
local broadcast_addr = net.sockaddr(net.AF_INET, "255.255.255.255", 54321)
s:connect(broadcast_addr)
assert.type(s:getsockname().port, "number")
assert(string.match(s:getsockname().address, '^%d+%.%d+%.%d+%.%d+$'))
s:close()

-- TCPListener, UDPListener

local server_host, server_port = "127.0.0.1", 54321
local server_addr = net.sockaddr(net.AF_INET, server_host, server_port)

local function test_listener(Listener, socket_type)
   local function server()
      local listener = Listener {
         address = server_host,
         port = server_port,
         server = function(stream)
            assert.equals(stream:read(), "ping")
            stream:write("pong")
         end,
      }
      listener:start()
   end
   local nclients = 10
   local function client()
      local client = net.socket(net.PF_INET, socket_type)
      client:connect(server_addr)
      client:write("ping")
      assert.equals(client:read(4), "pong")
      client:close()
      nclients = nclients - 1
      if nclients == 0 then
         sched.quit()
      end
   end
   sched(server)
   for i=1,nclients do
      sched(client)
   end
   sched()
end

test_listener(net.TCPListener, net.SOCK_STREAM)
test_listener(net.UDPListener, net.SOCK_DGRAM)
