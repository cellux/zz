local testing = require('testing')('nanomsg')
local nn = require('nanomsg')
local ffi = require('ffi')
local time = require('time')
local sched = require('sched')
local process = require('process')
local assert = require('assert')
local sf = string.format

local function isnumber(x)
   return type(x) == "number"
end

testing("pubsub", function(t)
   local endpoint = sf("inproc://pubsub%d", t:nextid())

   local sub_sock = nn.socket(nn.AF_SP, nn.SUB)
   nn.setsockopt(sub_sock, nn.SUB, nn.SUB_SUBSCRIBE, "")
   nn.connect(sub_sock, endpoint)

   local pub_sock = nn.socket(nn.AF_SP, nn.PUB)
   nn.bind(pub_sock, endpoint)
   nn.send(pub_sock, "hello")
   
   local poll = nn.Poll()
   poll:add(sub_sock, nn.POLLIN) -- socket, events
   assert(#poll.items == 1)
   local nevents = poll(-1) -- timeout in ms, -1=block
   assert(nevents == 1, sf("poll() returned nevents=%d, expected 1", nevents))
   assert(poll[0].revents == nn.POLLIN)
   local buf = nn.recv(sub_sock)
   assert(buf=="hello")
   
   nn.close(pub_sock)
   nn.close(sub_sock)
end)

testing("subscriber does not see published messages until connection is established", function(t)
   local address = sf("tcp://127.0.0.1:%d", 54321 + t:nextid())

   local pub_sock = nn.socket(nn.AF_SP, nn.PUB)
   nn.bind(pub_sock, address)
   
   local sub_sock = nn.socket(nn.AF_SP, nn.SUB)
   nn.setsockopt(sub_sock, nn.SUB, nn.SUB_SUBSCRIBE, "")
   nn.connect(sub_sock, address)
   
   -- after the connect and the bind, there is a time period while the
   -- connection gets established. during this period, messages sent to
   -- the pub socket are permanently lost.
   
   nn.send(pub_sock, "hello")
   assert(nn.recv(sub_sock, nn.DONTWAIT)==nil)
   
   nn.close(sub_sock)
   nn.close(pub_sock)
end)

testing("tcp with handshake", function(t)
   local address = sf("tcp://127.0.0.1:%d", 54321 + t:nextid())
   local n_messages = 10

   local pub_sock = nn.socket(nn.AF_SP, nn.PUB)
   nn.bind(pub_sock, address)

   local sub_sock = nn.socket(nn.AF_SP, nn.SUB)
   nn.setsockopt(sub_sock, nn.SUB, nn.SUB_SUBSCRIBE, "")
   nn.connect(sub_sock, address)
      
   local handshake_done = false
   
   sched(function()
         while not handshake_done do
            nn.send(pub_sock, "ping")
            sched.sleep(0.1)
         end
   end)
   
   -- wait for the first message to arrive
   local sub_sock_fd = nn.getsockopt(sub_sock, 0, nn.RCVFD)
   sched.poll(sub_sock_fd, "r")
   assert(nn.recv(sub_sock)=="ping")
   handshake_done = true
      
   -- from now on, all messages will be delivered (but pub/sub is
   -- inherently unreliable, so there is no real guarantee)
   local messages = {}
   local message_collector = sched(function()
         while #messages < n_messages do
            sched.poll(sub_sock_fd, "r")
            local msg = nn.recv(sub_sock)
            if msg ~= "ping" then
               table.insert(messages, msg)
            end
         end
         assert(#messages==n_messages)
         nn.close(sub_sock)
   end)
   for i=1,n_messages do
      nn.send(pub_sock, sf("msg-%d", i))
   end
   sched.join(message_collector)
   nn.close(pub_sock)
end)

testing("tcp with handshake, 10 subscribers, 100 messages", function(t)
   local address = sf("tcp://127.0.0.1:%d", 54321 + t:nextid())
   local n_subscribers = 10
   local n_messages = 100
   
   local pub_sock = nn.socket(nn.AF_SP, nn.PUB)
   nn.bind(pub_sock, address)
   local n_connected = 0
   local subscribers = {}
   for i=1,n_subscribers do
      table.insert(subscribers, sched(function()
         local sub_sock = nn.socket(nn.AF_SP, nn.SUB)
         nn.setsockopt(sub_sock, nn.SUB, nn.SUB_SUBSCRIBE, "")
         nn.connect(sub_sock, address)
         -- wait for the first message to arrive
         local sub_sock_fd = nn.getsockopt(sub_sock, 0, nn.RCVFD)
         sched.poll(sub_sock_fd, "r")
         assert(nn.recv(sub_sock)=="ping")
         n_connected = n_connected + 1
         local messages = {}
         while #messages < n_messages do
            sched.poll(sub_sock_fd, "r")
            local msg = nn.recv(sub_sock)
            if msg ~= "ping" then
               table.insert(messages, msg)
            end
         end
         assert(#messages==n_messages)
         nn.close(sub_sock)
      end))
   end
   while n_connected < n_subscribers do
      nn.send(pub_sock, "ping")
      sched.sleep(0.1)
   end
   for i=1,n_messages do
      local msg = sf("msg-%d", i)
      nn.send(pub_sock, msg)
   end
   sched.join(subscribers)
   nn.close(pub_sock)
end)

testing:nosched("tcp with handshake, 10 subscribers in 10 subprocesses, 100 messages", function(t)
   local address = sf("tcp://127.0.0.1:%d", 54321 + t:nextid())
   local n_children = 10
   local n_messages = 100

   local function child_proc(sc)
      sched(function()
         local sub_sock = nn.socket(nn.AF_SP, nn.SUB)
         nn.setsockopt(sub_sock, nn.SUB, nn.SUB_SUBSCRIBE, "")
         nn.connect(sub_sock, address)
         -- wait for the first message to arrive
         local sub_sock_fd = nn.getsockopt(sub_sock, 0, nn.RCVFD)
         sched.poll(sub_sock_fd, "r")
         sc:write("got ping\n")
         -- from now on, all messages will be delivered (but pub/sub is
         -- inherently unreliable, so in theory, there is no guarantee)
         local messages = {}
         while #messages < n_messages do
            sched.poll(sub_sock_fd, "r")
            local msg = nn.recv(sub_sock)
            if msg ~= "ping" then
               table.insert(messages, msg)
            end
         end
         assert(#messages==n_messages)
         for i=1,n_messages do
            assert.equals(messages[i], sf("msg-%d", i))
         end
         nn.close(sub_sock)
      end)
      sched()
   end

   local children = {}
   for i=1,n_children do
      local pid,sp = process.fork(child_proc)
      children[pid] = sp
   end
   
   sched(function()
      local pub_sock = nn.socket(nn.AF_SP, nn.PUB)
      nn.bind(pub_sock, address)
      local n_connected = 0
      for pid,sp in pairs(children) do
         sched(function()
            assert.equals(sp:read(), "got ping\n")
            n_connected = n_connected + 1
         end)
      end
      while n_connected < n_children do
         nn.send(pub_sock, "ping")
         sched.sleep(0.1)
      end
      for i=1,n_messages do
         local msg = sf("msg-%d", i)
         nn.send(pub_sock, msg)
      end
      nn.close(pub_sock)
   end)
   sched()
   for pid,sp in pairs(children) do
      sp:close()
      process.waitpid(pid)
   end
end)
