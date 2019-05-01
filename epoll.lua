local ffi = require('ffi')
local bit = require('bit')
local util = require('util')
local errno = require('errno')
local mm = require('mm')

ffi.cdef [[
enum EPOLL_EVENTS {
  EPOLLIN      = 0x0001,
  EPOLLPRI     = 0x0002,
  EPOLLOUT     = 0x0004,
  EPOLLRDNORM  = 0x0040,
  EPOLLRDBAND  = 0x0080,
  EPOLLWRNORM  = 0x0100,
  EPOLLWRBAND  = 0x0200,
  EPOLLMSG     = 0x0400,
  EPOLLERR     = 0x0008,
  EPOLLHUP     = 0x0010,
  EPOLLRDHUP   = 0x2000,
  EPOLLWAKEUP  = 1u << 29,
  EPOLLONESHOT = 1u << 30,
  EPOLLET      = 1u << 31
};

enum {
  EPOLL_CTL_ADD = 1,
  EPOLL_CTL_DEL = 2,
  EPOLL_CTL_MOD = 3
};

typedef union epoll_data {
  void *ptr;
  int fd;
  uint32_t u32;
  uint64_t u64;
} epoll_data_t;

struct epoll_event {
  uint32_t events;	/* Epoll events */
  epoll_data_t data;	/* User data variable */
} __attribute__((__packed__));

extern int epoll_create (int size);
extern int epoll_create1 (int flags);
extern int epoll_ctl (int epfd, int op, int fd, struct epoll_event *event);
extern int epoll_wait (int epfd, struct epoll_event *events, int max_events, int timeout);

]]

local Poller_mt = {}

local event_markers = {
   ["r"] = ffi.C.EPOLLIN,
   ["w"] = ffi.C.EPOLLOUT,
   ["1"] = ffi.C.EPOLLONESHOT,
   ["e"] = ffi.C.EPOLLET,
}

local function parse_events(events)
   if type(events)=="string" then
      local rv = 0
      for i=1,#events do
         local e = events:sub(i,i)
         local ev = event_markers[e]
         if not ev then
            ef("unknown event marker: '%s' in '%s'", e, events)
         end
         rv = bit.bor(rv, ev)
      end
      return rv
   else
      return events
   end
end

function Poller_mt:fd()
   return self.epfd
end

function Poller_mt:match_events(mask, events)
   mask = parse_events(mask)
   return bit.band(events, mask) ~= 0
end

function Poller_mt:ctl(op, fd, events, userdata)
   return mm.with_block("struct epoll_event", nil, function(ev)
      ev.events = events and parse_events(events) or 0
      ev.data.fd = userdata or 0
      return util.check_errno("epoll_ctl", ffi.C.epoll_ctl(self.epfd, op, fd, ev))
   end)
end

function Poller_mt:add(fd, events, userdata)
   return self:ctl(ffi.C.EPOLL_CTL_ADD, fd, events, userdata)
end

function Poller_mt:mod(fd, events, userdata)
   return self:ctl(ffi.C.EPOLL_CTL_MOD, fd, events, userdata)
end

function Poller_mt:del(fd, events, userdata)
   return self:ctl(ffi.C.EPOLL_CTL_DEL, fd, events, userdata)
end

function Poller_mt:wait(timeout, process)
   local rv
   while true do
      rv = ffi.C.epoll_wait(self.epfd,
                            self.epoll_events,
                            self.max_events,
                            timeout)
      if rv >= 0 then
         break
      elseif rv == -1 then
         local errnum = errno.errno()
         if errnum ~= ffi.C.EINTR then
            ef("epoll_wait() failed: %s", errno.strerror(errnum))
         end
      else
         ef("epoll_wait() failed: invalid return value: %d", rv)
      end
   end
   if rv > 0 then
      for i = 1,rv do
         local epoll_event = self.epoll_events[i-1]
         local events = epoll_event.events
         local userdata = epoll_event.data.fd
         process(events, userdata)
      end
   end
end

function Poller_mt:close()
   if self.epfd >= 0 then
      util.check_errno("close", ffi.C.close(self.epfd))
      self.epfd = -1
   end
end

Poller_mt.__index = Poller_mt

local function Poller(epfd, max_events)
   max_events = max_events or 256
   local self = {
      epfd = epfd,
      max_events = max_events,
      epoll_events = ffi.new("struct epoll_event[?]", max_events),
   }
   return setmetatable(self, Poller_mt)
end

local M = {}

function M.Poller(max_events)
   local epfd = util.check_errno("epoll_create", ffi.C.epoll_create(1))
   return Poller(epfd, max_events)
end

M.poller_factory = M.Poller

return M
