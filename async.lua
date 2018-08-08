local ffi = require('ffi')
local util = require('util')
local sched = require('sched')
local pthread = require('pthread')
local trigger = require('trigger')
local inspect = require('inspect')
local adt = require('adt')

ffi.cdef [[

typedef void (*zz_async_handler)(void *request_data);

int zz_async_register_worker(void *handlers[]);

struct zz_async_worker_info {
  zz_trigger request_trigger;
  int worker_id;
  int handler_id;
  void *request_data;
  zz_trigger response_trigger;
};

void *zz_async_worker_thread(void *arg);

enum {
  ZZ_ASYNC_ECHO
};

struct zz_async_echo {
  double delay;
  double payload;
  double response;
};

void *zz_async_handlers[];

]]

local M = {}

local MAX_ACTIVE_THREADS = 16

-- pool of free (reservable) worker threads
local thread_pool = {}

-- reservation ids of coroutines waiting for a worker thread
local reserve_queue = adt.List()

-- number of worker threads (free + active)
local n_worker_threads   = 0

-- number of worker threads currently servicing a request
local n_active_threads   = 0

local function create_worker_thread()
   n_worker_threads = n_worker_threads + 1
   local worker_info = ffi.new("struct zz_async_worker_info")
   local request_trigger = trigger()
   worker_info.request_trigger = request_trigger
   local response_trigger = trigger()
   worker_info.response_trigger = response_trigger
   sched.poller_add(response_trigger.fd, "r")
   local thread_id = ffi.new("pthread_t[1]")
   local rv = ffi.C.pthread_create(thread_id,
                                   nil,
                                   ffi.C.zz_async_worker_thread,
                                   ffi.cast("void*", worker_info))
   if rv ~= 0 then
      error("cannot create async worker thread: pthread_create() failed")
   end
   local self = {}
   function self:send_request(worker_id, handler_id, request_data)
      worker_info.worker_id = worker_id
      worker_info.handler_id = handler_id
      worker_info.request_data = request_data
      request_trigger:fire()
      response_trigger:poll()
   end
   function self:stop()
      self:send_request(-1, 0, nil)
      local retval = ffi.new("void*[1]")
      local rv = ffi.C.pthread_join(thread_id[0], retval)
      if rv ~=0 then
         error("cannot join async worker thread: pthread_join() failed")
      end
      sched.poller_del(response_trigger.fd)
      response_trigger:delete()
      request_trigger:delete()
      n_worker_threads = n_worker_threads - 1
   end
   return self
end

local function reserve_thread()
   local t
   if #thread_pool == 0 then
      if n_active_threads == MAX_ACTIVE_THREADS then
         local reservation_id = sched.make_event_id()
         reserve_queue:push(reservation_id)
         -- block until we get a free thread
         t = sched.wait(reservation_id)
      else
         t = create_worker_thread()
      end
   else
      t = table.remove(thread_pool)
   end
   n_active_threads = n_active_threads + 1
   return t
end

local function release_thread(t)
   n_active_threads = n_active_threads - 1
   if reserve_queue:empty() then
      -- nobody is waiting for a thread, put it back into the pool
      table.insert(thread_pool, t)
   else
      local reservation_id = reserve_queue:shift()
      sched.emit(reservation_id, t)
   end
end

function M.register_worker(handlers)
   return ffi.C.zz_async_register_worker(handlers)
end

function M.request(worker_id, handler_id, request_data)
   -- reserve_thread() blocks if needed
   -- until a thread becomes available
   local t = reserve_thread()
   t:send_request(worker_id, handler_id, request_data)
   release_thread(t)
end

local function AsyncModule(sched)
   local self = {}
   function self.init()
      thread_pool = {}
      reserve_queue = adt.List()
      n_active_threads = 0
      n_worker_threads = 0
   end
   function self.done()
      assert(n_active_threads == 0)
      assert(reserve_queue:empty())
      for _,t in ipairs(thread_pool) do
         t:stop()
      end
      assert(n_worker_threads == 0)
      thread_pool = {}
   end
   return self
end

sched.register_module(AsyncModule)

return M
