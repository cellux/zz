local ffi = require('ffi')
local adt = require('adt')
local time = require('time')
local mm = require('mm')
local nn = require('nanomsg')
local msgpack = require('msgpack')
local inspect = require('inspect')

local M = {}

local scheduler_state = "off"

-- off -> init -> running -> shutdown -> done -> off
--
-- off: there is no scheduler singleton
-- init: scheduler singleton is initializing
-- running: scheduler singleton is spinning around in its main loop
-- shutdown: scheduler singleton is shutting down (got 'quit' event)
-- done: scheduler singleton is cleaning up

function M.state()
   return scheduler_state
end

function M.running()
   return scheduler_state == "running"
end

function M.ticking()
   return scheduler_state == "running" or scheduler_state == "shutdown"
end

-- poller_factory shall be a callable returning an object which
-- implements the poller protocol (see epoll module for an example)
--
-- must be set to a platform-specific implementation at startup
M.poller_factory = nil

local module_constructors = {}

-- modules register themselves via this function if they want to do
-- something when the scheduler singleton initializes itself (init),
-- executes one cycle of its main loop (tick) or cleans up (done)
function M.register_module(mc)
   table.insert(module_constructors, mc)
end

-- every scheduler singleton has a module registry which keeps track
-- of the (module-provided) hooks to be invoked at init/tick/done
local function ModuleRegistry(scheduler)
   local hooks = {
      init = {},
      tick = {},
      done = {},
   }
   for _,mc in ipairs(module_constructors) do
      local m = mc(scheduler) -- returns a map of hooktype -> hookfn
      for k,_ in pairs(hooks) do
         if m[k] then
            table.insert(hooks[k], m[k])
         end
      end
   end
   local self = {}
   function self:invoke(hook)
      assert(hooks[hook])
      for _,fn in ipairs(hooks[hook]) do
         fn()
      end
   end
   return self
end

-- the single global scheduler instance
local scheduler_singleton

-- a special return value used to detach an event callback
local OFF = {}
M.OFF = OFF

-- the clock to use by timers
local sched_clock_id = time.CLOCK_MONOTONIC_RAW

local function get_current_time()
   return time.time(sched_clock_id)
end

M.time = get_current_time

-- after sched.wait(t), math.abs(sched.time()-t) is expected to be
-- less than sched.precision
M.precision = 0.005 -- seconds

