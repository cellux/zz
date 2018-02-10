local ffi = require('ffi')
local util = require('util')
local buffer = require('buffer')
local mm = require('mm')

local M = {}

M.READ_BLOCK_SIZE = 4096

local BaseStream = util.Class()

function BaseStream:eof()
   ef("to be implemented")
end

function BaseStream:read1(ptr, size)
   ef("to be implemented")
end

function BaseStream:write1(ptr, size)
   ef("to be implemented")
end

function BaseStream:read(n)
   local READ_BLOCK_SIZE = M.READ_BLOCK_SIZE
   local buf
   if not n then
      -- read any amount of bytes
      if self.read_buffer then
         buf = self.read_buffer
         self.read_buffer = nil
      else
         local ptr, block_size = mm.get_block(READ_BLOCK_SIZE)
         local nbytes = self:read1(ptr, block_size)
         buf = buffer.copy(ptr, nbytes)
         buf:size(nbytes)
         mm.ret_block(ptr, block_size)
      end
   elseif n > 0 then
      -- read exactly N bytes or until EOF
      buf = buffer.new(n)
      local bytes_left = n
      while not self:eof() and bytes_left > 0 do
         if self.read_buffer then
            if #self.read_buffer <= bytes_left then
               buf:append(self.read_buffer)
               bytes_left = bytes_left - #self.read_buffer
               self.read_buffer = nil
            else
               buf:append(self.read_buffer, bytes_left)
               self.read_buffer = buffer.slice(self.read_buffer, bytes_left)
               bytes_left = 0
            end
         else
            local dst = buf:ptr() + n - bytes_left
            local nbytes = self:read1(dst, bytes_left)
            buf:size(#buf + nbytes)
            bytes_left = bytes_left - nbytes
         end
      end
   elseif n == 0 then
      -- read until EOF
      local buffers = {}
      local nbytes_total = 0
      if self.read_buffer then
         table.insert(buffers, self.read_buffer)
         nbytes_total = nbytes_total + #self.read_buffer
         self.read_buffer = nil
      end
      local ptr, block_size = mm.get_block(READ_BLOCK_SIZE)
      while not self:eof() do
         local nbytes = self:read1(ptr, block_size)
         assert(nbytes > 0)
         table.insert(buffers, buffer.copy(ptr, nbytes))
         nbytes_total = nbytes_total + nbytes
      end
      mm.ret_block(ptr, block_size)
      buf = buffer.new(nbytes_total)
      for i=1,#buffers do
         buf:append(buffers[i])
      end
   end
   return buf
end

ffi.cdef [[ void * memmem (const void *haystack, size_t haystack_len,
                           const void *needle, size_t needle_len); ]]

function BaseStream:read_until(marker)
   local buf = buffer.new()
   local start_search_at = 0
   while not self:eof() do
      local chunk = self:read()
      buf:append(chunk) -- buffer automatically grows as needed
      local search_ptr = buf:ptr() + start_search_at
      local search_len = #buf - start_search_at
      local p = ffi.cast("uint8_t*", ffi.C.memmem(search_ptr, search_len, marker, #marker))
      if p ~= nil then
         local marker_offset = p - buf:ptr()
         local next_offset = marker_offset + #marker
         if next_offset < #buf then
            assert(self.read_buffer==nil)
            self.read_buffer = buffer.slice(buf, next_offset)
         end
         return buffer.copy(buf, marker_offset)
      else
         start_search_at = start_search_at + search_len - #marker + 1
      end
   end
   return buf
end

function BaseStream:readln()
   return tostring(self:read_until("\x0a"))
end

function BaseStream:write(data)
   local size
   if buffer.is_buffer(data) then
      size = #data
      data = data:ptr()
   end
   size = size or #data
   local nbytes = self:write1(ffi.cast("void*", data), size)
   assert(nbytes==size)
end

function BaseStream:writeln(line)
   self:write(tostring(line))
   self:write("\x0a")
end

local MemoryStream = util.Class(BaseStream)

function MemoryStream:create()
   return {
      buffers = {}
   }
end

function MemoryStream:eof()
   return #self.buffers == 0 and not self.read_buffer
end

function MemoryStream:write1(ptr, size)
   table.insert(self.buffers, buffer.copy(ptr, size))
   return size
end

function MemoryStream:read1(ptr, size)
   local dst = ffi.cast("uint8_t*", ptr)
   local bytes_left = size
   while #self.buffers > 0 and bytes_left > 0 do
      local buf = self.buffers[1]
      local bufsize = #buf
      if bufsize > bytes_left then
         ffi.copy(dst, buf:ptr(), bytes_left)
         self.buffers[1] = buffer.slice(buf, bytes_left)
         bytes_left = 0
      else
         ffi.copy(dst, buf:ptr(), bufsize)
         dst = dst + bufsize
         bytes_left = bytes_left - bufsize
         table.remove(self.buffers, 1)
      end
   end
   return size - bytes_left
end

local function make_stream(x)
   if not x then
      return MemoryStream()
   elseif (type(x)=="table" or type(x)=="cdata") and type(x.stream_impl)=="function" then
      local s = BaseStream()
      return x:stream_impl(s)
   else
      ef("cannot create stream of %s", x)
   end
end

local M_mt = {}

function M_mt:__call(...)
   return make_stream(...)
end

return setmetatable(M, M_mt)
