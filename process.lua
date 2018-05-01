local ffi = require('ffi')
local util = require('util')
local net = require('net')
local stream = require('stream')
local sched = require('sched')
local async = require('async')
local mm = require('mm')

ffi.cdef [[

typedef int pid_t;

/* process identification */

pid_t getpid ();
pid_t getppid ();

/* process creation */

pid_t fork ();

/* execution */

int system (const char *command);
int execv (const char *filename,
           char *const argv[]);
int execl (const char *filename,
           const char *arg0,
           ...);
int execve (const char *filename,
            char *const argv[],
            char *const env[]);
int execvp (const char *filename,
            char *const argv[]);
int execlp (const char *filename,
            const char *arg0,
            ...);

/* process completion */

void exit (int);
int kill (pid_t pid, int signum);
pid_t waitpid (pid_t pid, int *statusptr, int options);

/* process state */

char *getcwd (char *buf, size_t size);
int chdir (const char *path);

/* file descriptors */

int dup (int old);
int dup2 (int old, int new);

/* umask */

mode_t umask (mode_t mask);

/* async worker */

enum {
  ZZ_ASYNC_PROCESS_WAITPID
};

struct zz_async_process_waitpid {
  pid_t pid;
  int status;
  int options;
  pid_t rv;
};

void *zz_async_process_handlers[];

]]

local M = {}

local ASYNC_PROCESS = async.register_worker(ffi.C.zz_async_process_handlers)

function M.getpid()
   return ffi.C.getpid()
end

function M.fork(child_fn)
   if child_fn then
      -- sp: parent side
      -- sc: child side
      local sp, sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM, 0)
      sp = stream(sp)
      sc = stream(sc)
      local pid = util.check_errno("fork", ffi.C.fork())
      if pid == 0 then
         -- child
         sp:close()
         child_fn(sc)
         sc:close()
         M.exit(0)
      else
         -- parent
         sc:close()
         return pid, sp
      end
   else
      return util.check_errno("fork", ffi.C.fork())
   end
end

