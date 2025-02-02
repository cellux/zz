local testing = require('testing')
local ffi = require('ffi')
local fs = require('fs') -- for ffi.C.open()
local errno = require('errno')
local assert = require('assert')

testing("errno", function()
   local res = ffi.C.open("/xxx/non-existent", ffi.C.O_RDONLY, 0)
   assert(res==-1)
   assert(errno.errno()==ffi.C.ENOENT)
   --  calling errno.errno() does not consume the error code
   assert(errno.errno()==ffi.C.ENOENT)
   assert.equals(errno.strerror(), "No such file or directory")
end)
