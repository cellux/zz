local testing = require('testing')('stream')
local stream = require('stream')
local buffer = require('buffer')
local assert = require('assert')
local fs = require('fs')
local net = require('net')
local util = require('util')
local digest = require('digest')
local sched = require('sched')
local ffi = require('ffi')
local re = require('re')
local zip = require('zip')

testing("memory streams (fifos)", function()
   local s = stream()

   assert(s:eof())
   s:write("hello")
   assert(not s:eof())
   assert.equals(s:read(), "hello")
   assert(s:eof())

   s:write("hello\nworld\n")
   assert.equals(s:readln(), "hello")
   assert.equals(s:readln(), "world")
   assert(s:eof())

   s:write("hello\nworld\n")
   assert.equals(s:read(0), "hello\nworld\n")
   assert(s:eof())

   s:write("hello\nworld\n")
   assert.equals(s:read(2), "he")
   assert.equals(s:read(5), "llo\nw")
   s:write("\nx")
   assert.equals(s:read(0), "orld\n\nx")
   assert(s:eof())

   -- writeln works with numbers
   s:writeln(1234)
   assert.equals(s:readln(), "1234")
end)

testing("read_until", function()
   local buf = buffer.copy("\"This is not too good\", he said.")
   local s = stream(buf)
   assert(not s:eof())
   local part, found_marker = s:read_until('"')
   assert.equals(part, "")
   assert.is_true(found_marker)
   assert(not s:eof())
   local part, found_marker = s:read_until('"')
   assert.equals(part, "This is not too good")
   assert.is_true(found_marker)
   assert(not s:eof())
   local part, found_marker = s:read_until('"')
   assert.equals(part, ", he said.")
   assert.is_false(found_marker)
   assert(s:eof())
   local part, found_marker = s:read_until('"')
   assert.equals(part, "")
   assert.is_false(found_marker)
end)

testing("read_until keeping marker", function()
   local buf = buffer.copy("\"This is not too good\", he said.")
   local s = stream(buf)
   assert.equals(s:read_until(',', true), '"This is not too good",')
   assert.equals(s:read_until(',', true), ' he said.')
end)

testing("match", function()
   local s = stream("The realization that this universe is the body of God.")
   local m = s:match("real.*\\b(u.+?)\\b.*th")
   assert.equals(m[0], "realization that this universe is th")
   assert.equals(m[1], "universe")
   -- stream:match() consumes what it matched
   assert.equals(s:read_char(), "e")
   -- if there is no match, nothing changes in the stream state
   assert.is_nil(s:match("won't match"))
   assert.equals(s:read_until("of "), " body ")
   assert.equals(s:read(), "God.")

   local s = stream(fs.open("testdata/arborescence.jpg"))
   local m = s:match("uhi\\w+!")
   assert.equals(m[0], "uhiWIY6tU!")
   local m = s:match("o...O")
   assert.equals(m[0], "oZSmO")
   assert.is_nil(s:match("jumbo"))
   assert.equals(s:peek(2), "\xff\x00")
   local m = s:match("\\{\\*.+?\\d(\\w+)")
   assert.equals(m[1], "jfkE")
   s:close()
end)

testing("match at beginning", function()
   local s = stream("Altered Carbon in the Black Mirror")
   assert.is_nil(s:match("^C\\w+"))
   assert.equals(s:match("C\\w+")[0], "Carbon")
   assert.equals(s:read(), " in the Black Mirror")
end)

testing("match does not return empty matches", function()
   local s = stream("123")
   assert.is_nil(s:match("^(\\.[0-9]+)?(e-?[0-9]+)?"))
end)

testing("read_byte", function()
   local buf = buffer.copy("\x01\x02\x03\x04")
   local s = stream(buf)
   s:read(2)
   assert.equals(s:read_byte(), 3)
   assert.equals(s:read_byte(), 4)
   assert.is_nil(s:read_byte())
end)

testing("read_char", function()
   local buf = buffer.copy("\"This is not too good\", he said.")
   local s = stream(buf)
   assert.equals(s:read(5), "\"This")
   assert.equals(s:read_char(), " ")
   assert.equals(s:read_char(), "i")
   assert.equals(s:read_char(), "s")
   assert.equals(s:read_char(), " ")
   assert.equals(s:read_until("\""), "not too good")
   assert.equals(s:read(0), ", he said.")
   assert.is_nil(s:read_char())
end)

testing("read_be", function()
   local buf = buffer.copy("\x01\x02\x03\x04\x05\x06\x07")
   local s = stream(buf)
   assert.equals(s:read_be(1), 0x01)
   assert.equals(s:read_be(2), 0x0203)
   assert.equals(s:read_be(4), 0x04050607)
end)

