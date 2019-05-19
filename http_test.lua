local testing = require('testing')('http')
local assert = require('assert')
local http = require('http')
local net = require('net')
local sched = require('sched')

-- Hypertext Transfer Protocol (HTTP/1.1): Message Syntax and Routing
--
-- https://tools.ietf.org/html/rfc7230

-- 2. Architecture

testing("requests", function()
   local function with_sp(fn)
      local ss,sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM)
      fn(ss,sc)
      ss:close()
      sc:close()
   end
   with_sp(function(ss, sc)
      local function request_handler(req)
         assert.equals(req.method, "GET")
         assert.equals(req.uri, "/")
         assert.equals(req.http_version, "HTTP/1.1")
         assert.equals(req:header("host"), "www.example.com")
         assert.equals(req:header("hOsT"), "www.example.com")
         assert.equals(req.host, "www.example.com")
         assert.equals(req:header("Content-Length"), "0")
         assert.equals(req:header("content-length"), "0")
         assert.equals(req.content_length, 0)
         assert.equals(req:header("X-Color"), "red")
         assert.equals(req:header("X-String"), "abcd")
         assert.equals(req:header("X-Number"), "1234")
         assert.equals(req:header("X-Bool"), "true")
         return "Chihayafuru"
      end
      local server = http.StreamServer(ss, request_handler)
      assert(not server:running())
      server:start()
      sched.yield() -- server loop thread starts here
      assert(server:running())
      local req = http.Request {
         method = "GET",
         uri = "/",
         host = "www.example.com",
         headers = {
            ["X-Color"] = "red",
         }
      }
      assert.equals(req:header("X-Color"), "red")
      assert.is_nil(req:header("X-String"))
      req:header("X-String", "abcd")
      assert.equals(req:header("X-String"), "abcd")
      req:header("X-Number", 1234)
      assert.equals(req:header("X-Number"), "1234")
      req:header("X-Bool", true)
      assert.equals(req:header("X-Bool"), "true")
      assert.equals(req.method, "GET")
      assert.equals(req.uri, "/")
      assert.equals(req.http_version, "HTTP/1.1")
      assert.equals(req.host, "www.example.com")
      local client = http.StreamClient(sc)
      local res = client:send(req)
      assert.equals(res.status, 200)
      assert.equals(res.status_reason, "OK")
      assert.equals(res:header('content-type'), 'application/octet-stream')
      assert.equals(res:header('cOntent-lEngth'), "11")
      assert.equals(res.content_length, 11)
      assert.equals(res:read_body(), "Chihayafuru")
      assert(server:running())
      client:close()
      sched.yield() -- socket is closed in client
      sched.yield() -- read_request() returns in server (with nil)
      assert(not server:running())
   end)
end)

local function with_request_handler(request_handler, fn)
   local ss,sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM)
   local server = http.StreamServer(ss, request_handler)
   server:start()
   local client = http.StreamClient(sc)
   fn(client, server)
   client:close()
   sched.yield() -- socket is closed in client
   sched.yield() -- read_request returns in server
   sc:close()
   ss:close()
end

-- timeout.connect:
-- max time to wait for SYN/ACK

-- timeout.accept:
-- max time to wait until an incoming connection is accepted

-- timeout.data:
-- max time to wait until a socket becomes readable/writable

-- timeout.first_line:
-- max time to wait for first line of request/response

-- timeout.headers:
-- max time to wait until all headers + empty line are transmitted

-- timeout.body:
-- max time to wait until the entire body is transmitted

testing("404", function()
   local function handler(req)
      assert.equals(req.method, "GET")
      assert.equals(req.uri, "/")
      assert.equals(req.http_version, "HTTP/1.1")
      assert.is_nil(req.host)
      assert.equals(req.content_length, 0)
      return http.Response {
         status = 404
      }
   end
   with_request_handler(handler, function(client)
      local req = http.Request {}
      local res = client:send(req)
      assert.equals(res.http_version, "HTTP/1.1")
      assert.equals(res.status, 404)
      assert.equals(res.status_reason, "Not found")
      assert.equals(res.content_length, 0)
   end)
end)
