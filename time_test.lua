local testing = require('testing')('time')
local assert = require('assert')
local time = require('time')
local sched = require('sched')

testing("clock type ids", function()
  -- clock type ids shall be accessible via the module
  assert(time.CLOCK_MONOTONIC==1)
end)

testing:nosched("sleep", function()
   local t1 = time.time()
   local sleep_time = 0.1
   time.sleep(sleep_time)
   local t2 = time.time()
   local elapsed = t2 - t1
   local diff = math.abs(elapsed - sleep_time)
   -- sched provides us with the precision of its timer
   local max_diff = sched.precision
   assert(diff <= max_diff, sf("there are problems with timer precision: diff (%f) > max allowed diff (%f)", diff, max_diff))
end)

testing("sleep", function()
   local coll = {}

   local function add(x)
      table.insert(coll, x)
   end

   sched.join {
      sched(function()
            add(5)
            time.sleep(0.1)
            add(10)
            time.sleep(0.4)
            add(15)
            time.sleep(0.3)
            add(20)
            time.sleep(0.2)
            add(25)
      end),
      sched(function()
            time.sleep(0.2)
            add(2)
            time.sleep(0.2)
            add(4)
            time.sleep(0.3)
            add(6)
            time.sleep(0.2)
            add(8)
      end)
   }

   local expected = { 5, 10, 2, 4, 15, 6, 20, 8, 25 }
   assert.equals(coll, expected)
end)

testing("gmtime", function()
   local t = time.gmtime(1234567890)
   -- 2009-02-13 Friday, 23:31:30 UTC
   assert.equals(t.sec, 30)
   assert.equals(t.min, 31)
   assert.equals(t.hour, 23)
   assert.equals(t.mday, 13)
   assert.equals(t.mon, 1) -- 0: January, 1: February
   assert.equals(t.year, 109) -- 0: 1900, 109: 2009
   assert.equals(t.wday, 5) -- 0: Sunday, 5: Friday
   assert.equals(t.yday, 43) -- 0: Jan 1, 43: Feb 13
   assert.equals(t:timegm(), 1234567890)

   -- with no argument it uses current time
   local diff = time.gmtime():timegm() - time.gmtime(time.time()):timegm()
   assert(math.abs(diff) <= 1)

   -- wday and yday are not used by timegm()
   t.wday = 3
   t.yday = 50
   assert.equals(t:timegm(), 1234567890)

   -- but other fields are
   t.mday = 20
   assert(t:timegm() ~= 1234567890)
end)

testing("localtime", function()
   local t = time.localtime(1234567890)
   -- 2009-02-13 Friday, 23:31:30 UTC
   assert.equals(t.sec, 30)
   assert.equals(t.min, 31)
   --assert.equals(t.hour, 23)
   --assert.equals(t.mday, 13)
   assert.equals(t.mon, 1) -- 0: January, 1: February
   assert.equals(t.year, 109) -- 0: 1900, 109: 2009
   --assert.equals(t.wday, 5) -- 0: Sunday, 5: Friday
   --assert.equals(t.yday, 43) -- 0: Jan 1, 43: Feb 13
   assert.equals(t:timelocal(), 1234567890)

   -- with no argument it uses current time
   local diff = time.localtime():timelocal() - time.localtime(time.time()):timelocal()
   assert(math.abs(diff) <= 1)
end)
