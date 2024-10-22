local testing = require('testing')('fs')
local fs = require('fs')
local assert = require('assert')
local time = require('time')
local sched = require('sched')
local stream = require('stream')
local util = require('util')
local digest = require('digest')
local buffer = require('buffer')
local process = require('process')
local re = require('re')
local mm = require('mm')
local ffi = require('ffi')

testing("with_tmpdir", function()
   local tmpdir_save
   fs.with_tmpdir(function(tmpdir)
      assert(fs.is_dir(tmpdir))
      -- cleanup shall remove subdirectories
      fs.mkpath(fs.join(tmpdir, "a/b/c/d"))
      tmpdir_save = tmpdir
   end)
   assert(not fs.exists(tmpdir_save))
end)

testing:with_tmpdir("open", function(ctx)
   local tmpdir = ctx.tmpdir

   assert.throws('No such file or directory', function()
      fs.open("nonexistentfile")
   end)

   local f = fs.open(fs.join(tmpdir, "data.txt"), bit.bor(ffi.C.O_CREAT, ffi.C.O_RDWR))
   assert(f.fd > 0)
   stream(f):write("hello, world!")
   f:close()
   local f = fs.open(fs.join(tmpdir, "data.txt"))
   assert.equals(stream(f):read(0), "hello, world!")
   f:close()

   -- open also accepts fopen-style mode flags
   local f = fs.open(fs.join(tmpdir, "data.txt"), "w+")
   assert(f.fd > 0)
   stream(f):write("hello, world!")
   f:close()
   local f = fs.open(fs.join(tmpdir, "data.txt"))
   assert.equals(stream(f):read(0), "hello, world!")
   f:close()
end)

