local ffi = require('ffi')

ffi.cdef [[

typedef struct {
  uint8_t *data;
  size_t size;
  size_t capacity;
} zz_buffer_t;

void zz_buffer_init(zz_buffer_t *self,
                    uint8_t *data,
                    size_t size,
                    size_t capacity);

zz_buffer_t * zz_buffer_new();
zz_buffer_t * zz_buffer_new_with_capacity(size_t capacity);
zz_buffer_t * zz_buffer_new_with_copy(void *data, size_t size);
zz_buffer_t * zz_buffer_new_with_data(void *data, size_t size);

size_t zz_buffer_resize(zz_buffer_t *self, size_t n);
size_t zz_buffer_append(zz_buffer_t *self, const void *data, size_t size);

int zz_buffer_equals(zz_buffer_t *self, zz_buffer_t *other);

void zz_buffer_fill(zz_buffer_t *self, uint8_t c);
void zz_buffer_clear(zz_buffer_t *self);
void zz_buffer_reset(zz_buffer_t *self);

void zz_buffer_free(zz_buffer_t *self);

struct zz_buffer_Buffer_ct {
  zz_buffer_t * buf;
};

]]

local is_buffer

local Buffer_mt = {}

function Buffer_mt:ptr()
   return self.buf.data
end

function Buffer_mt:size(new_size)
   if new_size then
      self.buf.size = new_size
   end
   return tonumber(self.buf.size)
end

function Buffer_mt:__len()
   return self:size()
end

function Buffer_mt:capacity(new_capacity)
   if new_capacity then
      ffi.C.zz_buffer_resize(self.buf, new_capacity)
   end
   return tonumber(self.buf.capacity)
end

function Buffer_mt:str(index, length)
   index = index or 0
   length = length or (tonumber(self.buf.size) - index)
   return ffi.string(self.buf.data+index, length)
end

function Buffer_mt:__tostring()
   return self:str()
end

function Buffer_mt:get(i)
   return self.buf.data[i]
end

function Buffer_mt:__index(i)
   if type(i) == "number" then
      return self.buf.data[i]
   else
      return rawget(Buffer_mt, i)
   end
end

function Buffer_mt:set(i, value)
   self.buf.data[i] = value
end

function Buffer_mt:__newindex(i, value)
   self.buf.data[i] = value
end

function Buffer_mt:append(buf, size)
   if is_buffer(buf) then
      size = size or #buf
      buf = buf:ptr()
   end
   return ffi.C.zz_buffer_append(self.buf, ffi.cast("void*", buf), size or #buf)
end

function Buffer_mt.__eq(buf1, buf2)
   if not buf1 or not buf2 then
      return false
   elseif type(buf1) == "string" then
      return buf1 == buf2:str()
   elseif type(buf2) == "string" then
      return buf1:str() == buf2
   else
      return ffi.C.zz_buffer_equals(buf1.buf, buf2.buf) ~= 0
   end
end

function Buffer_mt:fill(c)
   ffi.C.zz_buffer_fill(self.buf, c)
end

function Buffer_mt:clear()
   ffi.C.zz_buffer_clear(self.buf)
end

function Buffer_mt:reset()
   ffi.C.zz_buffer_reset(self.buf)
end

function Buffer_mt:free()
   if self.buf ~= nil then
      ffi.C.zz_buffer_free(self.buf)
      self.buf = nil
   end
end

Buffer_mt.__gc = Buffer_mt.free

local Buffer = ffi.metatype("struct zz_buffer_Buffer_ct", Buffer_mt)

local M = {}

is_buffer = function(x)
   return ffi.istype(Buffer, x)
end
M.is_buffer = is_buffer

local function new_with_default_capacity()
   return Buffer(ffi.C.zz_buffer_new())
end

local function new_with_capacity(capacity)
   return Buffer(ffi.C.zz_buffer_new_with_capacity(capacity))
end

local function new_with_copy(data, size)
   return Buffer(ffi.C.zz_buffer_new_with_copy(data, size))
end

local function new_with_data(data, size)
   return Buffer(ffi.C.zz_buffer_new_with_data(data, size))
end

function M.new(size)
   if size then
      return new_with_capacity(size)
   else
      return new_with_default_capacity()
   end
end

function M.new_with_size(size)
   local buf = new_with_capacity(size)
   buf:size(size)
   return buf
end

function M.copy(data, size)
   size = size or #data
   if is_buffer(data) then
      data = data:ptr()
   end
   return new_with_copy(ffi.cast("void*", data), size)
end

function M.slice(data, offset, size)
   offset = offset or 0
   size = size or (#data - offset)
   if is_buffer(data) then
      data = data:ptr()
   end
   data = ffi.cast("uint8_t*", data) + offset
   return new_with_copy(ffi.cast("void*", data), size)
end

function M.wrap(data, size)
   size = size or #data
   if is_buffer(data) then
      data = data:ptr()
   end
   return new_with_data(ffi.cast("void*", data), size)
end

return M
