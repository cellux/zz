local ffi = require('ffi')
local buffer = require('buffer')

ffi.cdef [[

typedef bool   (*cmp_reader) (struct cmp_ctx_s *ctx,
                              void *data,
                              size_t limit);

typedef size_t (*cmp_writer) (struct cmp_ctx_s *ctx,
                              const void *data,
                              size_t count);

typedef struct cmp_ext_s {
  int8_t type;
  uint32_t size;
} cmp_ext_t;

union cmp_object_data_u {
  bool      boolean;
  uint8_t   u8;
  uint16_t  u16;
  uint32_t  u32;
  uint64_t  u64;
  int8_t    s8;
  int16_t   s16;
  int32_t   s32;
  int64_t   s64;
  float     flt;
  double    dbl;
  uint32_t  array_size;
  uint32_t  map_size;
  uint32_t  str_size;
  uint32_t  bin_size;
  cmp_ext_t ext;
};

typedef struct cmp_ctx_s {
  uint8_t     error;
  void       *buf;
  cmp_reader  read;
  cmp_writer  write;
} cmp_ctx_t;

typedef struct cmp_object_s {
  uint8_t type;
  union cmp_object_data_u as;
} cmp_object_t;

const char* cmp_strerror(cmp_ctx_t *ctx);

void cmp_init(cmp_ctx_t *ctx, void *buf, cmp_reader read, cmp_writer write);

bool cmp_write_sint(cmp_ctx_t *ctx, int64_t d);
bool cmp_write_uint(cmp_ctx_t *ctx, uint64_t u);
bool cmp_write_float(cmp_ctx_t *ctx, float f);
bool cmp_write_double(cmp_ctx_t *ctx, double d);
bool cmp_write_nil(cmp_ctx_t *ctx);
bool cmp_write_true(cmp_ctx_t *ctx);
bool cmp_write_false(cmp_ctx_t *ctx);
bool cmp_write_bool(cmp_ctx_t *ctx, bool b);
bool cmp_write_str(cmp_ctx_t *ctx, const char *data, uint32_t size);
bool cmp_write_bin(cmp_ctx_t *ctx, const void *data, uint32_t size);
bool cmp_write_array(cmp_ctx_t *ctx, uint32_t size);
bool cmp_write_map(cmp_ctx_t *ctx, uint32_t size);

bool cmp_read_char(cmp_ctx_t *ctx, int8_t *c);
bool cmp_read_short(cmp_ctx_t *ctx, int16_t *s);
bool cmp_read_int(cmp_ctx_t *ctx, int32_t *i);
bool cmp_read_long(cmp_ctx_t *ctx, int64_t *d);
bool cmp_read_sinteger(cmp_ctx_t *ctx, int64_t *d);
bool cmp_read_uchar(cmp_ctx_t *ctx, uint8_t *c);
bool cmp_read_ushort(cmp_ctx_t *ctx, uint16_t *s);
bool cmp_read_uint(cmp_ctx_t *ctx, uint32_t *i);
bool cmp_read_ulong(cmp_ctx_t *ctx, uint64_t *u);
bool cmp_read_uinteger(cmp_ctx_t *ctx, uint64_t *u);
bool cmp_read_float(cmp_ctx_t *ctx, float *f);
bool cmp_read_double(cmp_ctx_t *ctx, double *d);
bool cmp_read_nil(cmp_ctx_t *ctx);
bool cmp_read_bool(cmp_ctx_t *ctx, bool *b);
bool cmp_read_str_size(cmp_ctx_t *ctx, uint32_t *size);
bool cmp_read_str(cmp_ctx_t *ctx, char *data, uint32_t *size);
bool cmp_read_bin_size(cmp_ctx_t *ctx, uint32_t *size);
bool cmp_read_bin(cmp_ctx_t *ctx, void *data, uint32_t *size);
bool cmp_read_array(cmp_ctx_t *ctx, uint32_t *size);
bool cmp_read_map(cmp_ctx_t *ctx, uint32_t *size);
bool cmp_read_object(cmp_ctx_t *ctx, cmp_object_t *obj);

/* cmp-zz_buffer interop */

typedef struct {
  zz_buffer_t *buffer;
  uint32_t pos;
} zz_cmp_buffer_state;

bool zz_cmp_buffer_reader(struct cmp_ctx_s *ctx, void *data, size_t limit);
size_t zz_cmp_buffer_writer(struct cmp_ctx_s *ctx, const void *data, size_t count);

]]

