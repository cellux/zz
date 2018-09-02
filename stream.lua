local ffi = require('ffi')
local sched = require('sched')
local util = require('util')
local buffer = require('buffer')
local mm = require('mm')

local M = {}

M.READ_BLOCK_SIZE = 4096

local Stream = util.Class()

function Stream:create(obj)
   local impl
   if type(obj.stream_impl) == "function" then
      impl = obj:stream_impl()
   else
      impl = obj
   end
   return {
      is_stream = true,
      impl = impl,
      read_buffer = buffer.new(),
   }
end

function Stream:close()
   return self.impl:close()
end

function Stream:eof()
   return #self.read_buffer == 0 and self.impl:eof()
end

function Stream:read1(ptr, size)
   local bytes_read = 0
   local bytes_left = size
   local dst = ffi.cast("uint8_t*", ptr)
   if #self.read_buffer > 0 then
      if #self.read_buffer > size then
         ffi.copy(dst, self.read_buffer.ptr, size)
         self.read_buffer = buffer.slice(self.read_buffer, size)
         bytes_read = size
         bytes_left = 0
      else
         ffi.copy(dst, self.read_buffer.ptr, #self.read_buffer)
         bytes_read = #self.read_buffer
         bytes_left = size - bytes_read
         self.read_buffer.len = 0
      end
   end
   if bytes_left > 0 then
      bytes_read = bytes_read + self.impl:read1(dst + bytes_read, bytes_left)
   end
   return bytes_read
end

function Stream:write1(ptr, size)
   return self.impl:write1(ptr, size)
end

function Stream:read(n)
   local READ_BLOCK_SIZE = M.READ_BLOCK_SIZE
   local buf
   if not n then
      -- read an arbitrary amount of bytes
      if #self.read_buffer > 0 then
         buf = self.read_buffer
         self.read_buffer = buffer.new()
      else
         mm.with_block(READ_BLOCK_SIZE, nil, function(ptr, block_size)
            local nbytes = self:read1(ptr, block_size)
            buf = buffer.copy(ptr, nbytes)
         end)
      end
   elseif n > 0 then
      -- read exactly N bytes or until EOF
      buf = buffer.new(n)
      local bytes_left = n
      while not self:eof() and bytes_left > 0 do
         if #self.read_buffer > 0 then
            if #self.read_buffer <= bytes_left then
               buf:append(self.read_buffer)
               bytes_left = bytes_left - #self.read_buffer
               self.read_buffer.len = 0
            else
               buf:append(self.read_buffer, bytes_left)
               -- buffer.slice() makes a copy of read_buffer[bytes_left:]
               -- the previous read_buffer will be disposed by the GC
               self.read_buffer = buffer.slice(self.read_buffer, bytes_left)
               bytes_left = 0
            end
         else
            local dst = buf.ptr + n - bytes_left
            local nbytes = self:read1(dst, bytes_left)
            buf.len = buf.len + nbytes
            bytes_left = bytes_left - nbytes
         end
      end
   elseif n == 0 then
      -- read until EOF
      local buffers = {}
      local nbytes_total = 0
      if #self.read_buffer > 0 then
         table.insert(buffers, self.read_buffer)
         nbytes_total = nbytes_total + #self.read_buffer
         self.read_buffer = buffer.new()
      end
      mm.with_block(READ_BLOCK_SIZE, nil, function(ptr, block_size)
         while not self:eof() do
            local nbytes = self:read1(ptr, block_size)
            if nbytes > 0 then
               table.insert(buffers, buffer.copy(ptr, nbytes))
               nbytes_total = nbytes_total + nbytes
            end
         end
      end)
      buf = buffer.new(nbytes_total)
      for i=1,#buffers do
         buf:append(buffers[i])
      end
   end
   return buf
end

ffi.cdef [[ void * memmem (const void *haystack, size_t haystack_len,
                           const void *needle, size_t needle_len); ]]

function Stream:read_until(marker, keep_marker)
   local buf = buffer.new()
   local start_search_at = 0
   while not self:eof() do
      local chunk = self:read()
      if #chunk == 0 then
         break
      end
      buf:append(chunk) -- buffer automatically grows as needed
      local search_ptr = buf.ptr + start_search_at
      local search_len = buf.len - start_search_at
      local p = ffi.cast("uint8_t*", ffi.C.memmem(search_ptr, search_len, marker, #marker))
      if p ~= nil then
         local marker_offset = p - buf.ptr
         local next_offset = marker_offset + #marker
         if next_offset < #buf then
            assert(#self.read_buffer == 0)
            self.read_buffer = buffer.slice(buf, next_offset)
         end
         if keep_marker then
            return buffer.copy(buf, next_offset), true
         else
            return buffer.copy(buf, marker_offset), true
         end
      else
         start_search_at = start_search_at + search_len - #marker + 1
      end
   end
   return buf, false
end

function Stream:readln(eol)
   return tostring(self:read_until(eol or "\x0a"))
end

function Stream:write(data)
   local size
   if buffer.is_buffer(data) then
      size = #data
      data = data.ptr
   end
   size = size or #data
   local nbytes = self:write1(ffi.cast("void*", data), size)
   assert(nbytes==size)
end

function Stream:writeln(line, eol)
   self:write(tostring(line))
   self:write(eol or "\x0a")
end

local function MemoryStream()
   local self = {}
   local buffers = {}
   function self:eof()
      return #buffers == 0
   end
   function self:write1(ptr, size)
      table.insert(buffers, buffer.copy(ptr, size))
      return size
   end
   function self:read1(ptr, size)
      local dst = ffi.cast("uint8_t*", ptr)
      local bytes_left = size
      while #buffers > 0 and bytes_left > 0 do
         local buf = buffers[1]
         local bufsize = #buf
         if bufsize > bytes_left then
            ffi.copy(dst, buf.ptr, bytes_left)
            buffers[1] = buffer.slice(buf, bytes_left)
            bytes_left = 0
         else
            ffi.copy(dst, buf.ptr, bufsize)
            dst = dst + bufsize
            bytes_left = bytes_left - bufsize
            table.remove(buffers, 1)
         end
      end
      return size - bytes_left
   end
   return Stream(self)
end

local function is_stream(x)
   return type(x) == "table" and x.is_stream
end

M.is_stream = is_stream

local function make_stream(x)
   if is_stream(x) then
      return x
   else
      local s = x and Stream(x) or MemoryStream()
      return util.chainlast(s, x)
   end
end

function M.copy(s1, s2, cb)
   s1 = make_stream(s1)
   s2 = make_stream(s2)
   return sched(function()
      mm.with_block(M.READ_BLOCK_SIZE, nil, function(ptr, block_size)
         while not s1:eof() do
            local nbytes = s1:read1(ptr, block_size)
            s2:write1(ptr, nbytes)
         end
      end)
      s1:close()
      if cb then
         cb()
      end
   end)
end

function M.pipe(s1, s2)
   s1 = make_stream(s1)
   s2 = make_stream(s2)
   return M.copy(s1, s2, function() s2:close() end)
end

local M_mt = {}

function M_mt:__call(...)
   return make_stream(...)
end

return setmetatable(M, M_mt)
