local ffi = require('ffi')
local sched = require('sched')
local async = require('async')
local process = require('process')
local buffer = require('buffer')
local mm = require('mm')
local time = require('time') -- for struct timespec
local env = require('env')
local errno = require('errno')
local inspect = require('inspect')
local util = require('util')
local stream = require('stream')

ffi.cdef [[

int     open  (const char *file, int oflag, mode_t mode);
ssize_t read  (int fd, void *buf, size_t nbytes);
ssize_t write (int fd, const void *buf, size_t n);
off_t   lseek (int fd, off_t offset, int whence);
int     close (int fd);

struct zz_fs_File_ct {
  int fd;
};

/* change file timestamps with nanosecond precision */

int futimens(int fd, const struct timespec times[2]);

/* creation of temporary files/directories */

int    mkstemp (char *template);
char * mkdtemp (char *template);

enum {
  R_OK = 4,
  W_OK = 2,
  X_OK = 1,
  F_OK = 0
};

int     access   (const char *path, int how);
int     chmod    (const char *file, mode_t mode);
int     unlink   (const char *filename);
int     mkdir    (const char *file, mode_t mode);
int     rmdir    (const char *filename);

int     symlink  (const char *oldname, const char *newname);
ssize_t readlink (const char *filename, char *buffer, size_t size);
char   *realpath (const char *name, char *resolved);

char   *dirname  (char *path);
char   *basename (char *path);

struct zz_fs_Stat_ct {
  struct stat *buf;
};

struct stat *     zz_fs_Stat_new();
dev_t             zz_fs_Stat_dev(struct stat *);
ino_t             zz_fs_Stat_ino(struct stat *);
mode_t            zz_fs_Stat_mode(struct stat *);
mode_t            zz_fs_Stat_type(struct stat *buf);
mode_t            zz_fs_Stat_perms(struct stat *buf);
nlink_t           zz_fs_Stat_nlink(struct stat *);
uid_t             zz_fs_Stat_uid(struct stat *);
gid_t             zz_fs_Stat_gid(struct stat *);
dev_t             zz_fs_Stat_rdev(struct stat *);
off_t             zz_fs_Stat_size(struct stat *);
blksize_t         zz_fs_Stat_blksize(struct stat *);
blkcnt_t          zz_fs_Stat_blocks(struct stat *);
struct timespec * zz_fs_Stat_atime(struct stat *);
struct timespec * zz_fs_Stat_mtime(struct stat *);
struct timespec * zz_fs_Stat_ctime(struct stat *);
void              zz_fs_Stat_free(struct stat *);

int zz_fs_stat  (const char *path, struct stat *buf);
int zz_fs_lstat (const char *path, struct stat *buf);

typedef struct __dirstream DIR;

struct zz_fs_Dir_ct {
  DIR *dir;
};

DIR * opendir(const char *path);
struct dirent * readdir (DIR *dir);
int closedir (DIR *dir);

/* glob flags */

enum {
  GLOB_ERR         = (1 << 0),  /* Return on read errors.  */
  GLOB_MARK        = (1 << 1),  /* Append a slash to each name.  */
  GLOB_NOSORT      = (1 << 2),  /* Don't sort the names.  */
  GLOB_DOOFFS      = (1 << 3),  /* Insert PGLOB->gl_offs NULLs.  */
  GLOB_NOCHECK     = (1 << 4),  /* If nothing matches, return the pattern.  */
  GLOB_APPEND      = (1 << 5),  /* Append to results of a previous call.  */
  GLOB_NOESCAPE    = (1 << 6),  /* Backslashes don't quote metacharacters.  */
  GLOB_PERIOD      = (1 << 7),  /* Leading `.' can be matched by metachars.  */
  GLOB_MAGCHAR     = (1 << 8),  /* Set in gl_flags if any metachars seen.  */
  GLOB_ALTDIRFUNC  = (1 << 9),  /* Use gl_opendir et al functions.  */
  GLOB_BRACE       = (1 << 10), /* Expand "{a,b}" to "a" "b".  */
  GLOB_NOMAGIC     = (1 << 11), /* If no magic chars, return the pattern.  */
  GLOB_TILDE       = (1 << 12), /* Expand ~user and ~ to home directories. */
  GLOB_ONLYDIR     = (1 << 13), /* Match only directories.  */
  GLOB_TILDE_CHECK = (1 << 14)  /* Like GLOB_TILDE but return an error
                                   if the user name is not available.  */
};

/* glob errors */

enum {
  GLOB_NOSPACE = 1, /* Ran out of memory.  */
  GLOB_ABORTED = 2, /* Read error.         */
  GLOB_NOMATCH = 3, /* No matches found.   */
  GLOB_NOSYS   = 4  /* Not implemented.    */
};

typedef struct {
  size_t gl_pathc;  /* Count of paths matched by the pattern.  */
  char **gl_pathv;  /* List of matched pathnames.  */
  size_t gl_offs;   /* Slots to reserve in `gl_pathv'.  */
  int gl_flags;     /* Set to FLAGS, maybe | GLOB_MAGCHAR.  */

  void   (*gl_closedir) (void *);
  void * (*gl_readdir)  (void *);
  void * (*gl_opendir)  (const char *);
  int    (*gl_lstat)    (const char *, void *);
  int    (*gl_stat)     (const char *, void *);
} glob_t;

int  glob     (const char *pattern, int flags, int (*errfunc) (const char *, int), glob_t *pglob);
void globfree (glob_t *pglob);

char * zz_fs_dirent_name(struct dirent *);

const char * zz_fs_type(mode_t mode);

/* async worker */

enum {
  ZZ_ASYNC_FS_LSEEK,
  ZZ_ASYNC_FS_READ,
  ZZ_ASYNC_FS_WRITE,
  ZZ_ASYNC_FS_CLOSE,
  ZZ_ASYNC_FS_STAT,
  ZZ_ASYNC_FS_LSTAT
};

void *zz_async_fs_handlers[];

struct zz_async_fs_lseek {
  int fd;
  off_t offset;
  int whence;
  off_t rv;
};

struct zz_async_fs_read_write {
  int fd;
  void *buf;
  size_t count;
  ssize_t nbytes;
};

struct zz_async_fs_close {
  int fd;
  int rv;
};

struct zz_async_fs_stat {
  char *path;
  struct stat *buf;
  int rv;
};

]]

