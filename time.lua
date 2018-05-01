local ffi = require('ffi')

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

int gettimeofday (struct timeval *TP,
                  struct timezone *TZP);

int nanosleep (const struct timespec *requested_time,
               struct timespec *remaining);

int clock_gettime(clockid_t clk_id, struct timespec *tp);

]]

local M = {}

function M.time(clock_id)
   clock_id = clock_id or 0
   local tp = ffi.new("struct timespec")
   if ffi.C.clock_gettime(clock_id, tp) ~= 0 then
      error("clock_gettime() failed")
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
      error("nanosleep() failed")
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

return setmetatable(M, { __index = ffi.C })