local function Scheduler() -- scheduler constructor
   local self = {}

   -- threads may allocate event_ids and wait for them. when the event
   -- loop gets an event with a particular id, it wakes up the thread
   -- which is waiting for it
   local next_event_id = -1

   function self.make_event_id()
      local rv = next_event_id
      next_event_id = next_event_id - 1
      -- TODO: find a way to ensure that this doesn't underflow
      if next_event_id < -(2^31) then
         error("event id underflow")
      end
      return rv
   end

   if not M.poller_factory then
      error("sched.poller_factory is unset")
   end

   local poller = M.poller_factory()

   -- these fds have been permanently added to the poll set (instead of
   -- adding/removing at every poll as it happens for one-shot polls)
   local registered_fds = {}

   function self.poller_add(fd, events)
      assert(registered_fds[fd]==nil)
      local event_id = self.make_event_id()
      poller:add(fd, events, event_id)
      registered_fds[fd] = event_id
   end

   function self.poller_del(fd)
      local event_id = registered_fds[fd]
      assert(event_id)
      poller:del(fd)
      registered_fds[fd] = nil
   end

   -- the poller's own fd (which is only provided by epoll on Linux so
   -- this somewhat limits the range of possible implementations)
   function self.poller_fd()
      return poller:fd()
   end

   -- suspend the calling thread until there is an event on `fd` which
   -- matches `events`
   function self.poll(fd, events)
      assert(type(events)=="string")
      local rcvd_events
      local event_id = registered_fds[fd]
      if event_id then
         repeat
            rcvd_events = self.wait(event_id)
         until poller:match_events(events, rcvd_events)
      else
         events = events.."1" -- one shot
         event_id = self.make_event_id()
         -- the event_id lets us differentiate between threads which
         -- are all polling the same file descriptor
         poller:add(fd, events, event_id)
         rcvd_events = self.wait(event_id)
         poller:del(fd, events, event_id)
      end
      return rcvd_events
   end

   local module_registry = ModuleRegistry(self)

   -- runnable threads are those which can be resumed in the current tick
   local runnables = adt.List()

   -- each runnable consists of a callable (of some sort) and one piece of data
   local function Runnable(r, data)
      return { r = r, data = data }
   end

   -- sleeping threads are waiting for their time to come
   -- the list is ordered by wake-up time
   local sleeping = adt.OrderedList(function(st) return st.time end)

   local function SleepingRunnable(r, time)
      return { r = r, time = time }
   end

   -- `waiting` is a registry of runnables which are currently waiting
   -- for various events
   --
   -- key: evtype, value: array of runnables
   --
   -- a runnable can be a thread, a background thread or a function
   local waiting = {}
   local n_waiting_threads = 0

   local function add_waiting(evtype, r) -- r = runnable
      if not waiting[evtype] then
         waiting[evtype] = adt.List()
      end
      waiting[evtype]:push(r)
      if type(r)=="thread" then
         n_waiting_threads = n_waiting_threads + 1
      end
   end

   local function del_waiting(evtype, r) -- r = runnable
      if waiting[evtype] then
         local rs = waiting[evtype]
         local i = rs:index(r)
         if i then
            rs:remove_at(i)
            if type(r)=="thread" then
               n_waiting_threads = n_waiting_threads - 1
            end
         end
         if waiting[evtype]:empty() then
            waiting[evtype] = nil
         end
      end
   end

   -- use sched.on(evtype, fn) to register an event callback
   self.on = add_waiting
   self.off = del_waiting

   -- one cycle (tick) of the event loop:
   --
   -- 1. collects events and pushes them to the event queue
   -- 2. processes all events in the event queue
   -- 3. gives all active threads a chance to run (resume)
   local event_queue = adt.List()

   -- event_sub: the socket we receive events from
   -- C threads can use this socket to post events
   local event_sub = nn.socket(nn.AF_SP, nn.SUB)
   nn.setsockopt(event_sub, nn.SUB, nn.SUB_SUBSCRIBE, "")
   nn.bind(event_sub, "inproc://events")

   -- setup permanent polling for event_sub
   local event_sub_fd = nn.getsockopt(event_sub, 0, nn.RCVFD)
   local event_sub_id = self.make_event_id()
   poller:add(event_sub_fd, "r", event_sub_id)

   -- tick: one iteration of the event loop
   local function tick() 
      local now = get_current_time()
      self.now = now

      local function wakeup_sleepers(now)
         while not sleeping:empty() and sleeping[0].time <= now do
            local sr = sleeping:shift()
            runnables:push(Runnable(sr.r, nil))
         end
      end

      -- wake up sleeping threads whose time has come
      wakeup_sleepers(now)

      -- let all registered scheduler modules do their `tick`
      module_registry:invoke('tick')

      local function handle_poll_event(events, userdata)
         if userdata == event_sub_id then
            local event = nn.recv(event_sub)
            local unpacked = msgpack.unpack(event)
            assert(type(unpacked) == "table")
            assert(#unpacked == 2, "event shall be a table of two elements, but it is "..inspect(unpacked))
            event_queue:push(unpacked)
         else
            -- evtype: userdata, evdata: events
            event_queue:push({userdata, events})
         end
      end

      local function poll_events()
         if runnables:empty() and event_queue:empty() then
            -- there are no runnable threads, the event queue is empty
            -- we poll for events using a timeout to avoid busy-waiting
            local wait_until = now + 1 -- default timeout: 1 second
            if not sleeping:empty() then
               -- but may be shorter (or longer)
               -- if there are sleeping threads
               wait_until = sleeping[0].time
            end
            local timeout_ms = (wait_until - now) * 1000 -- sec -> ms
            -- if the thread's time comes sooner than 1 ms,
            -- we round up to 1 ms (the granularity of epoll)
            if timeout_ms < 1 then
               timeout_ms = 1
            end
            -- round to a whole number
            timeout_ms = math.floor(timeout_ms+0.5)
            -- poller invokes handle_poll_event() for each event
            poller:wait(timeout_ms, handle_poll_event)
         else
            -- there are runnable threads waiting for execution
            -- or the event queue is not empty
            --
            -- let's poll in a non-blocking way
            poller:wait(0, handle_poll_event)
         end
      end

      -- poll for events, transfer them to the event queue
      poll_events()

      local function process_event(event)
         local evtype, evdata = unpack(event)
         --pf("got event: evtype=%s, evdata=%s", evtype, inspect(evdata))
         -- wake up runnables waiting for this evtype
         local rs = waiting[evtype]
         if rs then
            local rs_next = adt.List()
            for r in rs:itervalues() do
               if type(r)=="thread" then
                  -- plain thread
                  runnables:push(Runnable(r, evdata))
                  n_waiting_threads = n_waiting_threads - 1
               elseif type(r)=="table" then
                  -- background thread in r[1]
                  runnables:push(Runnable(r, evdata))
               elseif type(r)=="function" then
                  -- callback: every event creates a new thread which
                  -- executes the callback function
                  local function wrapper(evdata)
                     -- remove the callback if it returns sched.OFF
                     -- quit handlers are also automatically removed
                     if r(evdata) == OFF or evtype == 'quit' then
                        del_waiting(evtype, r)
                     end
                  end
                  self.sched(wrapper, evdata)
                  -- callbacks keep waiting
                  -- (unless they are quit callbacks)
                  if evtype ~= 'quit' then
                     rs_next:push(r)
                  end
               else
                  ef("invalid object in waiting[%s]: %s", evtype, r)
               end
            end
            if rs_next:empty() then
               waiting[evtype] = nil
            else
               waiting[evtype] = rs_next
            end
         end
      end

      -- process the event queue
      while not event_queue:empty() do
         local event = event_queue:shift()
         process_event(event)
      end

      local function resume_runnables()
         local runnables_next = adt.List()
         for runnable in runnables:itervalues() do
            local r, data = runnable.r, runnable.data
            local is_background = (type(r)=="table")
            local t = is_background and r[1] or r
            local ok, rv = coroutine.resume(t, data)
            local status = coroutine.status(t)
            if status == "suspended" then
               if type(rv) == "number" and rv > 0 then
                  -- the coroutine shall be resumed at the given time
                  sleeping:push(SleepingRunnable(r, rv))
               elseif rv then
                  -- rv is the evtype which shall wake up this thread
                  add_waiting(rv, r)
               else
                  -- the coroutine shall be resumed in the next tick
                  runnables_next:push(Runnable(r, nil))
               end
            elseif status == "dead" then
               if not ok then
                  error(rv, 0)
               else
                  -- the coroutine finished its execution
               end
            else
               ef("unhandled status returned from coroutine.status(): %s", status)
            end
         end
         runnables = runnables_next
      end

      -- give each active thread a chance to run
      resume_runnables()
   end

   function self.loop()
      -- phase: running
      scheduler_state = "running"
      while scheduler_state == "running" do
         tick()
         if runnables:empty()
            and sleeping:empty()
            and n_waiting_threads == 0 then
               -- all threads exited without anyone calling
               -- sched.quit(), so we have to do it
               self.quit()
         end
      end
      -- phase: shutdown
      while not runnables:empty() or waiting['quit'] do
         tick()
      end
   end

   local function to_function(x)
      if type(x)=="function" then
         return x
      elseif getmetatable(x).__call then
         -- it's a callable object
         local callable = x
         return function(...)
            callable(...)
         end
      else
         ef("expected a callable, got: %s", x)
      end
   end

   function self.sched(fn, data)
      if fn then
         -- add fn to the list of runnable threads
         local t = coroutine.create(to_function(fn))
         runnables:push(Runnable(t, data))
      else
         -- enter the event loop, continue scheduling until there is
         -- work to do. when the event loop exits, cleanup and destroy
         -- this scheduler instance.
         scheduler_state = "init"
         module_registry:invoke('init')
         local ok, err = pcall(self.loop)
         scheduler_state = "done"
         module_registry:invoke('done')
         poller:del(event_sub_fd, "r", event_sub_id)
         poller:close()
         nn.close(event_sub)
         event_queue:clear()
         scheduler_singleton = nil
         scheduler_state = "off"
         if not ok then
            error(err, 0)
         end
         -- after this function returns, the current scheduler
         -- instance will be garbage-collected
         self.check_clean_shutdown()
      end
   end

   function self.check_clean_shutdown()
      for fd,event_id in pairs(registered_fds) do
         pf("WARNING: sched.registered_fds is not empty at scheduler shutdown")
         break
      end
      if not runnables:empty() then
         pf("WARNING: sched.runnables is not empty at scheduler shutdown")
      end
      if not sleeping:empty() then
         pf("WARNING: sched.sleeping is not empty at scheduler shutdown")
      end
      if n_waiting_threads > 0 then
         pf("WARNING: n_waiting_threads=%d at scheduler shutdown", n_waiting_threads)
      end
      -- background threads and functions (callbacks) left in waiting are ok
      if not event_queue:empty() then
         pf("WARNING: sched.event_queue is not empty at scheduler shutdown")
      end
   end

   function self.background(fn, data)
      -- background threads do not keep the event loop alive
      -- (they do not increase n_waiting_threads when they block)
      local t = coroutine.create(to_function(fn))
      runnables:push(Runnable({t}, data))
   end

   self.yield = coroutine.yield
   self.wait = coroutine.yield

   function self.sleep(seconds)
      return self.wait(get_current_time() + seconds)
   end

   function self.emit(evtype, evdata)
      assert(evdata ~= nil, "evdata must be non-nil")
      event_queue:push({ evtype, evdata })
   end

   function self.quit(evdata)
      scheduler_state = "shutdown"
      self.emit('quit', evdata or 0)
   end

   return self
end

local function get_scheduler()
   if not scheduler_singleton then
      scheduler_singleton = Scheduler()
   end
   return scheduler_singleton
end

local M_mt = {}

-- all lookups are proxied to the singleton Scheduler instance
function M_mt:__index(k)
   return get_scheduler()[k]
end

function M_mt:__call(...)
   return get_scheduler().sched(...)
end

return setmetatable(M, M_mt)
