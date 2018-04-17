local ffi = require('ffi')
local sched = require('sched')

-- commonly used C types and functions

ffi.cdef [[

typedef long int ssize_t;

/* types of struct stat fields */

typedef unsigned long long int __dev_t;
typedef unsigned long int __ino_t;
typedef unsigned int __mode_t;
typedef unsigned int __nlink_t;
typedef unsigned int __uid_t;
typedef unsigned int __gid_t;
typedef long int __off_t;
typedef long int __blksize_t;
typedef long int __blkcnt_t;

typedef __off_t off_t; /* TODO: this is not correct */

void *malloc (size_t size);
void *calloc (size_t count, size_t eltsize);
void free (void *ptr);

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

ssize_t read (int FILEDES, void *BUFFER, size_t SIZE);
ssize_t write (int FILEDES, const void *BUFFER, size_t SIZE);
int close (int FILEDES);

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
   local msg = string.format(fmt, ...)
   if sched.ticking() then
      -- append stack trace of the current thread
      msg = sf("%s%s", msg, debug.traceback("", 2))
   end
   error(msg, 2)
end

-- we define Point, Rect, Size and Color here so that users don't have
-- to pull in the SDL module if all they need are these structs

ffi.cdef [[

typedef struct SDL_Point {
  int x, y;
} SDL_Point;

typedef struct SDL_Rect {
  int x, y;
  int w, h;
} SDL_Rect;

typedef struct zz_size {
  int w, h;
} zz_size;

typedef struct SDL_Color {
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
} SDL_Color;

]]

-- Point

local Point_mt = {}

function Point_mt:__tostring()
   return sf("Point(%d,%d)", self.x, self.y)
end

_G.Point = ffi.metatype("SDL_Point", Point_mt)

-- Rect

local Rect_mt = {}

function Rect_mt:__tostring()
   return sf("Rect(%d,%d,%d,%d)",
             self.x, self.y,
             self.w, self.h)
end

function Rect_mt:update(x,y,w,h)
   self.x = x or self.x
   self.y = y or self.y
   self.w = w or self.w
   self.h = h or self.h
end

function Rect_mt:clear()
   self:update(0,0,0,0)
end

_G.Rect = ffi.metatype("SDL_Rect", Rect_mt)

-- Size

local Size_mt = {}

function Size_mt:__tostring()
   return sf("Size(%d,%d)", self.w, self.h)
end

function Size_mt:update(w,h)
   self.w = w or self.w
   self.h = h or self.h
end

function Size_mt:clear()
   self:update(0,0)
end

_G.Size = ffi.metatype("zz_size", Size_mt)

-- Color

local Color_mt = {}

function Color_mt:bytes()
   return self.r, self.g, self.b, self.a
end

function Color_mt:floats()
   return self.r/255, self.g/255, self.b/255, self.a/255
end

function Color_mt:u32be()
   return
      bit.lshift(self.r, 24) +
      bit.lshift(self.g, 16) +
      bit.lshift(self.b, 8) +
      bit.lshift(self.a, 0)
end

function Color_mt:u32le()
   return
      bit.lshift(self.r, 0) +
      bit.lshift(self.g, 8) +
      bit.lshift(self.b, 16) +
      bit.lshift(self.a, 24)
end

function Color_mt:u32()
   return ffi.abi("le") and self:u32le() or self:u32be()
end

Color_mt.__index = Color_mt

_G.Color = ffi.metatype("SDL_Color", Color_mt)