local PATH_MAX = 4096 -- as defined in /usr/include/linux/limits.h

local ASYNC_FS  = async.register_worker(ffi.C.zz_async_fs_handlers)

local File_mt = {}

local function lseek(fd, offset, whence)
   local rv
   if sched.ticking() then
      rv = mm.with_block("struct zz_async_fs_lseek", nil, function(req, block_size)
         req.fd = fd
         req.offset = offset
         req.whence = whence
         async.request(ASYNC_FS, ffi.C.ZZ_ASYNC_FS_LSEEK, req)
         return req.rv
      end)
   else
      rv = ffi.C.lseek(fd, offset, whence)
   end
   return util.check_errno("lseek", rv)
end

function File_mt:pos()
   return lseek(self.fd, 0, ffi.C.SEEK_CUR)
end

function File_mt:size()
   local pos = self:pos()
   local size = lseek(self.fd, 0, ffi.C.SEEK_END)
   lseek(self.fd, pos, ffi.C.SEEK_SET)
   return size
end

function File_mt:read1(ptr, size)
   local nbytes
   if sched.ticking() then
      mm.with_block("struct zz_async_fs_read_write", nil, function(req, block_size)
         req.fd = self.fd
         req.buf = ptr
         req.count = size
         async.request(ASYNC_FS, ffi.C.ZZ_ASYNC_FS_READ, req)
         nbytes = req.nbytes
      end)
   else
      nbytes = ffi.C.read(self.fd, ptr, size)
   end
   return util.check_errno("read1", nbytes)
end

function File_mt:write1(ptr, size)
   local nbytes
   if sched.ticking() then
      mm.with_block("struct zz_async_fs_read_write", nil, function(req, block_size)
         req.fd = self.fd
         req.buf = ptr
         req.count = size
         async.request(ASYNC_FS, ffi.C.ZZ_ASYNC_FS_WRITE, req)
         nbytes = req.nbytes
      end)
   else
      nbytes = ffi.C.write(self.fd, ptr, size)
   end
   return util.check_errno("write1", nbytes)
end

function File_mt:seek(offset, relative)
   if relative then
      return lseek(self.fd, offset, ffi.C.SEEK_CUR)
   elseif offset >= 0 then
      return lseek(self.fd, offset, ffi.C.SEEK_SET)
   else
      return lseek(self.fd, offset, ffi.C.SEEK_END)
   end
end

function File_mt:close()
   if self.fd >= 0 then
      local rv
      if sched.ticking() then
         rv = mm.with_block("struct zz_async_fs_close", nil, function(req, block_size)
            req.fd = self.fd
            async.request(ASYNC_FS, ffi.C.ZZ_ASYNC_FS_CLOSE, req)
            return req.rv
         end)
      else
         rv = ffi.C.close(self.fd)
      end
      util.check_errno("close", rv)
      self.fd = -1
   end
