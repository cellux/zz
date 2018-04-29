local ffi = require('ffi')
local util = require('util')
local net = require('net')
local stream = require('stream')

ffi.cdef [[

typedef int __pid_t;
typedef __pid_t pid_t;

/* process identification */

pid_t getpid ();
pid_t getppid ();

/* process creation */

pid_t fork ();

/* execution */

int system (const char *COMMAND);
int execv (const char *FILENAME,
           char *const ARGV[]);
int execl (const char *FILENAME,
           const char *ARG0,
           ...);
int execve (const char *FILENAME,
            char *const ARGV[],
            char *const ENV[]);
int execvp (const char *FILENAME,
            char *const ARGV[]);
int execlp (const char *FILENAME,
            const char *ARG0,
            ...);

/* process completion */

void exit (int);
int kill (pid_t pid, int signum);
pid_t waitpid (pid_t PID, int *STATUSPTR, int OPTIONS);

/* process state */

char *getcwd (char *buf, size_t size);
int chdir (const char *path);

/* file descriptors */

int     dup (int old);
int     dup2 (int old, int new);

/* umask */

__mode_t umask (__mode_t mask);

]]

local M = {}

function M.getpid()
   return ffi.C.getpid()
end

function M.fork(child_fn)
   if child_fn then
      local sp, sc = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM, 0)
      sp = stream(sp)
      sc = stream(sc)
      local pid = util.check_errno("fork", ffi.C.fork())
      if pid == 0 then
         sp:close()
         child_fn(sc)
         sc:close()
         M.exit(0)
      else
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
   -- if execvp() is successful, the following call doesn't return
   util.check_errno("execvp", ffi.C.execvp(path, execvp_argv))
end

function M.system(command)
   if type(command) == "string" then
      local status = ffi.C.system(command)
      -- see /usr/include/bits/waitstatus.h
      return bit.rshift(status, 8)
   elseif type(command) == "table" then
      local pid = util.check_errno("fork", ffi.C.fork())
      if pid == 0 then
         M.execvp(command[1], command)
      else
         local wpid, ret, sig = M.waitpid(pid)
         assert(wpid==pid)
         return ret, sig
      end
   else
      ef("system(): invalid command: %s", command)
   end
end

function M.kill(pid, signum)
   if not pid or pid == 0 then
      pid = M.getpid()
   end
   return ffi.C.kill(pid, signum)
end

function M.waitpid(pid, options)
   options = options or 0
   local status = ffi.new("int[1]")
   local rv = util.check_errno("waitpid", ffi.C.waitpid(pid, status, options))
   status = tonumber(status[0])
   local ret = bit.rshift(status, 8)
   local sig = bit.band(status, 0x7f)
   return rv, ret, sig
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
