local testing = require('testing')('msgpack')
local ffi = require('ffi')
local bit = require('bit')
local msgpack = require('msgpack')
local buffer = require('buffer')
local assert = require('assert')
local util = require('util')

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

testing("arrays", function()
   local packed = msgpack.pack_array({1,2,"abc",4})
   assert.equals(packed[0], 0x94, "initial byte of msgpacked {1,2,\"abc\",4}")
end)

testing("floats", function()
   local packed = msgpack.pack(1234.25)
   assert.equals(packed[0], 0xca, "initial byte of msgpacked 1234.25")
   local packed = msgpack.pack(-1234.25)
   assert.equals(packed[0], 0xca, "initial byte of msgpacked -1234.25")
end)

testing("doubles", function()
   local packed = msgpack.pack(123412341234.25)
   assert.equals(packed[0], 0xcb, "initial byte of msgpacked 123412341234.25")
   local packed = msgpack.pack(-123412341234.25)
   assert.equals(packed[0], 0xcb, "initial byte of msgpacked -123412341234.25")
end)

testing("zero", function()
   assert.equals(msgpack.pack(0), "\x00")
   assert.equals(msgpack.pack(0.0), "\x00")
   assert.equals(msgpack.pack(-0), "\x00")
   assert.equals(msgpack.pack(-0.0), "\x00")
end)

testing("positive integers", function()
   assert.equals(msgpack.pack(1), "\x01")
   assert.equals(msgpack.pack(2), "\x02")
   assert.equals(msgpack.pack(126), "\x7e")
   assert.equals(msgpack.pack(127), "\x7f")

   assert.equals(msgpack.pack(128), "\xcc\x80")
   assert.equals(msgpack.pack(129), "\xcc\x81")
   assert.equals(msgpack.pack(192), "\xcc\xc0")
   assert.equals(msgpack.pack(254), "\xcc\xfe")
   assert.equals(msgpack.pack(255), "\xcc\xff")

   assert.equals(msgpack.pack(2^8+0), "\xcd\x01\x00")
   assert.equals(msgpack.pack(2^8+1), "\xcd\x01\x01")
   assert.equals(msgpack.pack(2^16-2), "\xcd\xff\xfe")
   assert.equals(msgpack.pack(2^16-1), "\xcd\xff\xff")

   assert.equals(msgpack.pack(2^16+0), "\xce\x00\x01\x00\x00")
   assert.equals(msgpack.pack(2^16+1), "\xce\x00\x01\x00\x01")
   assert.equals(util.hexstr(msgpack.pack(2^32-2)), "cefffffffe")
   assert.equals(util.hexstr(msgpack.pack(2^32-1)), "ceffffffff")
   assert.equals(util.hexstr(msgpack.pack(2^32+0)), "cf0000000100000000")
   assert.equals(util.hexstr(msgpack.pack(2^32+1)), "cf0000000100000001")

   -- Lua numbers are doubles so they cannot represent 2^64-1
end)

testing("negative integers", function()
   assert.equals(msgpack.pack(-1), "\xff")
   assert.equals(msgpack.pack(-2), "\xfe")
   assert.equals(msgpack.pack(-31), "\xe1")
   assert.equals(msgpack.pack(-32), "\xe0")

   assert.equals(msgpack.pack(-33), "\xd0\xdf")
   assert.equals(msgpack.pack(-34), "\xd0\xde")
   assert.equals(msgpack.pack(-127), "\xd0\x81")
   assert.equals(msgpack.pack(-128), "\xd0\x80")

   assert.equals(msgpack.pack(-2^7-1), "\xd1\xff\x7f")
   assert.equals(msgpack.pack(-2^7-2), "\xd1\xff\x7e")
   assert.equals(msgpack.pack(-2^15+1), "\xd1\x80\x01")
   assert.equals(msgpack.pack(-2^15+0), "\xd1\x80\x00")

   assert.equals(msgpack.pack(-2^15-1), "\xd2\xff\xff\x7f\xff")
   assert.equals(msgpack.pack(-2^15-2), "\xd2\xff\xff\x7f\xfe")
   assert.equals(msgpack.pack(-2^31+1), "\xd2\x80\x00\x00\x01")
   assert.equals(msgpack.pack(-2^31+0), "\xd2\x80\x00\x00\x00")

   assert.equals(msgpack.pack(-2^31-1), "\xd3\xff\xff\xff\xff\x7f\xff\xff\xff")
   assert.equals(msgpack.pack(-2^31-2), "\xd3\xff\xff\xff\xff\x7f\xff\xff\xfe")
end)

testing("pointers", function()
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
