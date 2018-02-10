local ffi = require('ffi')

ffi.cdef [[
char * getenv (const char *NAME);
int putenv (char *STRING);
int setenv (const char *NAME, const char *VALUE, int REPLACE);
int unsetenv (const char *NAME);
]]

local M = {}

local M_mt = {}

function M_mt:__index(name)
   assert(type(name)=="string")
   local value = ffi.C.getenv(name)
   if value == nil then
      return nil
   else
      return ffi.string(value)
   end
end

function M_mt:__newindex(name, value)
   assert(type(name)=="string")
   if value then
      return ffi.C.setenv(name, tostring(value), 1)
   else
      return ffi.C.unsetenv(name)
   end
end

return setmetatable(M, M_mt)
