local ffi = require('ffi')
local sched = require('sched')
local util = require('util')

if ffi.abi("32bit") then
   ffi.cdef "typedef uint32_t __UWORD_TYPE"
   ffi.cdef "typedef int32_t  __SWORD_TYPE"
elseif ffi.abi("64bit") then
   ffi.cdef "typedef uint64_t __UWORD_TYPE"
   ffi.cdef "typedef int64_t  __SWORD_TYPE"
else
   ef("unsupported architecture")
end

-- commonly used C types, constants and functions

ffi.cdef [[

typedef     uint64_t dev_t;
typedef     uint32_t uid_t;
typedef     uint32_t gid_t;
typedef __UWORD_TYPE ino_t;
typedef     uint64_t ino64_t;
typedef     uint32_t mode_t;
typedef __UWORD_TYPE nlink_t;
typedef __SWORD_TYPE fsword_t;
typedef __SWORD_TYPE off_t;
typedef      int64_t off64_t;
typedef __UWORD_TYPE rlim_t;
typedef     uint64_t rlim64_t;
typedef __SWORD_TYPE blkcnt_t;
typedef      int64_t blkcnt64_t;
typedef __UWORD_TYPE fsblkcnt_t;
typedef     uint64_t fsblkcnt64_t;
typedef __UWORD_TYPE fsfilcnt_t;
typedef     uint64_t fsfilcnt64_t;
typedef     uint32_t id_t;
typedef      int32_t daddr_t;
typedef      int32_t key_t;
typedef __SWORD_TYPE blksize_t;
typedef __SWORD_TYPE ssize_t;

void * malloc (size_t size);
void * calloc (size_t count, size_t eltsize);
void   free   (void *ptr);

enum {
  O_RDONLY    = 00000000,
  O_WRONLY    = 00000001,
  O_RDWR      = 00000002,
  O_ACCMODE   = 00000003,
  O_CREAT     = 00000100,
  O_EXCL      = 00000200,
  O_NOCTTY    = 00000400,
  O_TRUNC     = 00001000,
  O_APPEND    = 00002000,
  O_NONBLOCK  = 00004000,
  O_SYNC      = 04010000,
  O_ASYNC     = 00020000,
  O_DIRECT    = 00040000,
  O_LARGEFILE = 00100000,
  O_DIRECTORY = 00200000,
  O_NOFOLLOW  = 00400000,
  O_NOATIME   = 01000000,
  O_CLOEXEC   = 02000000
};

enum {
  SEEK_SET = 0,
  SEEK_CUR = 1,
  SEEK_END = 2
};

ssize_t read  (int fd, void *buf, size_t size);
ssize_t write (int fd, const void *buf, size_t size);
int     close (int fd);

/* sys/ioctl.h */

int ioctl(int fd, int cmd, ...);

/* fcntl.h */

int fcntl(int fd, int cmd, ...);

enum {
  F_DUPFD = 0,
  F_GETFD = 1,
  F_SETFD = 2,
  F_GETFL = 3,
  F_SETFL = 4
};

]]

-- global definitions

_G.sf = string.format

function _G.pf(fmt, ...)
   print(string.format(fmt, ...))
end

function _G.ef(fmt, ...)
   local message = string.format(fmt, ...)
   util.throwat(2, nil, message)
end