end

function File_mt:stream_impl()
   local stream = {}
   local f = self
   local eof = false
   function stream:close()
      return f:close()
   end
   function stream:eof()
      return eof
   end
   function stream:read1(ptr, size)
      local nbytes = f:read1(ptr, size)
      if nbytes == 0 then
         eof = true
      end
      return nbytes
   end
   function stream:write1(ptr, size)
      return f:write1(ptr, size)
   end
   return stream
end

File_mt.__index = File_mt
--File_mt.__gc = File_mt.close

local File = ffi.metatype("struct zz_fs_File_ct", File_mt)

local M = {}

function M.open(path, flags, mode)
   flags = flags or ffi.C.O_RDONLY
   mode = mode or util.oct("666")
   local fd = ffi.C.open(path, flags, mode)
   if fd == -1 then
      error(sf("open(%s) failed: %s", path, errno.strerror()), 2)
   else
      return File(fd)
   end
end

function M.readfile(path, rsize)
   local f = M.open(path)
   local contents = stream(f):read(rsize or 0)
   f:close()
   return contents
end

function M.writefile(path, contents)
   local flags = bit.bor(ffi.C.O_CREAT,
                         ffi.C.O_WRONLY,
                         ffi.C.O_TRUNC)
   local f = M.open(path, flags)
   stream(f):write(contents)
   f:close()
end

function M.touch(path)
   local flags = bit.bor(ffi.C.O_WRONLY,
                         ffi.C.O_CREAT,
                         ffi.C.O_NOCTTY,
                         ffi.C.O_NONBLOCK,
                         ffi.C.O_LARGEFILE)
   local f = M.open(path, flags)
   util.check_errno("futimens", ffi.C.futimens(f.fd, nil))
   f:close()
end

