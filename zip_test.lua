local testing = require('testing')('zip')
local zip = require('zip')
local fs = require('fs')
local stream = require('stream')
local assert = require('assert')

testing("deflate/inflate", function()
   local data = fs.readfile('testdata/sub/HighHopes.txt')
   -- deflate(x) returns a stream of the compressed data
   local compressed = zip.deflate(data):slurp()
   assert(#compressed < #data)
   -- inflate(x) returns a stream of the decompressed data
   local decompressed = zip.inflate(compressed):slurp()
   assert.equals(data, decompressed)
end)

testing:with_tmpdir("open", function(ctx)
   -- opening a non-existent file creates it
   local zip_path = fs.join(ctx.tmpdir, "data.zip")
   local zf = zip.open(zip_path)
   assert(fs.exists(zip_path))
   zf:close()
   fs.unlink(zip_path)

   local zf = zip.open(zip_path)
   -- zf:add(path, streamable) appends local header and compressed data
   zf:add("some/path/arborescence.jpg", fs.readfile("testdata/arborescence.jpg"))
   zf:add("other/path/hello.txt", fs.readfile("testdata/hello.txt"))
   -- zf:add() accepts any streamable
   local f = fs.open("testdata/sub/HighHopes.txt")
   zf:add("missing_reunion.txt", f)
   -- zf:add() reads the input stream until eof and then closes it
   assert.equals(f.fd, -1)
   -- zf:close() writes central directory and EOCD
   zf:close()

   -- now read it back
   local zf = zip.open(zip_path)
   -- zf:stream(path) returns an inflate stream of the zip entry at path
   local s = zf:stream("some/path/arborescence.jpg")
   assert.equals(s:read(0), fs.readfile("testdata/arborescence.jpg"))
   -- the inflate stream must be closed to free its resources
   s:close()
   -- zf:readfile() is a shortcut for reading a complete file
   local hopes = zf:readfile("missing_reunion.txt")
   assert.equals(hopes, fs.readfile("testdata/sub/HighHopes.txt"))
   -- zf:exists() checks if a file exists within the archive
   assert(zf:exists("other/path/hello.txt"))
   assert(not zf:exists("some/path/hello.txt"))
   -- reading a non-existent file throws
   assert.throws("No such file", function()
      zf:readfile("nonexistent")
   end)
   zf:close()
end)

testing("crc32", function()
   local crc = zip.crc32()
   local s = stream(fs.open("testdata/arborescence.jpg"))
   while not s:eof() do
      local block = s:read(4000)
      crc = zip.crc32(crc, block.ptr, #block)
   end
   s:close()
   assert.equals(crc, 0x2865712d)
end)
