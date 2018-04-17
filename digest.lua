local ssl = require('openssl')
local buffer = require('buffer')

local M = {}

local M_mt = {}

function M_mt:__index(digest_type)
   return function(data)
      if data then
         local buf = buffer.wrap(data)
         local md = ssl.Digest(digest_type)
         md:update(buf.ptr, #buf)
         return md:final()
      else
         return ssl.Digest(digest_type)
      end
   end
end

return setmetatable(M, M_mt)
