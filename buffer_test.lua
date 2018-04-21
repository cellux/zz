local testing = require('testing')
local buffer = require('buffer')
local ffi = require('ffi')
local assert = require('assert')

testing("buffer", function()
   -- buffer.new() allocates a buffer with default capacity and zero size
   local buf = buffer.new()
   assert(buf.cap > 0)
   assert.equals(buf.len, 0)
   assert.equals(#buf, 0) -- #buf is equivalent to buf.len
   assert.equals(buf:str(), "") -- get contents as a string
   assert.equals(tostring(buf), "") -- same as buf:str()
   -- a buffer is cdata
   assert.equals(type(buf), "cdata")
   -- test if an object is a buffer
   assert(buffer.is_buffer(buf))
   -- compare with string
   assert(buf=="")
   assert(""==buf)
   -- compare with nil
   assert(buf~=nil)
   assert(nil~=buf)
   -- compare with another buffer
   assert(buf==buffer.new())

   -- append
   local buf = buffer.new()
   buf:append("hello")
   assert(buf=="hello")
   assert.equals(#buf, 5)
   buf:append(", world!")
   assert.equals(#buf, 13)
   assert(buf=="hello, world!")
   -- append another buffer
   buf:append(buffer.copy(" insane palace"))
   assert(buf=="hello, world! insane palace")
   -- then resize back
   buf.len = 13
   -- appending again
   buf:append(" nothing special")
   assert(buf=="hello, world! nothing special")
   -- then resize back
   buf.len = 13
   assert(buf=="hello, world!")

   -- buffer with explicit capacity
   local buf2 = buffer.new(5)
   assert.equals(buf2.cap, 5)
   assert.equals(#buf2, 0) -- initial size is zero
   assert(buf2=="")
   buf2:append("hell")
   assert.equals(buf2.cap, 5)
   assert.equals(#buf2, 4)
   -- automatic resize rounds capacity to next multiple of 1024
   buf2:append("o, world!")
   assert.equals(buf2.cap, 1024)
   assert.equals(#buf2, 13)
   assert(buf2=="hello, world!")
   assert(buf==buf2)
   -- append first N bytes of a string
   buf2:append("\n\n\n\n\n\n", 2)
   assert(buf2=="hello, world!\n\n")
   -- append a section of another buffer
   buf2:append(buf2.ptr+3, 3)
   assert(buf2=="hello, world!\n\nlo,")

   -- buffer with an explicit capacity and length
   local buf2 = buffer.new(5,5)
   assert.equals(buf2.cap, 5)
   assert.equals(buf2.len, 5)
   -- contents are zero-initialized
   assert(buf2=='\x00\x00\x00\x00\x00')

   -- buffer.copy() makes a copy of existing data
   local three_spaces = '   '
   local buf3 = buffer.copy(three_spaces)
   assert.equals(#buf3, 3)
   assert.equals(buf3.cap, 3)
   assert(buf3=='   ')

   -- fill
   buf3:fill(0x41)
   assert(buf3=='AAA')
   
   -- three_spaces still has its original value
   assert(three_spaces=='   ')
   
   -- clear: fill with zeroes
   buf3:clear()
   assert(buf3=='\0\0\0')

   buf3.len = 0
   assert(buf3.cap==3)
   assert(buf3.len==0)
   assert(buf3=="")
   
   buf3:append('zzz')
   assert(buf3=='zzz')
   assert.equals(#buf3, 3)

   -- buffer.wrap() creates a buffer which points to existing data
   --
   -- no copying, no ownership (doesn't deallocate data in the finalizer)
   local buf3b = buffer.wrap(buf3)
   assert(buf3b=='zzz')

   -- indexing
   assert(buf3b[1]==0x7a)
   buf3b[1]=0x78
   assert(buf3b=='zxz')
   
   -- as we shared data with buf3, it changed too:
   assert(buf3=='zxz')
   
   -- warning: never modify a buffer which shares its data with a Lua
   -- string - it interferes with the interning logic

   -- buffer with initial data of specified size
   local buf4 = buffer.copy('abcdef', 3)
   assert.equals(#buf4, 3)
   assert.equals(buf4.cap, 3)
   assert(buf4=='abc')

   -- buffer.slice(data, offset)
   -- returns a copy of the slice from `offset` to the end
   local buf4 = buffer.slice('abcdef', 2)
   assert.equals(#buf4, 4)
   assert.equals(buf4.cap, 4)
   assert(buf4=='cdef')
   
   -- buffer.slice(data, offset, size)
   -- returns a copy of the slice starting at `offset` with length `size`
   local buf4 = buffer.slice('abcdef', 2, 3)
   assert.equals(#buf4, 3)
   assert.equals(buf4.cap, 3)
   assert(buf4=='cde')
   
   -- change capacity
   local buf5 = buffer.new()
   buf5:resize(2100)
   -- capacity is rounded up to next multiple of 1024
   assert.equals(buf5.cap, 3072)
   buf5:resize(4000)
   assert.equals(buf5.cap, 4096)
   assert.equals(#buf5, 0)
   for i=0,4095 do
      buf5:append(string.char(0x41+i%26))
   end
   assert.equals(buf5.cap, 4096)
   assert.equals(#buf5, 4096)

   -- change length
   buf5.len = 5
   assert.equals(#buf5, 5)
   assert(buf5=='ABCDE')
   buf5.len = 4096
   
   -- buf:get(index) and buf[index]
   assert.equals(buf5:get(0), 0x41) -- byte value at index 0
   assert.equals(buf5[0], 0x41)     -- sugar for buf5:get(0)
   
   -- buf:str(index, length)
   assert.equals(buf5:str(0,10), "ABCDEFGHIJ")
   assert.equals(buf5:str(5,10), "FGHIJKLMNO")
   
   -- buf:set(index, value) and buf[index] = value
   buf5:set(2, 0x7A) -- byte value
   assert.equals(buf5:str(0,10), "ABzDEFGHIJ")
   buf5[2] = 0x79 -- sugar for buf5:set(2, 0x7A)
   assert.equals(buf5:str(0,10), "AByDEFGHIJ")
   
   -- getting a uint8_t* pointer to buffer data
   assert.equals(ffi.string(buf5.ptr+7,2), "HI")
   
   -- check that assert.equals works too
   assert.equals(buffer.copy("\x55\xaa\x00\xe0"), "\x55\xaa\x00\xe0")
end)

testing("buffer.resize", function()
   local buf = buffer.new(16384)
   assert(buf.cap >= 16384)
   buf:resize(128)
   assert(buf.cap < 16384 and buf.cap >= 128)
   buf:resize(0)
   assert(buf.cap > 0)
end)

testing("buffers with zero-length allocations", function()
  local buf = buffer.copy("")
  assert(buf.ptr == nil)
  assert.equals(buf.cap, 0)
  assert.equals(buf.len, 0)

  local buf = buffer.wrap("")
  assert(buf.ptr ~= nil)
  assert.equals(buf.cap, 0)
  assert.equals(buf.len, 0)
end)
