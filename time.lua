local ffi = require('ffi')
local mm = require('mm')
local util = require('util')

ffi.cdef [[

/* sizeof(long) == sizeof(size_t) on Linux ... but not on Windows!
 *
 * details: https://stackoverflow.com/a/384672 */

typedef         long clock_t;
typedef         long time_t;
typedef     uint32_t useconds_t;
typedef         long suseconds_t;
typedef      int32_t clockid_t;
typedef       void * timer_t;

enum {
  CLOCK_REALTIME           = 0,
  CLOCK_MONOTONIC          = 1,
  CLOCK_PROCESS_CPUTIME_ID = 2,
  CLOCK_THREAD_CPUTIME_ID  = 3,
  CLOCK_MONOTONIC_RAW      = 4,
  CLOCK_REALTIME_COARSE    = 5,
  CLOCK_MONOTONIC_COARSE   = 6,
  CLOCK_BOOTTIME           = 7,
  CLOCK_REALTIME_ALARM     = 8,
  CLOCK_BOOTTIME_ALARM     = 9,
  CLOCK_TAI                = 11
};

struct timespec {
  time_t tv_sec;      /* seconds */
  long int tv_nsec;   /* nanoseconds */
};

struct timeval {
  time_t tv_sec;      /* seconds */
  long int tv_usec;   /* microseconds */
};

struct timezone {
  int tz_minuteswest;
  int tz_dsttime;
};

struct tm
{
  int sec;          /* Seconds.	[0-60] (1 leap second) */
  int min;          /* Minutes.	[0-59] */
  int hour;         /* Hours.	[0-23] */
  int mday;         /* Day.		[1-31] */
  int mon;          /* Month.	[0-11] */
  int year;         /* Year	- 1900.  */
  int wday;         /* Day of week.	[0-6] */
  int yday;         /* Days in year.[0-365]	*/
  int isdst;        /* DST.		[-1/0/1]*/
  long int gmtoff;	/* Seconds east of UTC.  */
  const char *zone; /* Timezone abbreviation.  */
};

int gettimeofday (struct timeval *TP,
                  struct timezone *TZP);

int nanosleep (const struct timespec *requested_time,
               struct timespec *remaining);

int clock_gettime(clockid_t clk_id, struct timespec *tp);

struct tm * gmtime_r (const time_t *TIME, struct tm *RESULTP);
struct tm * localtime_r (const time_t *TIME, struct tm *RESULTP);

time_t timelocal (struct tm *BROKENTIME);
time_t timegm (struct tm *BROKENTIME);

]]

local M = {}

function M.time(clock_id)
   clock_id = clock_id or 0
   local tp = ffi.new("struct timespec")
   if ffi.C.clock_gettime(clock_id, tp) ~= 0 then
      ef("clock_gettime() failed")
   end
   -- on 64-bit architectures tp.tv_sec and tp.tv_nsec are boxed
   return tonumber(tp.tv_sec) + tonumber(tp.tv_nsec) / 1e9
end

function M.nanosleep(seconds)
   local requested_time = ffi.new("struct timespec")
   local integer_part = math.floor(seconds)
   requested_time.tv_sec = integer_part
   local float_part = seconds - integer_part
   local ns = float_part * 1e9
   requested_time.tv_nsec = ns
   local remaining = ffi.new("struct timespec")
   if ffi.C.nanosleep(requested_time, remaining) ~= 0 then
      ef("nanosleep() failed")
   end
end

function M.sleep(seconds)
   -- sleep for the given number of seconds
   local sched = require('sched')
   -- required here to avoid circular dependency
   -- between sched and time
   if sched.ticking() then
      sched.sleep(seconds)
   else
      M.nanosleep(seconds)
   end
end

local BrokenTime_mt = {}

function BrokenTime_mt:timelocal()
   return tonumber(ffi.C.timelocal(self))
end

function BrokenTime_mt:timegm()
   return tonumber(ffi.C.timegm(self))
end

BrokenTime_mt.__index = BrokenTime_mt

local BrokenTime = ffi.metatype("struct tm", BrokenTime_mt)

function M.gmtime(seconds_since_epoch)
   seconds_since_epoch = seconds_since_epoch or M.time()
   local tm = ffi.new("struct tm")
   mm.with_block("time_t", nil, function(ptr, block_size)
      ptr[0] = seconds_since_epoch
      local rv = ffi.C.gmtime_r(ptr, tm)
      if rv == nil then
         util.check_errno("gmtime_r", -1)
      end
      assert(rv == tm)
   end)
   return BrokenTime(tm)
end

function M.localtime(seconds_since_epoch)
   seconds_since_epoch = seconds_since_epoch or M.time()
   local tm = ffi.new("struct tm")
   mm.with_block("time_t", nil, function(ptr, block_size)
      ptr[0] = seconds_since_epoch
      local rv = ffi.C.localtime_r(ptr, tm)
      if rv == nil then
         util.check_errno("localtime_r", -1)
      end
      assert(rv == tm)
   end)
   return BrokenTime(tm)
end

return setmetatable(M, { __index = ffi.C })
