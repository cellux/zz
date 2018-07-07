local testing = require('testing')('net')
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

testing("open, close", function()
   assert.equals(net.PF_LOCAL, 1)
   assert.equals(net.SOCK_DGRAM, 2)
   local s = net.socket(net.PF_LOCAL, net.SOCK_DGRAM)
   assert.type(s.fd, "number")
   assert(s.fd > 0)
   assert.equals(s:close(), 0)
end)

testing("shutdown", function()
   local s = net.socket(net.PF_LOCAL, net.SOCK_DGRAM)
   assert.equals(s:shutdown(net.SHUT_RD), 0)
   assert.equals(s:shutdown(net.SHUT_WR), 0)
   assert.equals(s:close(), 0)
   
   local s = net.socket(net.PF_LOCAL, net.SOCK_DGRAM)
   assert.equals(s:shutdown(net.SHUT_RDWR), 0)
   assert.equals(s:close(), 0)
end)

testing("socketpair", function()
   local s1, s2 = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM)
   assert(s1 ~= nil)
   assert(s2 ~= nil)
   s1 = stream(s1)
   s2 = stream(s2)
   s1:write("hello")
   assert.equals(s2:read(5), "hello")
   s2:write("world")
   assert.equals(s1:read(5), "world")
   s1:close()
   s2:close()
end)

testing("socket read/write using streams", function()
   local s1, s2 = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM)
   assert(s1 ~= nil)
   assert(s2 ~= nil)
   local f = fs.open("testdata/arborescence.jpg")
   local buf = buffer.new()
   sched.join {
      stream.pipe(f, s1),
      stream.pipe(s2, buf),
   }
   assert.equals(util.hexstr(digest.md5(buf)), '58823f6d5e1d154d37d9aa2dbaf27371')
end)

testing:nosched("IPC using socketpair", function()
   local pid, sp = process.fork(function(sc)
      -- child
      assert.equals(sc:read(5), "hello")
      sc:write("world")
      assert.equals(sc:read(), "quit")
   end)
   -- parent
   sp:write("hello")
   assert.equals(sp:read(5), "world")
   sp:write("quit")
   sp:close()
   -- closing sp causes an EOF condition on sc in the child
   -- at this point, sc:read() returns and the child exits
   process.waitpid(pid)
end)

testing:nosched("IPC using socketpair with line-oriented protocol", function()
   local pid, sp = process.fork(function(sc)
      -- child
      assert.equals(sc:readln(), "hello")
      sc:writeln("world")
      assert.equals(sc:readln(), "quit")
      -- check that plain read() still works
      assert.equals(sc:read(10), "extra-data")
   end)
   -- parent
   sp:writeln("hello")
   -- sending quit immediately after hello shouldn't confuse the child
   sp:writeln("quit")
   assert.equals(sp:readln(), "world")
   sp:write("extra-data")
   process.waitpid(pid)
   sp:close()
end)

testing("sockaddr", function()
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
end)

testing:nosched("listen, accept, connect (with local sockets)", function()
   local socket_path = fs.mktemp("zz-net-test-socket")
   local socket_addr = net.sockaddr(net.AF_LOCAL, socket_path)

   local pid, sp = process.fork(function(sc)
      assert.equals(sc:read(13), "server-ready\n")
      function send(msg)
         local client = net.socket(net.PF_LOCAL, net.SOCK_STREAM)
         client:connect(socket_addr)
         local cs = stream(client)
         cs:writeln(msg)
         assert.equals(cs:readln(), msg)
         cs:close()
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
      cs:close()
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
end)

testing:nosched("listen, accept, connect (with TCP sockets), getsockname, getpeername", function(t)
   local server_host, server_port = "127.0.0.1", 54321 + t:nextid()
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
         cs:close()
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
      cs:close()
      if msg == "quit" then
         break
      end
   end
   server:close()
   sp:close()
   process.waitpid(pid)
end)
   
testing("sendto", function(t)
   local dst_addr = net.sockaddr(net.AF_INET, "127.0.0.1", 54321 + t:nextid())
   local s = net.socket(net.PF_INET, net.SOCK_DGRAM)
   s:sendto("this message should be dropped to the floor", dst_addr)
   s:close()
end)

testing:nosched("UDP sockets", function(t)
   local server_host, server_port = "127.0.0.1", 54321 + t:nextid()
   local server_addr = net.sockaddr(net.AF_INET, server_host, server_port)

   local pid, sp = process.fork(function(sc)
      assert.equals(sc:read(13), "server-ready\n")
      function send(msg)
         local client = net.socket(net.PF_INET, net.SOCK_DGRAM)
         client:sendto(msg, server_addr)
         local reply, peer_addr = client:recv()
         assert.equals(reply, msg)
         assert.equals(peer_addr.address, server_host)
         assert.equals(peer_addr.port, server_port)
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
      local msg, peer_addr = server:recv()
      assert.equals(peer_addr.address, server_host)
      assert(type(peer_addr.port)=="number")
      server:sendto(msg, peer_addr)
      if msg == "quit" then
         break
      end
   end
   server:close()
   sp:close()
   process.waitpid(pid)
end)

testing("tcp server", function(t)
   local server_host, server_port = "127.0.0.1", 54321 + t:nextid()
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
            cs:close()
         end)
      end
      socket:close()
   end

   local server_thread = sched(server)
   
   local function client(expr)
      -- distribute client requests evenly within one second
      sched.sleep(math.random())
      local client = net.socket(net.PF_INET, net.SOCK_STREAM)
      client:connect(server_addr)
      local cs = stream(client)
      cs:writeln(expr)
      local response = cs:readln()
      cs:close()
      responses[expr] = response
   end
   
   local client_threads = {}
   for i=1,n_req do
      table.insert(client_threads, sched(client, requests[i]))
   end
   sched.join(client_threads)

   for e,v in pairs(responses) do
      assert.equals(tostring(assert(loadstring("return "..e))()), v)
   end
end)

testing:nosched("a graceful way to shut down a network server", function(t)
   local server_host, server_port = "127.0.0.1", 54321 + t:nextid()
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
end)

-- connecting an UDP socket to the broadcast address and then calling
-- getsockname() on it returns the IP address of the interface which
-- would be used to send outgoing packets

testing("getsockname() on UDP socket connected to broadcast address", function(t)
   local s = net.socket(net.PF_INET, net.SOCK_DGRAM)
   s.SO_BROADCAST = true
   local broadcast_addr = net.sockaddr(net.AF_INET, "255.255.255.255", 54321 + t:nextid())
   s:connect(broadcast_addr)
   assert.type(s:getsockname().port, "number")
   assert(string.match(s:getsockname().address, '^%d+%.%d+%.%d+%.%d+$'))
   s:close()
end)

testing:nosched("TCPListener, UDPListener", function(t)
   local server_host, server_port = "127.0.0.1", 54321 + t:nextid()
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
         local cs = stream(client)
         cs:write("ping")
         assert.equals(cs:read(4), "pong")
         cs:close()
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
end)
