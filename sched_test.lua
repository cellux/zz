local testing = require('testing')('sched')
local sched = require('sched')
local time = require('time')
local process = require('process')
local signal = require('signal')
local assert = require('assert')
local inspect = require('inspect')

testing:nosched("scheduler creation and release", function()
   for i=1,10 do
      sched(function() sched.yield() end)
      sched()
   end
end)

testing("coroutines", function()
   local coll = {}
   local function make_co(value, steps, inc)
      return function()
         while steps > 0 do
            table.insert(coll, value)
            value = value + inc
            steps = steps - 1
            sched.yield()
         end
      end
   end
   sched.join {
      sched(make_co(1,10,1)),
      sched(make_co(2,6,2)),
      sched(make_co(3,7,3)),
   }
   local expected = { 
      1,  2,  3,
      2,  4,  6,
      3,  6,  9,
      4,  8, 12,
      5, 10, 15,
      6, 12, 18,
      7,     21,
      8,
      9,
      10,
   }
   assert.equals(coll, expected)
end)

-- sched(fn, data):
-- wrap fn into a new thread, schedule it for later execution
-- pass data as a single arg when the thread is first resumed

testing("sched(fn, data)", function()
   local output = nil
   sched.join(sched(function(x) output = x end, 42))
   assert(output == 42)
end)

-- sched.on(evtype, callback):
-- invokes callback(evdata) when an `evtype' event arrives

testing:nosched("sched.on(evtype, callback)", function()
   local counter = 0
   sched.on('my-signal-forever', function(inc)
      counter = counter + inc
   end)
   -- sched.emit(evtype, evdata):
   -- post a new event to the event queue
   --
   -- any threads waiting for this evtype will wake up
   sched(function()
      sched.emit('my-signal-forever', 42.5)
      sched.yield() -- give a chance to the signal handler
      -- event callbacks registered with sched.on() keep on waiting
      -- (no matter how many times the callback has been invoked)
      sched.emit('my-signal-forever', 10)
      sched.yield() -- give another chance to the signal handler
   end)
   sched()
   assert.equals(counter, 42.5+10)
end)

-- if you want to stop listening, return sched.OFF from the callback

testing:nosched("sched.OFF", function()
   local counter = 0
   sched.on('my-signal-once', function(inc)
      counter = counter + inc
      return sched.OFF
   end)
   sched(function()
      sched.emit('my-signal-once', 5)
      sched.yield()
      sched.emit('my-signal-once', 7)
      sched.yield()
   end)
   sched()
   assert.equals(counter, 5)
end)

-- a 'quit' event terminates the event loop
-- after a quit event has been posted, sched.running() returns false
-- this can be used to check whether it's time to exit

testing:nosched("sched.quit()", function()
   local counter = 0
   sched(function()
      while sched.running() do
         sched.yield()
         counter = counter + 1
         if counter == 10 then
            sched.quit()
         end
      end
   end)
   sched()
   assert.equals(counter, 10)
end)

-- sched.ticking(): the loop is still going around and around
-- sched.running(): sched.quit() has not been called yet

testing:nosched("ticking and running", function()
   assert(not sched.running())
   assert(not sched.ticking())
   sched(function()
      assert(sched.running())
      assert(sched.ticking())
      sched.quit()
      assert(not sched.running())
      assert(sched.ticking())
   end)
   sched()
   assert(not sched.running())
   assert(not sched.ticking())
end)

-- sched.wait(evtype):
-- go to sleep, wake up when an event of type `evtype' arrives
-- the event's data is returned by the sched.wait() call

testing("sched.wait(evtype)", function()
   local output = nil
   local waiter = sched(function()
      local wake_up_data = sched.wait('wake-up')
      assert(type(wake_up_data)=="table")
      assert(wake_up_data.value == 43)
      output = wake_up_data.value
   end)
   -- we emit after the previous thread has already executed sched.wait()
   --
   -- otherwise there would be no threads waiting for this evtype and
   -- sched() would exit immediately
   sched(function()
      sched.emit('wake-up', { value = 43 })
   end)
   sched.join(waiter)
   assert(output == 43, sf("output=%s", output))
end)

-- sched.wait() also accepts a positive number (a timestamp)
-- in that case, the thread will be resumed at the specified time

testing:nosched("sched.wait(timestamp)", function()
   local time_before_wait = nil
   local wait_amount = 0.1 -- seconds
   local time_after_wait = nil
   sched(function()
      -- sched.time() returns the current clock time in seconds
      time_before_wait = sched.time()
      sched.wait(sched.time() + wait_amount)
      -- we could also use sched.sleep():
      -- sched.sleep(x) = sched.wait(sched.time()+x)
      time_after_wait = sched.time()
   end)
   sched()
   assert.type(time_after_wait, 'number')
   local elapsed = time_after_wait-time_before_wait
   local diff = math.abs(wait_amount - elapsed) -- error
   -- sched provides us with the precision of its timer
   assert(diff <= sched.precision,
      sf("diff (%s) > sched timer precision (%s)", diff, sched.precision))
   -- retrieving precision shouldn't start another scheduler instance
   assert.equals(sched.state(), "off")
end)