function M.execvp(path, argv)
   -- stringify args
   for i=1,#argv do
      argv[i] = tostring(argv[i])
   end
   -- build const char* argv[] for execvp()
   local execvp_argv = ffi.new("char*[?]", #argv+1)
   for i=1,#argv do
      execvp_argv[i-1] = ffi.cast("char*", argv[i])
   end
   execvp_argv[#argv] = nil
   -- if execvp() is successful, the following call shall not return
   util.check_errno("execvp", ffi.C.execvp(path, execvp_argv))
end

function M.kill(pid, signum)
   pid = pid or M.getpid()
   return ffi.C.kill(pid, signum)
end

local function extract_status(status)
   -- see /usr/include/bits/waitstatus.h
   local ret = bit.rshift(status, 8)
   local sig = bit.band(status, 0x7f)
   return ret, sig
end

function M.waitpid(pid, options)
   options = options or 0
   if sched.ticking() then
      local req, block_size = mm.get_block("struct zz_async_process_waitpid")
      req.pid = pid
      req.options = options
      async.request(ASYNC_PROCESS, ffi.C.ZZ_ASYNC_PROCESS_WAITPID, req)
      util.check_errno("waitpid", req.rv)
      mm.ret_block(req, block_size)
      return req.rv, extract_status(req.status)
   else
      local status = ffi.new("int[1]")
      local rv = util.check_errno("waitpid", ffi.C.waitpid(pid, status, options))
      return rv, extract_status(status[0])
   end
end

function M.create(opts)
   local self = {}

   if type(opts) == "string" then
      opts = { command = opts }
   end
   if type(opts.command) == "string" then
      -- string commands are executed via the system shell
      opts.command = { "/bin/sh", "-c", opts.command }
   end
   assert(opts.command and type(opts.command) == "table")

   local function is_channel(x)
      return type(x) == "table" and x.is_channel
   end

   local function Channel(owner, name, fd, direction)
      local self = {
         is_channel = true,
         has_peer = false
      }

      function self:materialize(has_peer)
         self.has_peer = has_peer or false
         if not self.sp then
            self.sp, self.sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM, 0)
         end
      end

      function self:socket()
         assert(not self.has_peer)
         self:materialize()
         return self.sp
      end

      function self:stream_impl(stream)
         return self:socket():stream_impl(stream)
      end

      local function create_writer(input)
         if input == nil or type(input) == "function" then
            return input
         elseif type(input) == "string" then
            return function(istream)
               istream:write(input)
            end
         elseif stream.is_stream(input) then
            return function(istream)
               stream.pipe(input, istream)
            end
         else
            ef("invalid input")
         end
      end

      local function create_reader(output)
         if output == nil or type(output) == "function" then
            return output
         elseif stream.is_stream(output) then
            return function(ostream)
               stream.pipe(ostream, output)
            end
         else
            ef("invalid output")
         end
      end

      local peer = opts[name]

      if direction == "out" and peer == "capture" then
         peer = function(ostream)
            owner[name] = ostream:read(0)
         end
      end

      if peer then
         if is_channel(peer) then
            peer:materialize(true)
         else
            self:materialize()
            if direction == "in" then
               self.pump = create_writer(peer)
            elseif direction == "out" then
               self.pump = create_reader(peer)
            else
               ef("invalid direction")
            end
         end
      end

      function self:setup_in_child()
         if is_channel(peer) then
            peer.sp.O_NONBLOCK = false
            assert(ffi.C.dup2(peer.sp.fd, fd) == fd)
         elseif self.sp then
            if self.has_peer then
               -- closing sp would disrupt communication with peer
            else
               self.sp:close()
            end
            self.sc.O_NONBLOCK = false
            assert(ffi.C.dup2(self.sc.fd, fd) == fd)
         end
      end

      function self:setup_in_parent()
         if self.sc then
            self.sc:close()
            if self.pump then
               self.pump_thread = sched(function()
                  self.pump(stream(self))
                  self:close()
               end)
            end
         end
      end

      function self:close()
         if self.sp then
            self.sp:close()
            self.sp = nil
            self.sc = nil
         end
      end

      return self
   end

   -- Channel(owner, name, fd, direction)
   self.stdin = Channel(self, "stdin", 0, "in")
   self.stdout = Channel(self, "stdout", 1, "out")
   self.stderr = Channel(self, "stderr", 2, "out")

   local channels = {
      self.stdin,
      self.stdout,
      self.stderr
   }

   function self:start()
      self.pid = util.check_errno("fork", ffi.C.fork())
      if self.pid == 0 then
         if type(opts.pre_exec) == "function" then
            opts.pre_exec()
         end
         for _,channel in ipairs(channels) do
            channel:setup_in_child()
         end
         M.execvp(opts.command[1], opts.command)
         ef("execvp failed")
      else
         for _,channel in ipairs(channels) do
            channel:setup_in_parent()
         end
      end
      return self
   end

   function self:wait(skip_close)
      if not self.pid then
         self:start()
      end
      local pump_threads = {}
      for _,channel in ipairs(channels) do
         if channel.pump_thread then
            table.insert(pump_threads, channel.pump_thread)
         end
      end
      sched.join(pump_threads)
      local wpid, exit_status, term_signal = M.waitpid(self.pid)
      assert(wpid == self.pid)
      self.exit_status = exit_status
      self.term_signal = term_signal
      if not skip_close then
         self:close()
      end
      return self 
   end

   function self:close()
      for _,channel in ipairs(channels) do
         channel:close()
      end
   end

   local mt = {
      __gc = self.close
   }

   return setmetatable(self, mt)
end

function M.start(opts)
   return M.create(opts):start()
end

function M.system(command)
   local opts = {
      command = command
   }
   local p = M.create(opts):wait()
   return p.exit_status
end

function M.capture(command)
   local opts = {
      command = command,
      stdout = "capture",
      stderr = "capture",
   }
   local p = M.create(opts):wait()
   return p.exit_status, p.stdout, p.stderr
end

function M.Group()
   local self = {
      processes = {}
   }
   function self:create(...)
      local p = M.create(...)
      table.insert(self.processes, p)
      return p
   end
   function self:wait()
      for _,p in ipairs(self.processes) do
         p:wait(true)
      end
      for _,p in ipairs(self.processes) do
         p:close()
      end
   end
   return self
end

function M.getcwd()
   local buf = ffi.C.getcwd(nil, 0)
   local cwd = ffi.string(buf)
   ffi.C.free(buf)
   return cwd
end

function M.chdir(path)
   return util.check_ok("chdir", 0, ffi.C.chdir(path))
end

function M.exit(status)
   ffi.C.exit(status or 0)
end

function M.umask(umask)
   local prev_umask = ffi.C.umask(umask or 0)
   if not umask then
      -- getter: revert to previous value
      ffi.C.umask(prev_umask)
   end
   return prev_umask
end

return M
