local ffi = require('ffi')
local sched = require('sched')
local util = require('util')
local errno = require('errno')

ffi.cdef [[

enum {
  EFD_SEMAPHORE = 00000001,
  EFD_CLOEXEC   = 02000000,
  EFD_NONBLOCK  = 00004000
};

int eventfd(unsigned int initval, int flags);

typedef struct {
  int fd;
} zz_trigger;

]]

local M = {}

local Trigger_mt = {}

function Trigger_mt:read()
   local buf = ffi.new("uint64_t[1]", 0)
   local nbytes = ffi.C.read(self.fd, buf, 8)
   if nbytes == 8 then
      local value = tonumber(buf[0])
      assert(value > 0)
      return value
   elseif nbytes == -1 then
      local errnum = errno.errno()
      if errnum ~= ffi.C.EAGAIN then
         ef("read() failed: %s", errno.strerror(errnum))
      end
      return nil
   else
      ef("read() failed: nbytes=%d, expected 8", nbytes)
   end
end

function Trigger_mt:poll()
   local rv = nil
   while not rv do
      if sched.ticking() then
         sched.poll(self.fd, "r")
      end
      rv = self:read()
   end
   return rv
end

function Trigger_mt:write(data)
   local buf = ffi.new("uint64_t[1]")
   buf[0] = data
   ffi.C.write(self.fd, buf, 8)
end

function Trigger_mt:fire()
   self:write(1)
end

function Trigger_mt:delete()
   if self.fd ~= 0 then
      ffi.C.close(self.fd)
      self.fd = 0
   end
end

Trigger_mt.__index = Trigger_mt
Trigger_mt.__gc = Trigger_mt.delete

local Trigger = ffi.metatype("zz_trigger", Trigger_mt)

function M.Trigger()
   local fd = util.check_errno("eventfd",
      ffi.C.eventfd(0, ffi.C.EFD_NONBLOCK))
   return Trigger(fd)
end

function M.Semaphore()
   local fd = util.check_errno("eventfd",
      ffi.C.eventfd(0, bit.bor(ffi.C.EFD_NONBLOCK, ffi.C.EFD_SEMAPHORE)))
   return Trigger(fd)
end

return setmetatable(M, { __call = M.Trigger })
