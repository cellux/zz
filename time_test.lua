local time = require('time')
local sched = require('sched')

-- clock type ids shall be accessible via the module
assert(time.CLOCK_MONOTONIC==1)

local function test_sleep()
   local t1 = time.time()
   local sleep_time = 0.1
   time.sleep(sleep_time)
   local t2 = time.time()
   local elapsed = t2 - t1
   local diff = math.abs(elapsed - sleep_time)
   -- sched provides us with the precision of its timer
   local max_diff = sched.precision
   assert(diff <= max_diff, sf("there are problems with timer precision: diff (%f) > max allowed diff (%f)", diff, max_diff))
end

-- sync 
test_sleep()

-- async
sched(test_sleep)
sched()

local coll = {}

local function add(x)
   table.insert(coll, x)
end

sched(function()
         add(5)
         time.sleep(0.01)
         add(10)
         time.sleep(0.04)
         add(15)
         time.sleep(0.03)
         add(20)
         time.sleep(0.02)
         add(25)
      end)

sched(function()
         time.sleep(0.02)
         add(2)
         time.sleep(0.02)
         add(4)
         time.sleep(0.03)
         add(6)
         time.sleep(0.02)
         add(8)
      end)

sched()

local expected = { 5, 10, 2, 4, 15, 6, 20, 8, 25 }
assert(#coll == #expected, '#coll='..#coll)
for i=1,#coll do
   assert(coll[i] == expected[i])
end
