local testing = require('testing')('async')
local ffi = require('ffi')
local async = require('async')
local sched = require('sched')
local mm = require('mm')
local assert = require('assert')
local inspect = require('inspect')

local ASYNC = async.register_worker(ffi.C.zz_async_handlers)

local function make_async_echo_requester(delay, payload, acc)
   return function()
      mm.with_block("struct zz_async_echo", nil, function(request, block_size)
         request.delay = delay
         request.payload = payload
         -- zz_async_echo_worker takes a delay and
         -- returns .payload in .response after delay seconds
         async.request(ASYNC, ffi.C.ZZ_ASYNC_ECHO, request)
         table.insert(acc, request.response)
      end)
   end
end

testing("async", function()
   local delays = {1,2,3,4,5,6,7,8,9,10}
   local payloads = {1,2,3,4,5,6,7,8,9,10}
   local expected_replies = {}
   local actual_replies = {}
   local threads = {}
   for i=1,10 do
      local delay = table.remove(delays, math.random(#delays))
      local payload = table.remove(payloads, math.random(#payloads))
      -- we scale down delay a bit so that the test doesn't take too long
      -- (which also makes the test fragile if the system has high load)
      table.insert(threads, sched(make_async_echo_requester(delay*0.1, payload, actual_replies)))
      expected_replies[delay] = payload
   end
   sched.join(threads)
   assert.equals(actual_replies, expected_replies)
end)

-- test that async requests which cannot be handled immediately are
-- executed later

testing("async_queueing", function()
   actual_replies = {}
   local n_req = 100
   local threads = {}
   for i=1,n_req do
      table.insert(threads, sched(make_async_echo_requester(0, i, actual_replies)))
   end
   sched.join(threads)
   assert.equals(#actual_replies, n_req)
   table.sort(actual_replies)
   for i=1,n_req do
      assert.equals(actual_replies[i], i)
   end
end)
