local ffi = require('ffi')

ffi.cdef [[

typedef struct {
  uint8_t *ptr;
  size_t cap; /* 0: we are not responsible for freeing data */
  size_t len;
} zz_buffer_t;

size_t zz_buffer_resize(zz_buffer_t *self, size_t new_cap);
size_t zz_buffer_append(zz_buffer_t *self, const void *data, size_t size);

int zz_buffer_equals(zz_buffer_t *self, zz_buffer_t *other);

]]

local ZZ_BUFFER_DEFAULT_CAPACITY = 1024

local is_buffer

local Buffer_mt = {}

function Buffer_mt:__len()
   return tonumber(self.len)
end

function Buffer_mt:str(index, length)
   index = index or 0
   length = length or (tonumber(self.len) - index)
   return ffi.string(self.ptr+index, length)
end

function Buffer_mt:__tostring()
   return self:str()
end

function Buffer_mt:get(i)
   return self.ptr[i]
end

function Buffer_mt:__index(i)
   if type(i) == "number" then
      return self.ptr[i]
   else
      return rawget(Buffer_mt, i)
   end
end

function Buffer_mt:set(i, value)
   self.ptr[i] = value
end

function Buffer_mt:__newindex(i, value)
   self.ptr[i] = value
end

function Buffer_mt:resize(new_cap)
   return ffi.C.zz_buffer_resize(self, new_cap)
end

function Buffer_mt:append(data, size)
   size = size or #data
   if is_buffer(data) then
      data = data.ptr
   end
   return ffi.C.zz_buffer_append(self, ffi.cast("void*", data), size)
end

function Buffer_mt.__eq(buf1, buf2)
   if not buf1 or not buf2 then
      return false
   elseif type(buf1) == "string" then
      return buf1 == buf2:str()
   elseif type(buf2) == "string" then
      return buf1:str() == buf2
   else
      return ffi.C.zz_buffer_equals(buf1, buf2) ~= 0
   end
end

function Buffer_mt:fill(c)
   ffi.fill(self.ptr, tonumber(self.len), c)
end

function Buffer_mt:clear()
   ffi.fill(self.ptr, tonumber(self.len), 0)
end

function Buffer_mt:stream_impl(stream)
   local buf = self
   local read_offset = 0
   function stream:close()
   end
   function stream:eof()
      return read_offset == #buf
   end
   function stream:read1(ptr, size)
      local nbytes = math.min(#buf - read_offset, size)
      ffi.copy(ptr, buf.ptr + read_offset, nbytes)
      read_offset = read_offset + nbytes
      return nbytes
   end
   function stream:write1(ptr, size)
      buf:append(ptr, size)
      return size
   end
   return stream
end

function Buffer_mt:free()
   if self.ptr ~= nil and tonumber(self.cap) > 0 then
      ffi.C.free(self.ptr)
      self.ptr = nil
   end
end

Buffer_mt.__gc = Buffer_mt.free

local Buffer = ffi.metatype("zz_buffer_t", Buffer_mt)

local M = {}

is_buffer = function(x)
   return ffi.istype(Buffer, x)
end
M.is_buffer = is_buffer

local nil_buffer = Buffer(nil, 0, 0)

function M.new(cap, len)
   cap = cap or ZZ_BUFFER_DEFAULT_CAPACITY
   len = len or 0
   if cap == 0 then
      return nil_buffer
   else
      local ptr = ffi.C.calloc(cap, 1)
      return Buffer(ptr, cap, len)
   end
end

function M.copy(data, size)
   size = size or #data
   if is_buffer(data) then
      data = data.ptr
   end
   local self = M.new(size, size)
   ffi.copy(self.ptr, data, size)
   return self
end

function M.slice(data, offset, size)
   offset = offset or 0
   size = size or (#data - offset)
   if is_buffer(data) then
      data = data.ptr
   end
   return M.copy(ffi.cast("uint8_t*", data) + offset, size)
end

function M.wrap(data, size)
   size = size or #data
   if is_buffer(data) then
      data = data.ptr
   end
   return Buffer(ffi.cast("uint8_t*", data), 0, size)
end

return M
