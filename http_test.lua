local testing = require('testing')('http')
local assert = require('assert')
local http = require('http')
local net = require('net')
local sched = require('sched')

-- Hypertext Transfer Protocol (HTTP/1.1): Message Syntax and Routing
--
-- https://tools.ietf.org/html/rfc7230

-- 2.1. Client/Server Messaging

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
         assert.equals(req:header("X-Private-Option"), "1234")
         return "Chihayafuru"
      end
      local server = http.StreamServer(ss, request_handler)
      assert(not server:running())
      server:start()
      sched.yield()
      assert(server:running())
      local req = http.Request {
         method = "GET",
         uri = "/",
         host = "www.example.com",
         headers = {
            ["X-Color"] = "red",
         }
      }
      req:header("X-Private-Option", 1234)
      assert.equals(req.method, "GET")
      assert.equals(req.uri, "/")
      assert.equals(req.http_version, "HTTP/1.1")
      assert.equals(req.host, "www.example.com")
      assert.equals(req:header("X-Color"), "red")
      assert.equals(req:header("X-Private-Option"), "1234")
      local client = http.StreamClient(sc)
      local res = client:send(req)
      assert.equals(res.status, 200)
      assert.equals(res.status_reason, "OK")
      assert.equals(res:header('content-type'), 'application/octet-stream')
      assert.equals(res:header('cOntent-lEngth'), "11")
      assert.equals(res:read_body(), "Chihayafuru")
      assert(server:running())
      client:close()
      sched.yield() -- close
      sched.yield() -- read_request
      assert(not server:running())
   end)
end)