testing:nosched("a thread sleeping in sched.wait() keeps the event loop alive", function()
   local pid = process.fork()
   if pid == 0 then
      sched(function()
         sched.wait('quit')
      end)
      sched()
      process.exit()
   else
      time.sleep(0.1)
      -- subprocess still exists after 100 ms
      assert(process.kill(pid, 0)==0)
      -- let's send it a SIGTERM (which will cause a sched.quit())
      process.kill(pid, signal.SIGTERM)
      -- wait for it
      assert(process.waitpid(pid)==pid)
      -- now it should not exist any more
      assert.equals(process.kill(pid, 0), -1, "result of process.kill(pid,0) after child got SIGTERM")
   end
end)

testing:nosched("callbacks registered with sched.on() do not keep the event loop alive", function()
   local output = {}
   sched.on('my-signal', function()
      table.insert(output, "signal-handler-1")
   end)
   sched(function()
      sched.emit('my-signal', 0)
      table.insert(output, "signal-sent")
      -- this thread will now exit, so the number of running or
      -- waiting threads goes down to zero. as a result, neither of
      -- the registered my-signal handlers will be called.
   end)
   sched.on('my-signal', function()
      table.insert(output, "signal-handler-2")
   end)
   sched()
   assert.equals(output, {"signal-sent"})
end)

-- if you want to have a background thread which does not keep the
-- event loop alive, schedule it with sched.background():

testing:nosched("sched.background()", function()
   local counter = -100
   sched.background(function()
      counter = 0
      while true do
         evdata = sched.wait('never-happens')
         -- do something with the event
      end
   end)
   sched(function()
      for i=1,10 do
         sched.yield()
         counter = counter + 1
      end
   end)
   sched()
   assert.equals(counter, 10)
end)

-- one way to ensure that no signal gets lost is to call sched.yield()
-- as the last statement of the thread which emits the signal which
-- should be handled. this ensures a last tick of the event loop, in
-- which all pending callbacks will be scheduled for execution.

testing:nosched("a last sched.yield() ensures signal delivery", function()
   local output = {}
   sched.on('my-signal', function()
      table.insert(output, "signal-handler-1")
   end)
   sched(function()
      -- sched.emit() is asynchronous: it only posts the event
      -- callbacks will be scheduled when the event is processed
      sched.emit('my-signal', 0)
      table.insert(output, "signal-sent")
      sched.yield()
   end)
   sched.on('my-signal', function()
      table.insert(output, "signal-handler-2")
   end)
   sched()
   assert.equals(output, {"signal-sent", "signal-handler-1", "signal-handler-2"})
end)

-- note that the above behaviour does not apply to the 'quit' signal:
-- callbacks for 'quit' are always called before exiting the event loop

testing:nosched("quit callbacks always run", function()
   local output = {}
   sched.on('quit', function()
      table.insert(output, "quit-handler-1")
   end)
   sched(function()
      table.insert(output, "sched.quit")
      sched.quit()
   end)
   sched.on('quit', function()
      table.insert(output, "quit-handler-2")
   end)
   sched()
   assert.equals(output, {"sched.quit", "quit-handler-1", "quit-handler-2"})

-- quit callbacks are called even if the code doesn't invoke
-- sched.quit() explicitly. in that case, the scheduler makes an
-- implicit call when all threads exit.

   local output = {}
   sched.on('quit', function()
      table.insert(output, "quit-handler-1")
   end)
   sched(function()
      table.insert(output, "main thread exits")
   end)
   sched.on('quit', function()
      table.insert(output, "quit-handler-2")
   end)
   sched()
   assert.equals(output, {"main thread exits", "quit-handler-1", "quit-handler-2"})
end)

testing:nosched("errors thrown by scheduled threads contain a stack trace", function()
   sched(function()
      sched(function()
         function throw()
            error("not a respectable software company")
         end
         throw()
      end)
   end)
   local err = assert.throws(sched, "not a respectable software company")
   assert.match("in function 'throw'", err)
end)

testing:nosched("join", function()
   local acc = {}
   local co1 = sched(function()
      for i=1,5 do
         table.insert(acc, i)
         sched.yield()
      end
   end)
   local co2 = sched(function()
      for i=1,5 do
         table.insert(acc, -i)
         sched.yield()
      end
   end)
   local joiner = sched(function()
       table.insert(acc, 0)
       sched.join { co1, co2 }
       table.insert(acc, 100)
   end)
   sched()
   assert.equals(acc, {1, -1, 0, 2, -2, 3, -3, 4, -4, 5, -5, 100})
end)

testing:nosched("exclusive", function()
   local acc = {}
   sched(function()
      for i=1,4 do
         table.insert(acc, i)
         sched.yield()
      end
   end)
   sched.exclusive(function()
      for i=1,4 do
         table.insert(acc, -i)
         sched.yield()
      end
   end)
   sched(function()
      for i=1,4 do
         table.insert(acc, -i*2)
         sched.yield()
      end
   end)
   local t = sched.exclusive(function()
      for i=1,4 do
         table.insert(acc, i*2)
         sched.yield()
      end
   end)
   assert.type(t, "thread")
   sched()
   assert.equals(acc, {
      -1, -2, -3, -4,
       2,  4,  6,  8,
       1, -2,  2, -4,
       3, -6,  4, -8,
   })
end)