local CMP_TYPE_POSITIVE_FIXNUM = 0
local CMP_TYPE_FIXMAP          = 1
local CMP_TYPE_FIXARRAY        = 2
local CMP_TYPE_FIXSTR          = 3
local CMP_TYPE_NIL             = 4
local CMP_TYPE_BOOLEAN         = 5
local CMP_TYPE_BIN8            = 6
local CMP_TYPE_BIN16           = 7
local CMP_TYPE_BIN32           = 8
local CMP_TYPE_EXT8            = 9
local CMP_TYPE_EXT16           = 10
local CMP_TYPE_EXT32           = 11
local CMP_TYPE_FLOAT           = 12
local CMP_TYPE_DOUBLE          = 13
local CMP_TYPE_UINT8           = 14
local CMP_TYPE_UINT16          = 15
local CMP_TYPE_UINT32          = 16
local CMP_TYPE_UINT64          = 17
local CMP_TYPE_SINT8           = 18
local CMP_TYPE_SINT16          = 19
local CMP_TYPE_SINT32          = 20
local CMP_TYPE_SINT64          = 21
local CMP_TYPE_FIXEXT1         = 22
local CMP_TYPE_FIXEXT2         = 23
local CMP_TYPE_FIXEXT4         = 24
local CMP_TYPE_FIXEXT8         = 25
local CMP_TYPE_FIXEXT16        = 26
local CMP_TYPE_STR8            = 27
local CMP_TYPE_STR16           = 28
local CMP_TYPE_STR32           = 29
local CMP_TYPE_ARRAY16         = 30
local CMP_TYPE_ARRAY32         = 31
local CMP_TYPE_MAP16           = 32
local CMP_TYPE_MAP32           = 33
local CMP_TYPE_NEGATIVE_FIXNUM = 34

local Context_mt = {}

function Context_mt:error()
   return ffi.string(ffi.C.cmp_strerror(self.ctx))
end

function Context_mt:write_sint(i)
   ffi.C.cmp_write_sint(self.ctx, i)
end

function Context_mt:write_uint(u)
   ffi.C.cmp_write_uint(self.ctx, u)
end

function Context_mt:write_float(f)
   ffi.C.cmp_write_float(self.ctx, f)
end

function Context_mt:write_double(d)
   ffi.C.cmp_write_double(self.ctx, d)
end

function Context_mt:write_nil()
   ffi.C.cmp_write_nil(self.ctx)
end

function Context_mt:write_true()
   ffi.C.cmp_write_true(self.ctx)
end

function Context_mt:write_false()
   ffi.C.cmp_write_false(self.ctx)
end

function Context_mt:write_bool(b)
   ffi.C.cmp_write_bool(self.ctx, b)
end