testing("read", function()
   -- read whole file at once
   local f = stream(fs.open('testdata/hello.txt'))
   local contents = f:read(0)
   assert(buffer.is_buffer(contents))
   assert(contents=="hello, world!\n")
   f:close()

   -- read whole file at once, using helper func
   local contents = fs.readfile('testdata/hello.txt')
   assert(buffer.is_buffer(contents))
   assert(contents=="hello, world!\n")

   -- read a bigger file
   local contents = fs.readfile('testdata/arborescence.jpg')
   assert.equals(#contents, 81942)

   -- read some bytes
   local f = stream(fs.open('testdata/hello.txt'))
   local contents = f:read(5)
   assert(buffer.is_buffer(contents))
   assert(contents=="hello")
   f:close()

   -- reading beyond the end is not an error
   local f = stream(fs.open('testdata/hello.txt'))
   local contents = f:read(4096)
   assert(contents=="hello, world!\n")
   -- further reads return an empty buffer
   assert(f:read(4096)=="")
   f:close()
end)

testing:with_tmpdir("writefile", function(ctx)
   local tmp = fs.join(ctx.tmpdir, 'arborescence.jpg')
   fs.writefile(tmp, fs.readfile('testdata/arborescence.jpg'))
   assert.equals(fs.readfile(tmp), fs.readfile('testdata/arborescence.jpg'))
end)

testing("seek", function()
   -- seek from start
   local f = fs.open('testdata/hello.txt')
   assert(f:seek(5)==5)
   local contents = stream(f):read()
   assert(contents==", world!\n")
   f:close()

   -- seek from end
   local f = fs.open('testdata/hello.txt')
   assert(f:seek(-7)==7)
   local contents = stream(f):read(5)
   assert(contents=="world")
   f:close()

   -- seek from current position
   local f = fs.open('testdata/hello.txt')
   assert(f:seek(5)==5)
   assert(f:seek(2, true)==7)
   local contents = stream(f):read(5)
   assert(contents=="world")
   f:close()
end)

testing:with_tmpdir("truncate, seek_end", function(ctx)
   local path = fs.join(ctx.tmpdir, "temp")
   fs.writefile(path, fs.readfile("testdata/arborescence.jpg"))
   local f = fs.open(path, ffi.C.O_RDWR)
   assert.equals(f:size(), 81942)
   assert.equals(f:pos(), 0)
   f:seek_end()
   assert.equals(f:pos(), 81942)
   f:seek(-1942)
   assert.equals(f:pos(), 80000)
   f:truncate()
   f:seek(1000)
   f:seek_end()
   assert.equals(f:pos(), 80000)
   stream(f):write("moooo")
   assert.equals(f:size(), 80005)
   f:truncate(40000)
   f:seek_end()
   -- if we didn't seek to the end, the file position would remain at
   -- 80005 and the file size would be 80010 after the write
   --
   -- but we'd better not rely on this
   stream(f):write("moooo")
   assert.equals(f:size(), 40005)
   f:close()
end)

testing("mkstemp", function()
   local f, path = fs.mkstemp()
   assert(type(path)=="string")
   assert(fs.exists(path))
   assert(re.match("^/tmp/.+$", path))
   stream(f):write("stuff\n")
   f:close()
   -- temp file should be still there
   assert(fs.exists(path))
   local f = fs.open(path)
   assert.equals(stream(f):read(0), "stuff\n")
   f:close()
   fs.unlink(path)
   assert(not fs.exists(path))
end)

testing("exists", function()
   assert(fs.exists('testdata/hello.txt'))
   assert(fs.exists('testdata/sub/HighHopes.txt'))
   assert(not fs.exists('non-existing-file'))
end)

testing:exclusive("chmod", function()
   fs.chmod("testdata/hello.txt", util.oct("755"))
   assert.equals(fs.stat("testdata/hello.txt").perms, util.oct("755"))
   assert(fs.is_executable("testdata/hello.txt"))
   fs.chmod("testdata/hello.txt", util.oct("644"))
   assert(fs.stat("testdata/hello.txt").perms == util.oct("644"))
   assert(not fs.is_executable("testdata/hello.txt"))
end)

testing:exclusive("stat", function()
   local s = fs.stat("testdata/hello.txt")
   assert.type(s.dev, 'number')
   assert.type(s.ino, 'number')
   assert.type(s.mode, 'number')
   assert.type(s.perms, 'number')
   assert.type(s.type, 'number')
   assert.equals(s.mode, s.perms + s.type)
   assert.type(s.nlink, 'number')
   assert.type(s.uid, 'number')
   assert.type(s.gid, 'number')
   assert.type(s.rdev, 'number')
   assert.type(s.size, 'number')
   assert.equals(s.size, 14, "stat('testdata/hello.txt').size")
   assert.type(s.blksize, 'number')
   assert.type(s.blocks, 'number')
   assert.type(s.atime, 'number')
   assert.type(s.mtime, 'number')
   assert.type(s.ctime, 'number')

   -- stat for non-existent file returns nil
   assert.equals(fs.stat("non-existent"), nil, "fs.stat() result for non-existent file")

   -- "The field st_ctime is changed by writing or by setting inode
   -- information (i.e., owner, group, link count, mode, etc.)."
   fs.chmod("testdata/hello.txt", s.perms)
   local now = math.floor(time.time())
   assert(math.abs(now-s.ctime) <= 1.0, sf("time.time()=%d, s.ctime=%d, difference > 1.0 seconds", now, s.ctime))
end)

testing("type", function()
   assert(fs.type("testdata/hello.txt")=="reg")
   assert(fs.is_reg("testdata/hello.txt"))
   
   assert(fs.type("testdata")=="dir")
   assert(fs.is_dir("testdata"))
   
   assert(fs.type("testdata/hello.txt.symlink")=="lnk")
   assert(fs.is_lnk("testdata/hello.txt.symlink"))

   assert(fs.type("/dev/null")=="chr")
   assert(fs.is_chr("/dev/null"))

   -- TODO: blk, fifo, sock

   -- type of symlink pointing to non-existing file is "lnk"
   assert(fs.type("testdata/bad.symlink")=="lnk")
   assert(fs.is_lnk("testdata/bad.symlink"))

   -- but exists() returns false for such symlinks
   assert(fs.exists("testdata/hello.txt.symlink"))
   assert(not fs.exists("testdata/bad.symlink"))

   -- just like is_readable and is_writable
   assert(fs.is_readable("testdata/hello.txt.symlink"))
   assert(fs.is_writable("testdata/hello.txt.symlink"))
   assert(not fs.is_readable("testdata/bad.symlink"))
   assert(not fs.is_writable("testdata/bad.symlink"))
end)

testing("readdir", function()
   local expected_entries = {
      '.',
      '..',
      'arborescence.jpg',
      'bad.symlink',
      'hello.txt',
      'hello.txt.symlink',
      'www.google.com.txt',
      'sub'
   }
   table.sort(expected_entries)

   -- using dir:read()
   local entries = {}
   local dir = fs.opendir("testdata")
   local function add_entry()
      local e = dir:read()
      if e then
         assert(type(e)=="string")
         table.insert(entries, e)
      end
      return e
   end
   for i=1,#expected_entries do add_entry() end
   assert(dir:read()==nil)
   table.sort(entries)
   assert.equals(entries, expected_entries)
   assert.equals(dir:close(), 0)

   -- using iterator
   local entries = {}
   for f in fs.readdir("testdata") do
      table.insert(entries, f)
   end
   table.sort(entries)
   assert.equals(entries, expected_entries)
end)

testing("basename", function()
   assert.equals(fs.basename("testdata/hello.txt"), "hello.txt")
   assert.equals(fs.basename("/hello.txt"), "hello.txt")
   assert.equals(fs.basename("./hello.txt"), "hello.txt")
   assert.equals(fs.basename("hello.txt"), "hello.txt")
   assert.equals(fs.basename("testdata/sub/HighHopes.txt"), "HighHopes.txt")
end)

testing("dirname", function()
   assert.equals(fs.dirname("/"), "/")
   assert.equals(fs.dirname("."), ".")
   assert.equals(fs.dirname("./"), ".")
   assert.equals(fs.dirname("./hello.txt"), ".")
   assert.equals(fs.dirname("testdata/hello.txt"), "testdata")
   assert.equals(fs.dirname("x"), ".")
   assert.equals(fs.dirname("testdata/sub/HighHopes.txt"), "testdata/sub")
end)

testing("join", function()
   assert.equals(fs.join(), nil)
   assert.equals(fs.join("abc"), "abc")
   assert.equals(fs.join("abc","def"), "abc/def")
   assert.equals(fs.join("abc",".", "def"), "abc/./def")
   assert.equals(fs.join("abc","/def"), "abc//def")
   assert.equals(fs.join("", "abc"), "abc")
   assert.equals(fs.join("abc", ""), "abc")
end)

testing("stream.read", function()
   local f = fs.open("testdata/arborescence.jpg")
   local s = stream(f)
   assert(not s:eof())

   -- field lookups on streams fall back to the wrapped object
   assert.type(s.fd, "number")

   -- read(n) reads n bytes
   assert.equals(s:read(1), "\xff")
   assert.equals(s:read(2), "\xd8\xff")
   assert.equals(s:read(4), "\xe0\x00\x10\x4a")
   assert.equals(s:read(8), "\x46\x49\x46\x00\x01\x01\x01\x00")

   -- read() reads max stream.READ_BLOCK_SIZE bytes
   assert.equals(type(stream.READ_BLOCK_SIZE), "number")
   local buf = s:read()
   assert.equals(#buf, stream.READ_BLOCK_SIZE)
   assert.equals(util.hexstr(digest.md5(buf)), '97a61975b61aa68588eec3a7db2129d7')
   assert(not s:eof())

   -- rewind
   f:seek(0)

   -- read1
   mm.with_block(16, nil, function(ptr, block_size)
      assert.equals(s:read1(ptr, 1), 1)
      assert.equals(buffer.wrap(ptr,1), "\xff")
      assert.equals(s:read1(ptr, 2), 2)
      assert.equals(buffer.wrap(ptr,2), "\xd8\xff")
      assert.equals(s:read1(ptr, 4), 4)
      assert.equals(buffer.wrap(ptr,4), "\xe0\x00\x10\x4a")
      assert.equals(s:read1(ptr, 8), 8)
      assert.equals(buffer.wrap(ptr,8), "\x46\x49\x46\x00\x01\x01\x01\x00")
   end)

   -- read_until
   f:seek(0)
   assert.equals(s:read_until("\x10\x4a"), "\xff\xd8\xff\xe0\x00")
   -- f4 59 a9 29: this sequence is at position 81398 in the file
   local buf = s:read_until("\xf4\x59\xa9\x29")
   assert.equals(util.hexstr(digest.md5(buf)), '079dc470a97a1cf61aaa09a81204f75e')
   -- the stream most likely read past 81398
   -- extra bytes are left in the read buffer
   assert.equals(f:pos(), 81398+4+s.read_buffer:length())
   local nbytes_remaining = f:size() - (81398+4)
   assert.equals(#s:read(0), nbytes_remaining)
   assert(s:eof())
   f:close()

   -- read(0) reads the whole file (until EOF)
   local f = fs.open("testdata/arborescence.jpg")
   local s = stream(f)
   assert(not s:eof())
   local buf = s:read(0)
   assert.equals(util.hexstr(digest.md5(buf)), '58823f6d5e1d154d37d9aa2dbaf27371')
   assert(s:eof())
   -- once we get to end of file, a rewind does NOT reset the EOF flag
   -- (it seems difficult to implement this correctly)
   f:seek(0)
   assert(s:eof())
   f:close()

   -- random read using read() and read(n)
   local f = fs.open("testdata/arborescence.jpg")
   local s = stream(f)
   local buf = buffer.new()
   while not s:eof() do
      buf:append(s:read())
      buf:append(s:read(math.random(1000)))
   end
   assert.equals(util.hexstr(digest.md5(buf)), '58823f6d5e1d154d37d9aa2dbaf27371')
   f:close()

   -- readln
   local f = fs.open("testdata/www.google.com.txt")
   local s = stream(f)
   assert.equals(s:readln(), "HTTP/1.1 302 Found\x0d")
   assert.equals(s:readln(), "Cache-Control: private\x0d")
   assert.equals(s:readln(), "Content-Type: text/html; charset=UTF-8\x0d")
   s:read_until("\x0d\x0a\x0d\x0a")
   assert.equals(s:readln(), '<HTML><HEAD><meta http-equiv="content-type" content="text/html;charset=utf-8">')
   -- s:close() is proxied to the wrapped object (in this case f)
   s:close()
end)

testing:with_tmpdir("stream.write", function(ctx)
   local sin = stream(fs.open("testdata/arborescence.jpg"))
   local fout_path = fs.join(ctx.tmpdir, "test_stream_write")
   local sout = stream(fs.open(fout_path, bit.bor(ffi.C.O_CREAT, ffi.C.O_RDWR)))
   while not sin:eof() do
      sout:write(sin:read())
      sout:write(sin:read(math.random(1000)))
   end
   sout:close()
   sin:close()
   assert.equals(fs.readfile("testdata/arborescence.jpg"), fs.readfile(fout_path))
end)

testing:with_tmpdir("symlink_readlink_realpath", function(ctx)
   local rel = "testdata/arborescence.jpg"
   local abs = fs.realpath(rel)
   assert(abs ~= rel)
   assert.equals(abs:sub(1,1), "/")
   assert.equals(fs.readfile(abs), fs.readfile(rel))

   local tmp = fs.join(ctx.tmpdir, "arborescence.jpg")
   fs.symlink(abs, tmp)
   assert(fs.is_lnk(tmp))
   assert.equals(fs.readlink(tmp), abs)
   assert.equals(fs.realpath(tmp), abs)
   assert.equals(fs.realpath(sf("/tmp/../."..tmp)), abs)
   fs.unlink(tmp)
   assert(not fs.exists(tmp))
end)

testing("Path", function()
   assert.throws("invalid path: nil", function () fs.Path() end)
   assert.throws("invalid path: nil", function () fs.Path(nil) end)
   assert.throws("invalid path: ''", function () fs.Path("") end)
   assert.throws("invalid path: {}", function () fs.Path{} end)
   assert.equals(tostring(fs.Path(".")), ".")
   assert.equals(fs.Path(".").components, {"."})
   assert.equals(tostring(fs.Path("/")), "/")
   assert.equals(fs.Path("/").components, {"/"})
   assert.equals(tostring(fs.Path("abc")), "abc")
   assert.equals(fs.Path("abc").components, {"abc"})
   assert.equals(tostring(fs.Path("/abc")), "/abc")
   assert.equals(fs.Path("/abc").components, {"/","abc"})
   assert.equals(tostring(fs.Path("abc/")), "abc")
   assert.equals(fs.Path("abc/").components, {"abc"})
   assert.equals(tostring(fs.Path("abc/.")), "abc/.")
   assert.equals(fs.Path("abc/.").components, {"abc","."})
   assert.equals(tostring(fs.Path("./abc")), "./abc")
   assert.equals(fs.Path("./abc").components, {".","abc"})
   assert.equals(tostring(fs.Path("abc/def")), "abc/def")
   assert.equals(fs.Path("abc/def").components, {"abc","def"})
   assert.equals(tostring(fs.Path{"abc","def"}), "abc/def")
end)

testing:with_tmpdir("mkdir_rmdir", function(ctx)
   local foo_path = fs.join(ctx.tmpdir, "foo")
   assert.equals(0, fs.mkdir(foo_path))
   assert(fs.is_dir(foo_path))
   local s = fs.stat(foo_path)
   assert.equals(s.perms, bit.band(util.oct("777"), bit.bnot(process.umask())))
   assert.equals(0, fs.rmdir(foo_path))
   assert(not fs.is_dir(foo_path))
   assert(not fs.exists(foo_path))
end)

-- the following tests are exclusive because they change global state
-- (process.umask)

testing:with_tmpdir("mkpath_rmpath", function(ctx)
   local t = ctx.tmpdir
   local old_umask = process.umask(util.oct("022"))
   local test_path = fs.join(t, "zsuba/guba/csicseri")
   fs.mkpath(test_path)
   assert(fs.is_dir(fs.join(t, "zsuba")))
   assert.equals(fs.stat(fs.join(t, "zsuba")).perms, util.oct("755"))
   assert(fs.is_dir(fs.join(t, "zsuba", "guba")))
   assert.equals(fs.stat(fs.join(t, "zsuba", "guba")).perms, util.oct("755"))
   assert(fs.is_dir(fs.join(t, "zsuba", "guba", "csicseri")))
   assert.equals(fs.stat(fs.join(t, "zsuba", "guba", "csicseri")).perms, util.oct("755"))
   fs.rmpath(fs.join(t, "zsuba"))
   assert(fs.is_dir(t))
   assert(not fs.is_dir(fs.join(t, "zsuba")))
   process.umask(old_umask)
end, { exclusive = true })

testing:with_tmpdir("touch", function(ctx)
   local old_umask = process.umask(util.oct("022"))
   local test_path = fs.join(ctx.tmpdir, "touch")
   fs.touch(test_path)
   assert(fs.is_reg(test_path))
   assert.equals(fs.stat(test_path).perms, util.oct("644"))
   process.umask(old_umask)
end, { exclusive = true })

testing("glob", function()
   assert.equals(fs.glob("testdata/*.jpg"), {
     "testdata/arborescence.jpg"
   })
   assert.equals(fs.glob("testdata/*.txt"), {
     "testdata/hello.txt",
     "testdata/www.google.com.txt"
   })
   assert.equals(fs.glob("testdata/sub/*.txt"), {
     "testdata/sub/HighHopes.txt"
   })
end)
