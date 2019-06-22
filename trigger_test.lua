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
      -- if we scheduled this fn before gather_wood(), we'd get 50
      assert.equals(wood_gathered, 51)
      t:fire()
      -- in the next cycle of the event loop:
      --
      -- 1. gather_wood() will be resumed (-> wood_gathered = 52)
      -- 2. wait_for_stop() will return from t:poll()
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

testing("write", function()
   local t = trigger()
   local values = {}
   local reader = sched(function()
      while true do
         local value = t:poll()
         table.insert(values, value)
         if value == 1 then
            break
         end
      end
   end)
   local writer = sched(function()
      -- values written to the trigger add up
      -- the accumulated value is returned by the next read()
      -- read() resets the counter to zero
      t:write(5)
      sched.yield()
      -- the first sched.yield() call pushes this thread back to the
      -- list of runnables. at the next tick, the scheduler poller
      -- will detect that the trigger fd is readable, so it will push
      -- the reader thread to the list of runnables. at this point,
      -- the reader thread is at a higher index in the runnables list
      -- than this thread, so it will be resumed AFTER this thread. if
      -- we want the reader to see the value which we have just
      -- written (5), we have to yield() again to ensure that t:poll()
      -- returns before we continue writing
      sched.yield()
      t:write(3)
      t:write(2)
      sched.yield()
      sched.yield()
      t:write(1)
   end)
   sched.join({reader, writer})
   assert.equals(values, {5,3+2,1})
   t:delete()
end)

testing("Semaphore", function()
   local t = trigger.Semaphore()
   local values = {}
   local reader = sched(function()
      while #values < 11 do
         local value = t:poll()
         table.insert(values, value)
      end
   end)
   -- values written to the semaphore add up
   -- each read() returns 1 and decrements the counter by one
   t:write(5)
   sched.yield()
   t:write(3)
   t:write(2)
   sched.yield()
   t:write(1)
   sched.join(reader)
   assert.equals(values, {
      1,1,1,1,1, -- 5
      1,1,1,     -- 3
      1,1,       -- 2
      1,         -- 1
   })
   t:delete()
end)