function Context_mt:write_str(data, size)
   ffi.C.cmp_write_str(self.ctx, ffi.cast('const char*', data), size or #data)
end

function Context_mt:write_bin(data, size)
   ffi.C.cmp_write_bin(self.ctx, ffi.cast('const void*', data), size or #data)
end

function Context_mt:write_table(t, format)
   if format == "map" then
      local size = 0
      for k,v in pairs(t) do
         size = size + 1
      end
      ffi.C.cmp_write_map(self.ctx, size)
      for k,v in pairs(t) do
         self:write(k)
         self:write(v)
      end
   elseif format == "array" then
      ffi.C.cmp_write_array(self.ctx, #t)
      for i=1,#t do
         self:write(t[i])
      end
   end
end

function Context_mt:write(o)
   if type(o) == "number" then
      self:write_double(o)
   elseif o == nil then
      self:write_nil()
   elseif type(o) == "boolean" then
      self:write_bool(o)
   elseif type(o) == "string" then
      self:write_str(o)
   elseif type(o) == "table" then
      self:write_table(o, "map")
   elseif ffi.istype("size_t", o) then
      -- pack pointers by casting them to size_t
      self:write_uint(o)
   elseif buffer.is_buffer(o) then
      self:write_bin(o.ptr, o.len)
   else
      ef("cannot serialize object %s", o)
   end
end

local readers = {}

readers[CMP_TYPE_NIL] = function(ctx, obj)
   return nil
end

readers[CMP_TYPE_BOOLEAN] = function(ctx, obj)
   return obj.as.boolean
end

readers[CMP_TYPE_POSITIVE_FIXNUM] = function(ctx, obj)
   return obj.as.u8
end

readers[CMP_TYPE_NEGATIVE_FIXNUM] = function(ctx, obj)
   return obj.as.s8
end

readers[CMP_TYPE_UINT8] = function(ctx, obj)
   return obj.as.u8
end

readers[CMP_TYPE_UINT16] = function(ctx, obj)
   return obj.as.u16
end

readers[CMP_TYPE_UINT32] = function(ctx, obj)
   return obj.as.u32
end

readers[CMP_TYPE_UINT64] = function(ctx, obj)
   return obj.as.u64
end

readers[CMP_TYPE_SINT8] = function(ctx, obj)
   return obj.as.s8
end

readers[CMP_TYPE_SINT16] = function(ctx, obj)
   return obj.as.s16
end

readers[CMP_TYPE_SINT32] = function(ctx, obj)
   return obj.as.s32
end

readers[CMP_TYPE_SINT64] = function(ctx, obj)
   return obj.as.s64
end

readers[CMP_TYPE_FLOAT] = function(ctx, obj)
   return obj.as.flt
end

readers[CMP_TYPE_DOUBLE] = function(ctx, obj)
   return obj.as.dbl
end

readers[CMP_TYPE_FIXSTR] = function(ctx, obj)
   local size = obj.as.str_size
   local buf = buffer.new(size)
   if not ctx.ctx.read(ctx.ctx, buf.ptr, size) then
      error("ctx->read() failed")
   end
   return ffi.string(buf.ptr, size)
end
readers[CMP_TYPE_STR8] = readers[CMP_TYPE_FIXSTR]
readers[CMP_TYPE_STR16] = readers[CMP_TYPE_FIXSTR]
readers[CMP_TYPE_STR32] = readers[CMP_TYPE_FIXSTR]

readers[CMP_TYPE_BIN8] = function(ctx, obj)
   local size = obj.as.bin_size
   local buf = buffer.new(size, size)
   if not ctx.ctx.read(ctx.ctx, buf.ptr, size) then
      error("ctx->read() failed")
   end
   return buf
end
readers[CMP_TYPE_BIN16] = readers[CMP_TYPE_BIN8]
readers[CMP_TYPE_BIN32] = readers[CMP_TYPE_BIN8]

readers[CMP_TYPE_FIXARRAY] = function(ctx, obj)
   local size = obj.as.array_size
   local array = {}
   for i=1,size do
      local v = ctx:read()
      table.insert(array, v)
   end
   return array
end
readers[CMP_TYPE_ARRAY16] = readers[CMP_TYPE_FIXARRAY]
readers[CMP_TYPE_ARRAY32] = readers[CMP_TYPE_FIXARRAY]

readers[CMP_TYPE_FIXMAP] = function(ctx, obj)
   local size = obj.as.map_size
   local map = {}
   for i=1,size do
      local k = ctx:read()
      local v = ctx:read()
      map[k] = v
   end
   return map
end
readers[CMP_TYPE_MAP16] = readers[CMP_TYPE_FIXMAP]
readers[CMP_TYPE_MAP32] = readers[CMP_TYPE_FIXMAP]

function Context_mt:read()
   local obj = ffi.new("cmp_object_t")
   if not ffi.C.cmp_read_object(self.ctx, obj) then
      ef("cmp_read_object() failed: %s", self:error())
   end
   local obj_type = tonumber(obj.type)
   local reader = readers[obj_type]
   if not reader then
      error("cannot read object: unknown (or unhandled) type")
   end
   return reader(self, obj)
end

Context_mt.__index = Context_mt

local function Context(buf)
   buf = buf or buffer.new()
   local self = {
      buf = buf,
      ctx = ffi.new("cmp_ctx_t"),
      state = ffi.new("zz_cmp_buffer_state", buf, 0),
   }
   ffi.C.cmp_init(self.ctx,
                  self.state,
                  ffi.C.zz_cmp_buffer_reader,
                  ffi.C.zz_cmp_buffer_writer)
   return setmetatable(self, Context_mt)
end

--

local M = {}

function M.pack(obj)
   local ctx = Context()
   ctx:write(obj)
   return ctx.buf
end

function M.pack_array(obj)
   local ctx = Context()
   ctx:write_table(obj, "array")
   return ctx.buf
end

function M.unpack(data)
   local buf = buffer.wrap(data)
   local ctx = Context(buf)
   return ctx:read()
end

return M
