local ffi = require('ffi')
local async = require('async')
local sched = require('sched')
local mm = require('mm')
local assert = require('assert')
local inspect = require('inspect')

local ASYNC = async.register_worker(ffi.C.zz_async_handlers)

local delays = {1,2,3,4,5,6,7,8,9,10}
local payloads = {1,2,3,4,5,6,7,8,9,10}
local expected_replies = {}
local actual_replies = {}

local function make_async_echo_requester(delay, payload)
   return function()
      local request, block_size = mm.get_block("struct zz_async_echo_request")
      request.delay = delay
      request.payload = payload
      -- zz_async_echo_worker takes a delay and
      -- returns .payload in .response after delay seconds
      async.request(ASYNC, ffi.C.ZZ_ASYNC_ECHO, request)
      table.insert(actual_replies, request.response)
      mm.ret_block(request, block_size)
   end
end

for i=1,10 do
   local delay = table.remove(delays, math.random(#delays))
   local payload = table.remove(payloads, math.random(#payloads))
   -- we scale down delay a bit so that the test doesn't take too long
   -- (which also makes the test fragile if the system has high load)
   sched(make_async_echo_requester(delay*0.05, payload))
   expected_replies[delay] = payload
end

sched()

assert.equals(actual_replies, expected_replies)

-- test that async requests which cannot be handled immediately are
-- executed later

actual_replies = {}
local n_req = 100
for i=1,n_req do
   sched(make_async_echo_requester(0, i))
end
sched()
assert.equals(#actual_replies, n_req)
table.sort(actual_replies)
for i=1,n_req do
   assert.equals(actual_replies[i], i)
end
