local testing = require('testing')('msgpack')
local ffi = require('ffi')
local msgpack = require('msgpack')
local buffer = require('buffer')
local assert = require('assert')

local function test_pack_unpack(x)
   local packed = msgpack.pack(x)
   local unpacked = msgpack.unpack(packed)
   assert.equals(x, unpacked)
end

testing("msgpack", function()
   test_pack_unpack(nil)
   test_pack_unpack(true)
   test_pack_unpack(false)
   test_pack_unpack(0)
   test_pack_unpack(123)
   test_pack_unpack(123.25)
   test_pack_unpack("hello, world!")
   test_pack_unpack(buffer.copy("hello, world!"))
   test_pack_unpack({nil,true,false,0,123,123.25,"hello, world!"})
   test_pack_unpack({[0]=true,[1]=false,[123]={x=123.25,y=-123.5},str="hello, world!"})
end)

-- pack_array() ensures the table is packed as an array
-- it's the user's reponsibility to ensure that the array is valid

testing("pack_array", function()
   local packed = msgpack.pack_array({1,2,"abc",4})
   assert.equals(packed[0], 0x94, "initial byte of msgpacked {1,2,\"abc\",4}")
end)

testing("numbers are packed as doubles", function()
   local packed = msgpack.pack(1234)
   assert.equals(packed[0], 0xcb, "initial byte of msgpacked 1234")
end)

testing("packing pointers", function()
   local hello = "hello"
   ffi.cdef "struct zz_test_msgpack_t { int x; };"
   local test_struct = ffi.new("struct zz_test_msgpack_t", 42)
   -- pointers must be cast to size_t
   local packed = msgpack.pack({ffi.cast("size_t", ffi.cast("char*", hello)),
                                ffi.cast("size_t", ffi.cast("struct zz_test_msgpack_t*", test_struct))})
   local unpacked = msgpack.unpack(packed)
   -- and cast back to their original ptr type when unpacking
   assert.equals(ffi.string(ffi.cast("char*", unpacked[1])), hello)
   local unpacked_test_struct = ffi.cast("struct zz_test_msgpack_t*", unpacked[2])
   assert.equals(unpacked_test_struct.x, 42)
end)
