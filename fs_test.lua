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

local function test_read()
   -- read whole file at once
   local f = fs.open('testdata/hello.txt')
   local contents = f:read()
   assert(contents=="hello, world!\n")
   f:close()

   -- read whole file at once, using helper func
   local contents = fs.readfile('testdata/hello.txt')
   assert(contents=="hello, world!\n")

   -- read a bigger file
   local contents = fs.readfile('testdata/arborescence.jpg')
   assert.equals(#contents, 81942)

   -- read some bytes
   local f = fs.open('testdata/hello.txt')
   local contents = f:read(5)
   assert(contents=="hello")
   f:close()

   -- if we want to read more bytes than the length of the file, we
   -- don't get an error
   local f = fs.open('testdata/hello.txt')
   local contents = f:read(4096)
   assert(contents=="hello, world!\n")
   -- further reads return nil
   assert(f:read(4096)==nil)
   f:close()
end

local function test_seek()
   -- seek from start
   local f = fs.open('testdata/hello.txt')
   assert(f:seek(5)==5)
   local contents = f:read()
   assert(contents==", world!\n")
   f:close()

   -- seek from end
   local f = fs.open('testdata/hello.txt')
   assert(f:seek(-7)==7)
   local contents = f:read(5)
   assert(contents=="world")
   f:close()

   -- seek from current position
   local f = fs.open('testdata/hello.txt')
   assert(f:seek(5)==5)
   assert(f:seek(2, true)==7)
   local contents = f:read(5)
   assert(contents=="world")
   f:close()
end

local function test_mkstemp()
   local f, path = fs.mkstemp()
   assert(type(path)=="string")
   assert(fs.exists(path))
   assert(re.match("^/tmp/.+$", path))
   f:write("stuff\n")
   f:close()
   -- temp file should be still there
   assert(fs.exists(path))
   local f = fs.open(path)
   assert.equals(tostring(f:read()), "stuff\n")
   f:close()
   fs.unlink(path)
   assert(not fs.exists(path))
end

local function test_exists()
   assert(fs.exists('testdata/hello.txt'))
   assert(not fs.exists('non-existing-file'))
end

local function test_chmod()
   fs.chmod("testdata/hello.txt", util.oct("755"))
   assert.equals(fs.stat("testdata/hello.txt").perms, util.oct("755"))
   assert(fs.is_executable("testdata/hello.txt"))
   fs.chmod("testdata/hello.txt", util.oct("644"))
   assert(fs.stat("testdata/hello.txt").perms == util.oct("644"))
   assert(not fs.is_executable("testdata/hello.txt"))
end

local function test_readable_writable_executable()
   local hello_txt_perms = util.oct("644")
   fs.chmod("testdata/hello.txt", hello_txt_perms)

   assert(fs.is_readable("testdata/hello.txt"))
   assert(fs.is_writable("testdata/hello.txt"))
   assert(not fs.is_executable("testdata/hello.txt"))

   fs.chmod("testdata/hello.txt", 0)
   assert(not fs.is_readable("testdata/hello.txt"))
   assert(not fs.is_writable("testdata/hello.txt"))
   assert(not fs.is_executable("testdata/hello.txt"))

   fs.chmod("testdata/hello.txt", util.oct("400"))
   assert(fs.is_readable("testdata/hello.txt"))
   assert(not fs.is_writable("testdata/hello.txt"))
   assert(not fs.is_executable("testdata/hello.txt"))

   fs.chmod("testdata/hello.txt", util.oct("200"))
   assert(not fs.is_readable("testdata/hello.txt"))
   assert(fs.is_writable("testdata/hello.txt"))
   assert(not fs.is_executable("testdata/hello.txt"))

   fs.chmod("testdata/hello.txt", util.oct("100"))
   assert(not fs.is_readable("testdata/hello.txt"))
   assert(not fs.is_writable("testdata/hello.txt"))
   assert(fs.is_executable("testdata/hello.txt"))

   fs.chmod("testdata/hello.txt", hello_txt_perms)
end

local function test_stat()
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
end

local function test_type()
   assert(fs.type("testdata/hello.txt")=="reg")
   assert(fs.is_reg("testdata/hello.txt"))
   
   assert(fs.type("testdata")=="dir")
   assert(fs.is_dir("testdata"))
   
   assert(fs.type("testdata/hello.txt.symlink")=="lnk")
   assert(fs.is_lnk("testdata/hello.txt.symlink"))
   -- TODO: chr, blk, fifo, sock
   
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
end

local function test_readdir()
   local expected_entries = {
      '.',
      '..',
      'arborescence.jpg',
      'bad.symlink',
      'hello.txt',
      'hello.txt.symlink',
      'www.google.com.txt',
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
end

local function test_basename()
   assert.equals(fs.basename("testdata/hello.txt"), "hello.txt")
end

local function test_dirname()
   assert.equals(fs.dirname("/"), "/")
   assert.equals(fs.dirname("."), ".")
   assert.equals(fs.dirname("./"), ".")
   assert.equals(fs.dirname("./hello.txt"), ".")
   assert.equals(fs.dirname("testdata/hello.txt"), "testdata")
end

local function test_join()
   assert.equals(fs.join(), nil)
   assert.equals(fs.join("abc"), "abc")
   assert.equals(fs.join("abc","def"), "abc/def")
   assert.equals(fs.join("abc",".", "def"), "abc/./def")
end

local function test_stream_read()
   local f = fs.open("testdata/arborescence.jpg")
   local s = stream(f)
   assert(not s:eof())

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
   local ptr, block_size = mm.get_block(16)
   assert.equals(s:read1(ptr, 1), 1)
   assert.equals(buffer.wrap(ptr,1), "\xff")
   assert.equals(s:read1(ptr, 2), 2)
   assert.equals(buffer.wrap(ptr,2), "\xd8\xff")
   assert.equals(s:read1(ptr, 4), 4)
   assert.equals(buffer.wrap(ptr,4), "\xe0\x00\x10\x4a")
   assert.equals(s:read1(ptr, 8), 8)
   assert.equals(buffer.wrap(ptr,8), "\x46\x49\x46\x00\x01\x01\x01\x00")
   mm.ret_block(ptr, block_size)

   -- read_until
   f:seek(0)
   assert.equals(s:read_until("\x10\x4a"), "\xff\xd8\xff\xe0\x00")
   -- f4 59 a9 29: this sequence is at position 81398 in the file
   local buf = s:read_until("\xf4\x59\xa9\x29")
   assert.equals(util.hexstr(digest.md5(buf)), '079dc470a97a1cf61aaa09a81204f75e')
   -- the stream most likely read past 81398
   -- extra bytes are left in the read buffer
   assert.equals(f:pos(), 81398+4+#s.read_buffer)
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
   f:close()
end

local function test_stream_write()
   local fin = fs.open("testdata/arborescence.jpg")
   local sin = stream(fin)
   local fout, fout_path = fs.mkstemp("test_stream_write")
   local sout = stream(fout)
   while not sin:eof() do
      sout:write(sin:read())
      sout:write(sin:read(math.random(1000)))
   end
   fout:close()
   fin:close()
   assert.equals(fs.readfile("testdata/arborescence.jpg"), fs.readfile(fout_path))
   fs.unlink(fout_path)
end

local function test_symlink_readlink_realpath()
   local rel = "testdata/arborescence.jpg"
   local abs = fs.realpath(rel)
   assert(abs ~= rel)
   assert.equals(fs.readfile(abs), fs.readfile(rel))
   local tmp = sf("/tmp/%s-arborescence.jpg", process.getpid())
   fs.symlink(abs, tmp)
   assert(fs.is_lnk(tmp))
   assert.equals(fs.readlink(tmp), abs)
   assert.equals(fs.realpath(tmp), abs)
   assert.equals(fs.realpath(sf("/tmp/../."..tmp)), abs)
   fs.unlink(tmp)
   assert(not fs.exists(tmp))
end

local function test_Path()
   assert.throws(function () fs.Path() end, "invalid path: nil")
   assert.throws(function () fs.Path(nil) end, "invalid path: nil")
   assert.throws(function () fs.Path("") end, "invalid path: ''")
   assert.throws(function () fs.Path{} end, "invalid path: {}")
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
end

local function test_mkdir()
   local tmpdir = sf("/tmp/fs_test_%d", process.getpid())
   assert.equals(0, fs.mkdir(tmpdir))
   assert(fs.is_dir(tmpdir))
   local s = fs.stat(tmpdir)
   assert.equals(s.perms, bit.band(util.oct("777"), bit.bnot(process.umask())))
   process.system(sf("rm -rf %s", tmpdir))
end

local function test_mkpath()
   local old_umask = process.umask(util.oct("022"))
   local tmpdir = sf("/tmp/fs_test_%d", process.getpid())
   fs.mkdir(tmpdir)
   local test_path = fs.join(tmpdir, "zsuba/guba/csicseri")
   fs.mkpath(test_path)
   assert(fs.is_dir(fs.join(tmpdir, "zsuba")))
   assert.equals(fs.stat(fs.join(tmpdir, "zsuba")).perms, util.oct("755"))
   assert(fs.is_dir(fs.join(tmpdir, "zsuba", "guba")))
   assert.equals(fs.stat(fs.join(tmpdir, "zsuba", "guba")).perms, util.oct("755"))
   assert(fs.is_dir(fs.join(tmpdir, "zsuba", "guba", "csicseri")))
   assert.equals(fs.stat(fs.join(tmpdir, "zsuba", "guba", "csicseri")).perms, util.oct("755"))
   process.system(sf("rm -rf %s", tmpdir))
   process.umask(old_umask)
end

local function test_touch()
   local old_umask = process.umask(util.oct("022"))
   local tmpdir = sf("/tmp/fs_test_%d", process.getpid())
   fs.mkdir(tmpdir)
   local test_path = fs.join(tmpdir, "touch")
   fs.touch(test_path)
   assert(fs.is_reg(test_path))
   assert.equals(fs.stat(test_path).perms, util.oct("644"))
   process.system(sf("rm -rf %s", tmpdir))
   process.umask(old_umask)
end

local function test()
   test_read()
   test_seek()
   test_mkstemp()
   test_exists()
   test_chmod()
   test_readable_writable_executable()
   test_stat()
   test_type()
   test_readdir()
   test_basename()
   test_dirname()
   test_join()
   test_stream_read()
   test_stream_write()
   test_symlink_readlink_realpath()
   test_Path()
   test_mkdir()
   test_mkpath()
   test_touch()
end

-- async
sched(test)
sched()

-- sync
test()