testing("write_be", function()
   local buf = buffer.new(8)
   local s = stream(buf)
   s:write_be(1, 0x01)
   s:write_be(2, 0x0203)
   s:write_be(4, 0x04050607)
   assert.equals(buf, "\x01\x02\x03\x04\x05\x06\x07")
end)

testing("read_le", function()
   local buf = buffer.copy("\x01\x02\x03\x04\x05\x06\x07")
   local s = stream(buf)
   assert.equals(s:read_le(1), 0x01)
   assert.equals(s:read_le(2), 0x0302)
   assert.equals(s:read_le(4), 0x07060504)
end)

testing("write_le", function()
   local buf = buffer.new(8)
   local s = stream(buf)
   s:write_le(1, 0x01)
   s:write_le(2, 0x0302)
   s:write_le(4, 0x07060504)
   assert.equals(buf, "\x01\x02\x03\x04\x05\x06\x07")
end)

local function stream_between(input, output)
   input = stream(input)
   output = stream(output)
   local bufsize = 512
   local buf = buffer.new(bufsize)
   local readers = {
      function()
         local bytes_to_read = math.random(bufsize)
         local bytes_actually_read = input:read1(buf.ptr, bytes_to_read)
         return buffer.wrap(buf, bytes_actually_read)
      end,
      function()
         return input:read()
      end,
      function()
         return input:read(math.random(bufsize))
      end,
      function()
         return input:read_until("\0", true)
      end,
      function()
         local ch = input:read_char()
         local size = ch and 1 or 0
         return buffer.copy(ch, size)
      end,
   }
   while not input:eof() do
      local piece_of_data = readers[math.random(#readers)]()
      output:write(piece_of_data)
   end
   buf:free() -- we could also leave it to the GC
end

testing("file", function()
   local input = fs.open("testdata/arborescence.jpg")
   local output = buffer.new()
   stream_between(input, output)
   assert.equals(util.hexstr(digest.md5(output)), '58823f6d5e1d154d37d9aa2dbaf27371')
   input:close()
end)

testing("buffer", function()
   local input = fs.readfile("testdata/arborescence.jpg")
   output = buffer.new()
   stream_between(input, output)
   assert.equals(util.hexstr(digest.md5(output)), '58823f6d5e1d154d37d9aa2dbaf27371')
end)

testing("string", function()
   local input = tostring(fs.readfile("testdata/arborescence.jpg"))
   output = buffer.new()
   stream_between(input, output)
   assert.equals(util.hexstr(digest.md5(output)), '58823f6d5e1d154d37d9aa2dbaf27371')
end)

testing("socketpair", function()
   local input = fs.open("testdata/arborescence.jpg")
   local s1,s2 = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM)
   local output = buffer.new()
   sched(function()
      stream_between(input, s1)
      s1:close()
   end)
   stream_between(s2, output)
   s2:close()
   input:close()
   assert.equals(util.hexstr(digest.md5(output)), '58823f6d5e1d154d37d9aa2dbaf27371')
end)

testing("memory stream", function()
   local input = fs.open("testdata/arborescence.jpg")
   local memory_stream = stream()
   stream_between(input, memory_stream)
   input:close()
   local output = buffer.new()
   stream_between(memory_stream, output)
   assert.equals(util.hexstr(digest.md5(output)), '58823f6d5e1d154d37d9aa2dbaf27371')
end)

testing("peek", function()
   local input = stream(fs.open("testdata/arborescence.jpg"))
   input:read(100)
   assert.equals(input:peek(1), "\x08")
   assert.equals(input:peek(8), "\x08\x04\x04\x08\x10\x0b\x09\x0b")
   assert.equals(input:read(3), "\x08\x04\04")
   -- if the read buffer has more data in it than the peek size,
   -- peek() shall only return size bytes
   input:match("pereszteg") -- fill the read buffer
   assert.equals(input:peek(5), "\x08\x10\x0b\x09\x0b")
   input:close()
end)

testing("unread", function()
   local s = stream("this is the beginning of a beautiful friendship")
   s:unread("[abcdef]")
   assert.equals(s:peek(12), "[abcdef]this")
   assert.equals(s:match("(\\w+\\s+){4}")[0], "this is the beginning ")
   assert.equals(s:peek(2), "of")
   s:unread("this is the end ")
   assert.equals(s:match("(\\w+\\s+){4}")[0], "this is the end ")
   assert.equals(s:read(), "of a beautiful friendship")
end)

testing("slurp", function()
   local f = fs.open("testdata/arborescence.jpg")
   assert(f.fd > 0)
   local s = stream(f)
   local data = s:slurp() -- f:slurp() = f:read(0) + f:close()
   assert.equals(data,fs.readfile("testdata/arborescence.jpg"))
   assert(f.fd == -1)
end)

testing:with_tmpdir("stream.copy", function(ctx)
   local f1 = fs.open("testdata/arborescence.jpg")
   local f2 = fs.open(fs.join(ctx.tmpdir, "out.jpg"),
                      bit.bor(ffi.C.O_CREAT, ffi.C.O_WRONLY))
   local s1 = stream(f1)
   local s2 = stream(f2)
   -- copy is synchronous
   stream.copy(s1, s2)
   -- copy does not close either streams
   assert(f1.fd > 0)
   f1:close()
   assert(f2.fd > 0)
   f2:close()
   assert.equals(fs.readfile("testdata/arborescence.jpg"),
                 fs.readfile(fs.join(ctx.tmpdir, "out.jpg")))
end)

testing:with_tmpdir("stream.pipe", function(ctx)
   local f1 = fs.open("testdata/arborescence.jpg")
   local f2 = fs.open(fs.join(ctx.tmpdir, "out.jpg"),
                      bit.bor(ffi.C.O_CREAT, ffi.C.O_WRONLY))
   local s1 = stream(f1)
   local s2 = stream(f2)
   -- pipe is asynchronous
   -- it returns the thread which is running the copy
   local thread = stream.pipe(s1, s2)
   sched.join(thread) -- wait for copy to finish
   -- pipe closes both streams
   assert(f1.fd == -1)
   assert(f2.fd == -1)
   assert.equals(fs.readfile("testdata/arborescence.jpg"),
                 fs.readfile(fs.join(ctx.tmpdir, "out.jpg")))
end)

testing("stream.with_size", function()
   local f = fs.open("testdata/arborescence.jpg")
   s = stream.with_size(20, f)
   local buf = s:read(17)
   assert(not s:eof())
   local bytebuf = ffi.new("uint8_t[1]")
   -- read_byte() shall also heed the size constraint
   bytebuf[0] = s:read_byte()
   buf:append(bytebuf, 1)
   buf:append(s:read(1000))
   assert.equals(#buf, 20)
   assert.equals(f:pos(), 20)
   assert(s:eof())
   s:close()
   assert.equals(buf, buffer.copy(fs.readfile("testdata/arborescence.jpg"), 20))
end)

testing("stream.tap", function()
   local crc32 = zip.crc32()
   local uncompressed_size = 0
   local compressed_size = 0
   local input = stream(fs.open("testdata/arborescence.jpg"))
   input = stream.tap(input, function(ptr, len)
      uncompressed_size = uncompressed_size + len
      crc32 = zip.crc32(crc32, ptr, len)
   end)
   input = zip.deflate(input)
   input = stream.tap(input, function(ptr, len)
      compressed_size = compressed_size + len
   end)
   local output_buf = buffer.new()
   local output = stream(output_buf)
   stream.copy(input, output)
   input:close()
   assert.equals(crc32, 0x2865712d)
   assert.equals(uncompressed_size, 81942)
   -- zipping arborescence.jpg with InfoZIP
   -- results in a compressed size of 81858
   --
   -- I don't know why zip.deflate gives a different result
   assert.equals(compressed_size, 81884)
   assert.equals(#output_buf, compressed_size)
end)

testing("stream.no_close", function()
   local f = fs.open("testdata/arborescence.jpg")
   local s = stream(f)
   s:close()
   -- close is forwarded to the wrapped object by default
   assert(f.fd == -1)

   local f = fs.open("testdata/arborescence.jpg")
   local s = stream.no_close(f)
   s:close()
   -- no_close() prevents forwarding the close to the wrapped objet
   assert(f.fd > 0)
   f:close()
end)

testing("reading characters from pipe wrapped via fs.fd()", function()
   -- trying to simulate what happens when we read from stdin
   local sock1,sock2 = net.socketpair(net.PF_LOCAL, net.SOCK_STREAM)
   local s1 = stream(sock1)
   local f2 = fs.fd(sock2.fd) -- like fs.fd(0) for reading from stdin
   local s2 = stream(f2)
   local input = "0123456789abcdef"
   s1:write(input)
   for i=1,#input do
      local ch = input:sub(i,i)
      assert.equals(s2:peek(1), ch)
      assert.equals(s2:read_char(), ch)
   end
   s1:close()
   s2:close()
end)