function M.mkstemp(filename_prefix, tmpdir)
   filename_prefix = filename_prefix or sf("%u", process.getpid())
   tmpdir = tmpdir or env.TMPDIR or '/tmp'
   local template = sf("%s/%s-XXXXXX", tmpdir, filename_prefix)
   local buf = ffi.new("char[?]", #template+1) -- zero-initialized
   ffi.copy(buf, template) -- \x00 already at the end
   local fd = util.check_errno("mkstemp", ffi.C.mkstemp(buf))
   return File(fd), ffi.string(buf)
end

function M.mktemp(...)
   local fd, path = M.mkstemp(...)
   fd:close()
   M.unlink(path)
   return path
end

local tmp_index = 0

function M.with_tmpdir(cb)
   tmp_index = tmp_index + 1
   local tmpdir = sf("%s/%s.%d.%d",
                     env.TMPDIR or '/tmp',
                     M.basename(arg[0]),
                     process.getpid(),
                     tmp_index)
   M.mkdir(tmpdir)
   local ok, err = pcall(cb, tmpdir)
   M.rmpath(tmpdir)
   if not ok then
      error(err, 2)
   end
end

-- stat

local Stat_mt = {}

function Stat_mt:stat(path)
   if sched.ticking() then
      return mm.with_block("struct zz_async_fs_stat", nil, function(req, block_size)
         req.path = ffi.cast("char*", path)
         req.buf = self.buf
         async.request(ASYNC_FS, ffi.C.ZZ_ASYNC_FS_STAT, req)
         return req.rv
      end)
   else
      return ffi.C.zz_fs_stat(path, self.buf)
   end
end

function Stat_mt:lstat(path)
   if sched.ticking() then
      return mm.with_block("struct zz_async_fs_stat", nil, function(req, block_size)
         req.path = ffi.cast("char*", path)
         req.buf = self.buf
         async.request(ASYNC_FS, ffi.C.ZZ_ASYNC_FS_LSTAT, req)
         return req.rv
      end)
   else
      return ffi.C.zz_fs_lstat(path, self.buf)
   end
end

local Stat_accessors = {
   dev = function(buf)
      return tonumber(ffi.C.zz_fs_Stat_dev(buf))
   end,
   ino = function(buf)
      return tonumber(ffi.C.zz_fs_Stat_ino(buf))
   end,
   mode = function(buf)
      return tonumber(ffi.C.zz_fs_Stat_mode(buf))
   end,
   perms = function(buf)
      return tonumber(ffi.C.zz_fs_Stat_perms(buf))
   end,
   type = function(buf)
      return tonumber(ffi.C.zz_fs_Stat_type(buf))
   end,
   nlink = function(buf)
      return tonumber(ffi.C.zz_fs_Stat_nlink(buf))
   end,
   uid = function(buf)
      return tonumber(ffi.C.zz_fs_Stat_uid(buf))
   end,
   gid = function(buf)
      return tonumber(ffi.C.zz_fs_Stat_gid(buf))
   end,
   rdev = function(buf)
      return tonumber(ffi.C.zz_fs_Stat_rdev(buf))
   end,
   size = function(buf)
      return tonumber(ffi.C.zz_fs_Stat_size(buf))
   end,
   blksize = function(buf)
      return tonumber(ffi.C.zz_fs_Stat_blksize(buf))
   end,
   blocks = function(buf)
      return tonumber(ffi.C.zz_fs_Stat_blocks(buf))
   end,
   atime = function(buf)
      local timespec = ffi.C.zz_fs_Stat_atime(buf)
      return tonumber(timespec.tv_sec) + tonumber(timespec.tv_nsec)/1000000000
   end,
   mtime = function(buf)
      local timespec = ffi.C.zz_fs_Stat_mtime(buf)
      return tonumber(timespec.tv_sec) + tonumber(timespec.tv_nsec)/1000000000
   end,
   ctime = function(buf)
      local timespec = ffi.C.zz_fs_Stat_ctime(buf)
      return tonumber(timespec.tv_sec) + tonumber(timespec.tv_nsec)/1000000000
   end,
}

function Stat_mt:__index(key)
   local accessor = Stat_accessors[key]
   if accessor then
      return accessor(self.buf)
   else
      local field = rawget(Stat_mt, key)
      if field then
         return field
      else
         ef("invalid key: %s, no such field in struct stat", key)
      end
   end
end

function Stat_mt:free()
   if self.buf ~= nil then
      ffi.C.zz_fs_Stat_free(self.buf)
      self.buf = nil
   end
end

Stat_mt.__gc = Stat_mt.free

local Stat = ffi.metatype("struct zz_fs_Stat_ct", Stat_mt)

local Dir_mt = {}

function Dir_mt:read()
   local entry = ffi.C.readdir(self.dir)
   if entry ~= nil then
      return ffi.string(ffi.C.zz_fs_dirent_name(entry))
   else
      return nil
   end
end

function Dir_mt:close()
   if self.dir ~= nil then
      util.check_ok("closedir", 0, ffi.C.closedir(self.dir))
      self.dir = nil
   end
   return 0
end

Dir_mt.__index = Dir_mt
Dir_mt.__gc = Dir_mt.close

local Dir = ffi.metatype("struct zz_fs_Dir_ct", Dir_mt)

function M.opendir(path)
   return Dir(util.check_bad("opendir", nil, ffi.C.opendir(path)))
end

function M.readdir(path)
   local dir = M.opendir(path)
   local function next()
      local entry = dir:read()
      if not entry then
         dir:close()
      end
      return entry
   end
   return next
end

function M.exists(path)
   return ffi.C.access(path, ffi.C.F_OK) == 0
end

function M.is_readable(path)
   return ffi.C.access(path, ffi.C.R_OK) == 0
end

function M.is_writable(path)
   return ffi.C.access(path, ffi.C.W_OK) == 0
end

function M.is_executable(path)
   return ffi.C.access(path, ffi.C.X_OK) == 0
end

function M.stat(path)
   local s = Stat(ffi.C.zz_fs_Stat_new())
   if s:stat(path)==0 then
      return s
   else
      return nil
   end
end

function M.lstat(path)
   local s = Stat(ffi.C.zz_fs_Stat_new())
   if s:lstat(path)==0 then
      return s
   else
      return nil
   end
end

function M.type(path)
   local s = M.lstat(path)
   return s and ffi.string(ffi.C.zz_fs_type(s.mode))
end

local function create_type_checker(typ)
   M["is_"..typ] = function(path)
      return M.type(path)==typ
   end
end

create_type_checker("reg")
create_type_checker("dir")
create_type_checker("lnk")
create_type_checker("chr")
create_type_checker("blk")
create_type_checker("fifo")
create_type_checker("sock")

function M.chmod(path, mode)
   return util.check_errno("chmod", ffi.C.chmod(path, mode))
end

function M.unlink(path)
   return util.check_errno("unlink", ffi.C.unlink(path))
end

function M.mkdir(path, mode)
   return util.check_errno("mkdir", ffi.C.mkdir(path, mode or util.oct("777")))
end

function M.rmdir(path)
   return util.check_errno("rmdir", ffi.C.rmdir(path))
end

function M.symlink(oldname, newname)
   return util.check_errno("symlink", ffi.C.symlink(oldname, newname))
end

function M.readlink(filename)
   return mm.with_block(PATH_MAX, nil, function(buf, block_size)
      local size = ffi.C.readlink(filename, buf, PATH_MAX)
      if size == PATH_MAX then
         ef("readlink: buffer overflow for filename: %s", filename)
      end
      return ffi.string(buf, size)
   end)
end

function M.realpath(name)
   local ptr = ffi.C.realpath(name, nil)
   if ptr ~= nil then
      local rv = ffi.string(ptr)
      ffi.C.free(ptr)
      return rv
   else
      ef("realpath() failed: %s: %s", name, errno.strerror())
   end
end

function M.basename(path)
   -- may modify its argument, so let's make a copy
   return mm.with_block(#path+1, nil, function(path_copy, block_size)
      ffi.copy(path_copy, path)
      return ffi.string(ffi.C.basename(path_copy))
   end)
end

function M.dirname(path)
   -- may modify its argument, so let's make a copy
   return mm.with_block(#path+1, nil, function(path_copy, block_size)
      ffi.copy(path_copy, path)
      return ffi.string(ffi.C.dirname(path_copy))
   end)
end

local function join(path, ...)
   local n_rest = select('#', ...)
   if n_rest == 0 then
      return path
   elseif type(path)=="string" then
      return sf("%s/%s", path, join(...))
   else
      ef("Invalid argument to join: %s", path)
   end
end

M.join = join

local Path_mt = {}

function Path_mt:__tostring()
   return mm.with_block(PATH_MAX, "char*", function(buf, block_size)
      local offset = 0
      local idx = 1
      -- the first component of an absolute path is /
      if self.components[1] == "/" then
         buf[0] = 0x2f -- slash
         offset = 1
         idx = 2
      end
      -- append components one by one to buf
      while idx <= #self.components do
         local name = self.components[idx]
         local len = #name
         if offset+len > block_size then
            ef("path too long")
         end
         ffi.copy(buf+offset, name, len)
         offset = offset + len
         -- append a slash after every component except the last
         if idx < #self.components then
            if offset == block_size then
               ef("path too long")
            end
            buf[offset] = 0x2f -- slash
            offset = offset + 1
         end
         idx = idx + 1
      end
      return ffi.string(buf, offset)
   end)
end

local function parse_path(path)
   local components = {}
   local ibeg = 1
   if path:sub(1,1) == "/" then
      table.insert(components, "/")
      ibeg = 2
   end
   while ibeg <= #path do
      local iend = path:find("/", ibeg, true) or #path+1
      local name = path:sub(ibeg, iend-1)
      table.insert(components, name)
      ibeg = iend + 1
   end
   return components
end

local function check_path_components(components)
   if type(components) ~= "table" then
      ef("check_path_components: path components must be in a table")
   end
   if #components == 0 then
      ef("check_path_components: table is empty")
   end
   local idx = 1
   if components[1] == "/" then
      idx = 2
   end
   while idx <= #components do
      name = components[idx]
      if not name then
         ef("check_path_components: found empty component")
      end
      if name:match("/") then
         ef("check_path_components: found a slash inside a component")
      end
      idx = idx + 1
   end
end

local function Path(path)
   local self = {}
   if type(path) == "string" then
      if path == "" then
         ef("invalid path: ''")
      end
      self.components = parse_path(path)
   elseif type(path) == "table" then
      if #path == 0 then
         ef("invalid path: {}")
      end
      self.components = path
   else
      ef("invalid path: %s", inspect(path))
   end
   check_path_components(self.components)
   return setmetatable(self, Path_mt)
end

M.Path = Path

function M.mkpath(path)
   path = Path(path)
   local dir
   for _,name in ipairs(path.components) do
      dir = dir and sf("%s/%s", dir, name) or name
      if not M.exists(dir) then
         M.mkdir(dir)
      end
   end
end

function M.rmpath(path)
   if M.exists(path) then
      process.system { "rm", "-rf", path }
   end
end

function M.glob(pattern, flags)
   flags = bit.bor(flags or 0,
                   ffi.C.GLOB_ERR,
                   ffi.C.GLOB_BRACE,
                   ffi.C.GLOB_TILDE_CHECK)
   return mm.with_block("glob_t", nil, function(pglob, block_size)
      local status = ffi.C.glob(pattern, flags, nil, pglob)
      local rv = {}
      if status == 0 then
         for i=1,tonumber(pglob.gl_pathc) do
            table.insert(rv, ffi.string(pglob.gl_pathv[i-1]))
         end
      end
      ffi.C.globfree(pglob)
      if status ~= 0 and status ~= ffi.C.GLOB_NOMATCH then
         ef("glob failed")
      end
      return rv
   end)
end

return setmetatable(M, { __index = ffi.C })
