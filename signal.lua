local ffi = require('ffi')
local process = require('process')
local util = require('util')
local sched = require('sched')
local pthread = require('pthread')

ffi.cdef [[

typedef struct {
  unsigned long int __val[(1024 / (8 * sizeof (unsigned long int)))];
} __sigset_t;
typedef __sigset_t sigset_t;

int sigemptyset (sigset_t *__set);
int sigfillset (sigset_t *__set);
int sigaddset (sigset_t *__set, int __signo);
int sigdelset (sigset_t *__set, int __signo);
int sigismember (const sigset_t *__set, int __signo);

int pthread_sigmask(int how, const sigset_t *set, sigset_t *oldset);

void *zz_signal_handler_thread(void *arg);

]]

local SIG_BLOCK   = 0
local SIG_UNBLOCK = 1
local SIG_SETMASK = 2

local M = {}

M.SIGHUP    = 1
M.SIGINT    = 2
M.SIGQUIT   = 3
M.SIGILL    = 4
M.SIGTRAP   = 5
M.SIGABRT   = 6
M.SIGBUS    = 7
M.SIGFPE    = 8
M.SIGKILL   = 9
M.SIGUSR1   = 10
M.SIGSEGV   = 11
M.SIGUSR2   = 12
M.SIGPIPE   = 13
M.SIGALRM   = 14
M.SIGTERM   = 15
M.SIGSTKFLT = 16
M.SIGCHLD   = 17
M.SIGCONT   = 18
M.SIGSTOP   = 19
M.SIGTSTP   = 20
M.SIGTTIN   = 21
M.SIGTTOU   = 22
M.SIGURG    = 23
M.SIGXCPU   = 24
M.SIGXFSZ   = 25
M.SIGVTALRM = 26
M.SIGPROF   = 27
M.SIGWINCH  = 28
M.SIGIO     = 29
M.SIGPWR    = 30
M.SIGSYS    = 31

local function sigmask(how, signum)
   local ss = ffi.new('sigset_t')
   if signum then
      ffi.C.sigemptyset(ss)
      ffi.C.sigaddset(ss, signum)
   else
      ffi.C.sigfillset(ss)
   end
   return util.check_ok("pthread_sigmask", 0,
                        ffi.C.pthread_sigmask(how, ss, nil))
end

function M.block(signum)
   return sigmask(SIG_BLOCK, signum)
end

function M.unblock(signum)
   return sigmask(SIG_UNBLOCK, signum)
end

local function SignalModule(sched)
   local self = {}

   local signal_handler_thread_id = ffi.new("pthread_t[1]")
   signal_handler_thread_id[0] = 0

   local function start_signal_handler_thread()
      assert(signal_handler_thread_id[0] == 0)
      -- we handle signals in a dedicated thread which sends an event to
      -- the Lua scheduler when a signal arrives
      local rv = ffi.C.pthread_create(signal_handler_thread_id,
                                      nil,
                                      ffi.C.zz_signal_handler_thread,
                                      nil)
      if rv ~= 0 then
         error("cannot create signal handler thread: pthread_create() failed")
      end
      assert(signal_handler_thread_id[0] ~= 0)
   end

   local function stop_signal_handler_thread()
      assert(signal_handler_thread_id[0] ~= 0)
      -- signal handler thread exits upon receiving SIGALRM
      -- pid == nil means send the signal to ourselves
      process.kill(nil, M.SIGALRM)
      local retval = ffi.new("void*[1]")
      local rv = ffi.C.pthread_join(signal_handler_thread_id[0], retval)
      if rv ~=0 then
         error("cannot join signal handler thread: pthread_join() failed")
      end
      signal_handler_thread_id[0] = 0
   end

   local function signal_handler(data)
      local signum, pid = unpack(data)
      --print(sf("got signal %d from pid %d", signum, pid))
      if signum == M.SIGTERM or signum == M.SIGINT then
         sched.quit()
      end
   end

   function self.init()
      M.block()
      sched.on('signal', signal_handler)
      start_signal_handler_thread()
   end

   function self.done()
      stop_signal_handler_thread()
      sched.off('signal', signal_handler)
      M.unblock()
   end

   return self
end

sched.register_module(SignalModule)

return M
