local ffi = require('ffi')
local bit = require('bit')
local buffer = require('buffer')

ffi.cdef [[
int nn_errno (void);
const char *nn_strerror (int errnum);

void nn_term (void);

void *nn_allocmsg (size_t size, int type);
void *nn_reallocmsg (void *msg, size_t size);
int nn_freemsg (void *msg);

int nn_socket (int domain, int protocol);
int nn_close (int s);
int nn_setsockopt (int s, int level, int option, const void *optval, size_t optvallen);
int nn_getsockopt (int s, int level, int option, void *optval, size_t *optvallen);
int nn_bind (int s, const char *addr);
int nn_connect (int s, const char *addr);
int nn_shutdown (int s, int how);
int nn_send (int s, const void *buf, size_t len, int flags);
int nn_recv (int s, void *buf, size_t len, int flags);

struct nn_pollfd {
    int fd;
    short events;
    short revents;
};

int nn_poll (struct nn_pollfd *fds, int nfds, int timeout);
]]

local M = {}

-- socket domains
M.AF_SP              = 1
M.AF_SP_RAW          = 2

-- socket protocols
M.PAIR               = 0x10
M.PUB                = 0x20
M.SUB                = 0x21
M.REQ                = 0x30
M.REP                = 0x31
M.PUSH               = 0x50
M.PULL               = 0x51
M.SURVEYOR           = 0x60
M.RESPONDENT         = 0x61
M.BUS                = 0x70

-- socket option levels
M.SOL_SOCKET         = 0

-- socket options
M.LINGER             = 1
M.SNDBUF             = 2
M.RCVBUF             = 3
M.SNDTIMEO           = 4
M.RCVTIMEO           = 5
M.RECONNECT_IVL      = 6
M.RECONNECT_IVL_MAX  = 7
M.SNDPRIO            = 8
M.RCVPRIO            = 9
M.SNDFD              = 10
M.RCVFD              = 11
M.DOMAIN             = 12
M.PROTOCOL           = 13
M.IPV4ONLY           = 14
M.SOCKET_NAME        = 15

M.REQ_RESEND_IVL     = 1

M.SUB_SUBSCRIBE      = 1
M.SUB_UNSUBSCRIBE    = 2

M.SURVEYOR_DEADLINE  = 1

-- send/recv options
M.DONTWAIT           = 1

-- poll events
M.POLLIN             = 1
M.POLLOUT            = 2

local function nn_error()
   return ffi.string(ffi.C.nn_strerror(ffi.C.nn_errno()))
end

function M.socket(domain, protocol)
   local s = ffi.C.nn_socket(domain, protocol)
   if s < 0 then
      ef("nn_socket() failed: %s", nn_error())
   end
   return s
end

function M.close(s)
   local rv = ffi.C.nn_close(s)
   if rv ~= 0 then
      ef("nn_close() failed: %s", nn_error())
   end
   return rv
end

function M.setsockopt(s, level, option, optval, optvallen)
   if type(optval)=="string" and optvallen == nil then
      optvallen = #optval
   end
   local rv = ffi.C.nn_setsockopt(s, level, option, optval, optvallen)
   if rv ~= 0 then
      ef("nn_setsockopt() failed: %s", nn_error())
   end
   return rv
end

function M.getsockopt(s, level, option)
   local optval = ffi.new("int[1]")
   local optvallen = ffi.new("size_t[1]", ffi.sizeof("int"))
   local rv = ffi.C.nn_getsockopt(s, level, option, optval, optvallen)
   if rv ~= 0 then
      ef("nn_getsockopt() failed: %s", nn_error())
   end
   return optval[0]
end

function M.bind(s, addr)
   local endpoint = ffi.C.nn_bind(s, addr)
   if endpoint < 0 then
      ef("nn_bind() failed: %s", nn_error())
   end
   return endpoint
end

function M.connect(s, addr)
   local endpoint = ffi.C.nn_connect(s, addr)
   if endpoint < 0 then
      ef("nn_connect() failed: %s", nn_error())
   end
   return endpoint
end

function M.shutdown(s, how)
   local rv = ffi.C.nn_shutdown(s, how)
   if rv < 0 then
      ef("nn_shutdown() failed: %s", nn_error())
   end
   return rv
end

function M.send(s, data, len, flags)
   local buf = buffer.wrap(data, len or #data)
   flags = flags or 0
   local bytes_sent = ffi.C.nn_send(s, buf:ptr(), #buf, flags)
   if bytes_sent == -1 then
      ef("nn_send() failed: %s", nn_error())
   end
   return bytes_sent
end

function M.recv(s, flags)
   flags = flags or 0
   local bufptr = ffi.new("void*[1]")
   -- NN_MSG=-1: nanomsg allocates the buffer for us
   local bytes_received = ffi.C.nn_recv(s, bufptr, -1, flags)
   if bytes_received == -1 then
      if bit.band(flags, M.DONTWAIT) ~= 0 then
         -- this is normal, there was nothing to process
         return nil
      else
         ef("nn_recv() failed: %s", nn_error())
      end
   end
   local buf = buffer.copy(bufptr[0], bytes_received)
   assert(ffi.C.nn_freemsg(bufptr[0])==0)
   return buf
end

-- Poll

local Poll_mt = {}

function Poll_mt:add(s, events)
   table.insert(self.items, {s, events})
   self.changed = true
end

function Poll_mt:populate_nn_pollfd()
   self.nn_pollfd = ffi.new("struct nn_pollfd[?]", #self.items)
   for i=1,#self.items do
      self.nn_pollfd[i-1].fd = self.items[i][1]
      self.nn_pollfd[i-1].events = self.items[i][2]
      self.nn_pollfd[i-1].revents = 0
   end
end

function Poll_mt:__call(timeout)
   if self.nn_pollfd == nil or self.changed then
      self:populate_nn_pollfd()
      self.changed = false
   end
   local rv = ffi.C.nn_poll(self.nn_pollfd, #self.items, timeout)
   if rv == -1 then
      ef("nn_poll() failed: %s", nn_error())
   end
   return rv
end

function Poll_mt:__index(k)
   if type(k)=="number" then
      return self.nn_pollfd[k]
   else
      return rawget(Poll_mt, k)
   end
end

function M.Poll()
   local self = {
      items = {},
      nn_pollfd = nil,
      changed = false,
   }
   return setmetatable(self, Poll_mt)
end

M.error = nn_error

return M
