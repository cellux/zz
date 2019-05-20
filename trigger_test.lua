local testing = require('testing')
local trigger = require('trigger')
local sched = require('sched')
local assert = require('assert')

testing("trigger", function()
   local t = trigger()

   local keep_gathering_wood = true
   local wood_gathered = 0

   local function gather_wood()
      while keep_gathering_wood do
         wood_gathered = wood_gathered + 1
         sched.yield()
      end
   end

   local function wait_for_stop()
      t:poll()
      assert.equals(wood_gathered, 52)
      keep_gathering_wood = false
   end

   local function let_him_gather_some_wood()
      for i=1,50 do
         sched.yield()
      end
      assert.equals(wood_gathered, 51)
      -- if we scheduled this fn before gather_wood(), we'd get 50
      t:fire()
      -- in the next cycle of the event loop, first gather_wood() will be
      -- resumed, then wait_for_stop() will return from the t:poll() call
   end

   sched.join {
      sched(gather_wood),
      sched(wait_for_stop),
      sched(let_him_gather_some_wood),
   }

   assert.equals(keep_gathering_wood, false)
   assert.equals(wood_gathered, 52)

   t:delete()
end)
