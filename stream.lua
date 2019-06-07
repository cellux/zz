local ffi = require('ffi')
local bit = require('bit')
local sched = require('sched')
local util = require('util')
local buffer = require('buffer')
local mm = require('mm')
local re = require('re')

local M = {}

local function ReadBuffer()
   local buf = buffer.new()
   local offset = 0
   return {
      length = function(self)
         return tonumber(buf.len - offset)
      end,
      ptr = function(self)
         return buf.ptr + offset
      end,
      consume = function(self, nbytes)
         offset = offset + nbytes
         assert(offset <= buf.len)
      end,
      clear = function(self)
         buf.len = 0
         offset = 0
      end,
      get = function(self)
         local rv
         if offset == 0 then
            rv = buf
            buf = buffer.new()
         else
            rv = buffer.slice(buf, offset)
            self:clear()
         end
         return rv
      end,
      set = function(self, newbuf)
         buf = newbuf
         offset = 0
      end,
      fill = function(self, stream, size)
         if stream:eof() then return end
         size = size or (buf.cap - offset)
         if self:length() < size then
            local desired_cap = offset + size
            if buf.cap < desired_cap then
               buf:resize(desired_cap)
            end
            local dst = buf.ptr + buf.len
            local bytes_to_read = size - self:length()
            local nbytes = stream:read1_raw(dst, bytes_to_read)
            buf.len = buf.len + nbytes
         end
      end
   }
end

M.READ_BLOCK_SIZE = 4096

local Stream = util.Class()

function Stream:new(obj)
   local self = { obj = obj } -- keep reference to prevent GC
   if type(obj) == "string" then
      obj = buffer.wrap(obj)
   end
   if type(obj.as_stream) == "function" then
      -- obj can create another object which implements the stream API
      self.impl = obj:as_stream()
   else
      -- obj directly implements the stream API
      self.impl = obj
   end
   self.read_buffer = ReadBuffer()
   self.is_stream = true
   return self
end

function Stream:close()
   return self.impl.close and self.impl:close()
end

function Stream:eof()
   return self.read_buffer:length() == 0 and self.impl:eof()
end

function Stream:read1_raw(ptr, size)
   return self.impl:read1(ptr, size)
end

function Stream:read1(ptr, size)
   local bytes_read = 0
   local bytes_left = size
   local dst = ffi.cast("uint8_t*", ptr)
   local rbl = self.read_buffer:length()
   if rbl > 0 then
      if rbl > size then
         ffi.copy(dst, self.read_buffer:ptr(), size)
         self.read_buffer:consume(size)
         bytes_read = size
         bytes_left = 0
      else
         ffi.copy(dst, self.read_buffer:ptr(), rbl)
         bytes_read = rbl
         bytes_left = size - bytes_read
         self.read_buffer:clear()
      end
   end
   if bytes_left > 0 then
      bytes_read = bytes_read + self:read1_raw(dst + bytes_read, bytes_left)
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
      if self.read_buffer:length() > 0 then
         buf = self.read_buffer:get()
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
         local rbl = self.read_buffer:length()
         if rbl > 0 then
            if rbl <= bytes_left then
               buf:append(self.read_buffer:ptr(), rbl)
               bytes_left = bytes_left - rbl
               self.read_buffer:clear()
            else
               buf:append(self.read_buffer:ptr(), bytes_left)
               self.read_buffer:consume(bytes_left)
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
      local rbl = self.read_buffer:length()
      if rbl > 0 then
         table.insert(buffers, self.read_buffer:get())
         nbytes_total = nbytes_total + rbl
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

function Stream:slurp()
   local data = self:read(0)
   self:close()
   return data
end

function Stream:unread(data)
   local rbl = self.read_buffer:length()
   if rbl == 0 then
      if buffer.is_buffer(data) then
         self.read_buffer:set(data)
      else
         self.read_buffer:set(buffer.copy(data))
      end
   else
      local read_buffer = buffer.new(#data + rbl)
      read_buffer:append(data)
      read_buffer:append(self.read_buffer:ptr(), rbl)
      self.read_buffer:set(read_buffer)
   end
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
            assert(self.read_buffer:length() == 0)
            self.read_buffer:set(buffer.slice(buf, next_offset))
         end
         if keep_marker then
            return buffer.copy(buf, next_offset), true
         else
            return buffer.copy(buf, marker_offset), true
         end
      else
         start_search_at = buf.len - #marker + 1
      end
   end
   return buf, false
end

function Stream:match(pattern)
   pattern = re.compile(pattern)
   local buf = buffer.new()
   local startoffset = 0
   while true do
      local chunk = self:read()
      if #chunk == 0 then
         assert(self.read_buffer:length() == 0)
         self.read_buffer:set(buf)
         break
      end
      buf:append(chunk)
      local m, is_partial = pattern:match(buf, startoffset, bit.bor(re.PARTIAL, re.NOTEMPTY))
      if m then
         local match, lo, hi = m:group(0)
         if is_partial then
            startoffset = lo
         else
            if hi < #buf then
               assert(self.read_buffer:length() == 0)
               self.read_buffer:set(buffer.slice(buf, hi))
            end
            return m
         end
      else
         startoffset = buf.len
      end
   end
   return nil
end

function Stream:read_byte()
   local byte
   self.read_buffer:fill(self)
   if self.read_buffer:length() > 0 then
      byte = self.read_buffer:ptr()[0]
      self.read_buffer:consume(1)
   end
   return byte
end

function Stream:read_char()
   local byte = self:read_byte()
   return byte and string.char(byte) or nil
end

function Stream:readln(eol)
   return tostring(self:read_until(eol or "\x0a"))
end

function Stream:peek(size)
   self.read_buffer:fill(self, size)
   return buffer.copy(self.read_buffer:ptr(),
                      math.min(size, self.read_buffer:length()))
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

function Stream:read_be(nbytes)
   local rv = 0
   for i=1,nbytes do
      rv = bit.bor(bit.lshift(rv, 8), self:read_byte())
   end
   return rv
end

local function be2le(nbytes, value)
   while nbytes < 4 do
      value = bit.lshift(value, 8)
      nbytes = nbytes + 1
   end
   return bit.bswap(value)
end

function Stream:read_le(nbytes)
   local value = self:read_be(nbytes)
   return be2le(nbytes, value)
end

function Stream:write_le(nbytes, value)
   return mm.with_block(nbytes, "uint8_t*", function(ptr, block_size)
      for i=1,nbytes do
         ptr[i-1] = bit.band(value, 0xff)
         value = bit.rshift(value, 8)
      end
      return self:write1(ptr, nbytes)
   end)
end

function Stream:write_be(nbytes, value)
   value = be2le(nbytes, value)
   return self:write_le(nbytes, value)
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
      if x then
         return util.chainlast(Stream(x), x)
      else
         return MemoryStream()
      end
   end
end

function M.copy(s1, s2)
   s1 = make_stream(s1)
   s2 = make_stream(s2)
   mm.with_block(M.READ_BLOCK_SIZE, nil, function(ptr, block_size)
      while not s1:eof() do
         local nbytes = s1:read1(ptr, block_size)
         s2:write1(ptr, nbytes)
      end
   end)
end

function M.pipe(s1, s2)
   return sched(function()
      s1 = make_stream(s1)
      s2 = make_stream(s2)
      M.copy(s1, s2)
      s1:close()
      s2:close()
   end)
end

function M.duplex(input, output)
   local self = {}
   input = make_stream(input)
   output = make_stream(output)
   function self:eof()
      return input:eof()
   end
   function self:read1(ptr, size)
      return input:read1(ptr, size)
   end
   function self:write1(ptr, size)
      return output:write1(ptr, size)
   end
   return Stream(self)
end

local M_mt = {}

function M_mt:__call(...)
   return make_stream(...)
end

return setmetatable(M, M_mt)
