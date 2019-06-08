local ffi = require('ffi')
local bit = require('bit')
local time = require('time')
local mm = require('mm')
local util = require('util')
local fs = require('fs')
local stream = require('stream')
local buffer = require('buffer')

ffi.cdef [[

/*** zlib ***/

typedef uint8_t Bytef;
typedef unsigned int uInt;
typedef __UWORD_TYPE uLong;
typedef void *voidpf;

typedef voidpf (*alloc_func) (voidpf opaque, uInt items, uInt size);
typedef void   (*free_func)  (voidpf opaque, voidpf address);

typedef struct z_stream_s {
  Bytef    *next_in;  /* next input byte */
  uInt     avail_in;  /* number of bytes available at next_in */
  uLong    total_in;  /* total number of input bytes read so far */

  Bytef    *next_out; /* next output byte will go here */
  uInt     avail_out; /* remaining free space at next_out */
  uLong    total_out; /* total number of bytes output so far */

  char     *msg;      /* last error message, NULL if no error */
  struct internal_state *state; /* not visible by applications */

  alloc_func zalloc;  /* used to allocate the internal state */
  free_func  zfree;   /* used to free the internal state */
  voidpf     opaque;  /* private data object passed to zalloc and zfree */

  int     data_type;  /* best guess about the data type: binary or text
                         for deflate, or the decoding state for inflate */
  uLong   adler;      /* Adler-32 or CRC-32 value of the uncompressed data */
  uLong   reserved;   /* reserved for future use */
} z_stream;

typedef z_stream *z_streamp;

/* constants */

enum {
  Z_NO_FLUSH      = 0,
  Z_PARTIAL_FLUSH = 1,
  Z_SYNC_FLUSH    = 2,
  Z_FULL_FLUSH    = 3,
  Z_FINISH        = 4,
  Z_BLOCK         = 5,
  Z_TREES         = 6
};

enum {
  Z_OK            =  0,
  Z_STREAM_END    =  1,
  Z_NEED_DICT     =  2,
  Z_ERRNO         = (-1),
  Z_STREAM_ERROR  = (-2),
  Z_DATA_ERROR    = (-3),
  Z_MEM_ERROR     = (-4),
  Z_BUF_ERROR     = (-5),
  Z_VERSION_ERROR = (-6)
};

enum {
  Z_NO_COMPRESSION      =   0,
  Z_BEST_SPEED          =   1,
  Z_BEST_COMPRESSION    =   9,
  Z_DEFAULT_COMPRESSION = (-1)
};

enum {
  Z_FILTERED         = 1,
  Z_HUFFMAN_ONLY     = 2,
  Z_RLE              = 3,
  Z_FIXED            = 4,
  Z_DEFAULT_STRATEGY = 0
};

enum {
  Z_BINARY   = 0,
  Z_TEXT     = 1,
  Z_ASCII    = Z_TEXT,
  Z_UNKNOWN  = 2
};

enum {
  Z_DEFLATED = 8
};

const char * zlibVersion (void);

int deflateInit2_ (
  z_streamp strm,
  int level,
  int method,
  int windowBits,
  int memLevel,
  int strategy,
  const char *version,
  int stream_size);
int deflate (z_streamp strm, int flush);
int deflateEnd (z_streamp strm);
int deflatePending (
  z_streamp strm,
  unsigned *pending,
  int *bits);

int inflateInit2_ (
  z_streamp strm,
  int windowBits,
  const char *version,
  int stream_size);
int inflate (z_streamp strm, int flush);
int inflateEnd (z_streamp strm);

uLong crc32 (uLong crc, const Bytef *buf, uInt len);

/*** zip ***/

struct zz_zip_central_file_header {
  uint32_t signature; /* 0x02014b50 */
  uint16_t made_by_version;
  uint16_t extract_version;
  uint16_t bit_flags;
  uint16_t compression_method;
  uint16_t mtime;
  uint16_t mdate;
  uint32_t crc32;
  uint32_t compressed_size;
  uint32_t uncompressed_size;
  uint16_t file_name_length;
  uint16_t extra_field_length;
  uint16_t file_comment_length;
  uint16_t disk_number_start;
  uint16_t internal_attributes;
  uint32_t external_attributes;
  uint32_t local_header_offset;

  /* file name (variable length) */
  /* extra field (variable length) */
  /* file comment (variable length) */
};

struct zz_zip_local_file_header {
  uint32_t signature; /* 0x04034b50 */
  uint16_t extract_version;
  uint16_t bit_flags;
  uint16_t compression_method;
  uint16_t mtime;
  uint16_t mdate;
  uint32_t crc32;
  uint32_t compressed_size;
  uint32_t uncompressed_size;
  uint16_t file_name_length;
  uint16_t extra_field_length;

  /* file name (variable length) */
  /* extra field (variable length) */
};

struct zz_zip_eocd { /* end-of-central-directory */
  uint32_t signature; /* 0x06054b50 */
  uint16_t disk_number;
  uint16_t disk_number_of_eocd;
  uint16_t num_entries_disk; /* number of entries on this disk */
  uint16_t num_entries_total;
  uint32_t central_directory_size; /* in bytes */
  uint32_t central_directory_offset; /* from beginning of first disk */
  uint16_t zip_comment_length;

  /* zip comment (variable length) */
};

]]

local z = ffi.load("z")

local M = {}

local BUF_SIZE = 16384

local CENTRAL_FILE_HEADER_SIGNATURE = 0x02014b50
local LOCAL_FILE_HEADER_SIGNATURE   = 0x04034b50
local EOCD_SIGNATURE                = 0x06054b50

local CENTRAL_FILE_HEADER_SIZE = 46
local LOCAL_FILE_HEADER_SIZE   = 30
local EOCD_SIZE                = 22

local function zlibVersion()
   return ffi.string(z.zlibVersion())
end

function M.deflate(input)
   input = stream(input)

   local z_stream = ffi.new("z_stream")
   z_stream.zalloc = nil
   z_stream.zfree = nil
   z_stream.opaque = nil

   local level = z.Z_DEFAULT_COMPRESSION
   local method = z.Z_DEFLATED
   local windowBits = -15 -- raw deflate with 32k window
   local memLevel = 8
   local strategy = z.Z_DEFAULT_STRATEGY
   local version = z.zlibVersion()
   local stream_size = ffi.sizeof("z_stream")

   util.check_ok("deflateInit2_", z.Z_OK, z.deflateInit2_(
     z_stream, level, method, windowBits, memLevel, strategy,
     version, stream_size))

   local buf = ffi.new("uint8_t[?]", BUF_SIZE)
   z_stream.next_in = buf
   z_stream.avail_in = 0

   local flush = z.Z_NO_FLUSH
   local stream_end = false

   return stream {
      close = function(self)
         if z_stream ~= nil then
            z.deflateEnd(z_stream)
            z_stream = nil
            buf = nil
            input:close()
         end
      end,
      eof = function(self)
         return stream_end
      end,
      read1 = function(self, ptr, size)
         if stream_end then
            return 0
         end
         if z_stream.avail_in == 0 then
            if input:eof() then
               flush = z.Z_FINISH
            else
               z_stream.next_in = buf
               z_stream.avail_in = input:read1(buf, BUF_SIZE)
            end
         end
         z_stream.next_out = ptr
         z_stream.avail_out = size
         local rv = z.deflate(z_stream, flush)
         if rv == z.Z_STREAM_END then
            stream_end = true
         elseif rv ~= z.Z_OK and rv ~= z.Z_BUF_ERROR then
            ef("deflate failed (%d)", rv)
         end
         local nbytes = z_stream.next_out - ptr
         return nbytes
      end,
      write1 = function(self)
         ef("unimplemented")
      end
   }
end

function M.inflate(input)
   input = stream(input)

   local z_stream = ffi.new("z_stream")
   z_stream.zalloc = nil
   z_stream.zfree = nil
   z_stream.opaque = nil

   local windowBits = -15 -- raw inflate with 32k window
   local version = z.zlibVersion()
   local stream_size = ffi.sizeof("z_stream")

   util.check_ok("inflateInit2_", z.Z_OK, z.inflateInit2_(
      z_stream, windowBits, version, stream_size))

   local buf = ffi.new("uint8_t[?]", BUF_SIZE)
   z_stream.next_in = buf
   z_stream.avail_in = 0

   local flush = z.Z_NO_FLUSH
   local stream_end = false

   return stream {
      close = function(self)
         if z_stream ~= nil then
            z.inflateEnd(z_stream)
            z_stream = nil
            buf = nil
            input:close()
         end
      end,
      eof = function(self)
         return stream_end
      end,
      read1 = function(self, ptr, size)
         if stream_end then
            return 0
         end
         if z_stream.avail_in == 0 then
            if input:eof() then
               flush = z.Z_FINISH
            else
               z_stream.next_in = buf
               z_stream.avail_in = input:read1(buf, BUF_SIZE)
            end
         end
         z_stream.next_out = ptr
         z_stream.avail_out = size
         local rv = z.inflate(z_stream, flush)
         if rv == z.Z_STREAM_END then
            stream_end = true
         elseif rv ~= z.Z_OK and rv ~= z.Z_BUF_ERROR then
            ef("inflate failed (%d)", rv)
         end
         local nbytes = z_stream.next_out - ptr
         return nbytes
      end,
      write1 = function(self)
         ef("unimplemented")
      end
   }
end

local EOCD = util.Class()

function EOCD:new(opts)
   local self = {
      disk_number = opts.disk_number or 0,
      disk_number_of_eocd = opts.disk_number_of_eocd or 0,
      num_entries_disk = opts.num_entries_disk or opts.num_entries_total or 0,
      num_entries_total = opts.num_entries_total or 0,
      central_directory_size = opts.central_directory_size or 0,
      central_directory_offset = opts.central_directory_offset or 0,
      zip_comment_length = 0
   }
   return self
end

function EOCD:write(f)
   local s = stream(f)
   s:write_le(4, EOCD_SIGNATURE)
   s:write_le(2, self.disk_number)
   s:write_le(2, self.disk_number_of_eocd)
   s:write_le(2, self.num_entries_disk)
   s:write_le(2, self.num_entries_total)
   s:write_le(4, self.central_directory_size)
   s:write_le(4, self.central_directory_offset)
   s:write_le(2, self.zip_comment_length) -- should be zero
end

local function read_eocd(f)
   if f:size() < EOCD_SIZE then
      return nil
   end
   f:seek(-EOCD_SIZE)
   local s = stream(f)
   local signature = s:read_le(4)
   if signature ~= EOCD_SIGNATURE then
      return nil
   end
   local opts = {}
   opts.disk_number = s:read_le(2)
   opts.disk_number_of_eocd = s:read_le(2)
   opts.num_entries_disk = s:read_le(2)
   opts.num_entries_total = s:read_le(2)
   opts.central_directory_size = s:read_le(4)
   opts.central_directory_offset = s:read_le(4)
   opts.zip_comment_length = s:read_le(2)
   assert(opts.zip_comment_length == 0)
   return EOCD(opts)
end

local function to_msdos_date(tm)
   return bit.bor(
      bit.lshift(tm.year-80, 9),
      bit.lshift(tm.mon+1, 5),
      tm.mday)
end

local function to_msdos_time(tm)
   return bit.bor(
      bit.lshift(tm.hour, 11),
      bit.lshift(tm.min, 5),
      bit.rshift(tm.sec, 1))
end

local function from_msdos_date_and_time(dos_date, dos_time)
   local tm = time.gmtime()

   tm.year = bit.band(bit.rshift(dos_date, 9), 0x7f) + 80
   tm.mon = bit.band(bit.rshift(dos_date, 5), 0x0f) - 1
   tm.mday = bit.band(dos_date, 0x1f)

   tm.hour = bit.band(bit.rshift(dos_time, 11), 0x1f)
   tm.min = bit.band(bit.rshift(dos_time, 5), 0x3f)
   tm.sec = bit.band(bit.lshift(dos_time, 1), 0x3f)

   return tm
end

local ZipEntry = util.Class()

function ZipEntry:new(opts)
   local self = {
      file_name = opts.file_name,
      extra_field = opts.extra_field,
      file_comment = opts.file_comment,
      made_by_version = opts.made_by_version or 20,
      extract_version = opts.extract_version or 20,
      bit_flags = opts.bit_flags or 0,
      compression_method = opts.compression_method or z.Z_DEFLATED,
      mtime = opts.mtime or time.time(),
      crc32 = opts.crc32 or 0,
      compressed_size = opts.compressed_size or 0,
      uncompressed_size = opts.uncompressed_size or 0,
      disk_number_start = 0,
      internal_attributes = 0,
      external_attributes = 0,
      local_header_offset = opts.local_header_offset or 0
   }
   return self
end

function ZipEntry:write_central_header(f)
   local s = stream(f)
   s:write_le(4, CENTRAL_FILE_HEADER_SIGNATURE)
   s:write_le(2, self.made_by_version)
   s:write_le(2, self.extract_version)
   s:write_le(2, self.bit_flags)
   s:write_le(2, self.compression_method)
   local tm = time.gmtime(self.mtime)
   s:write_le(2, to_msdos_time(tm))
   s:write_le(2, to_msdos_date(tm))
   s:write_le(4, self.crc32)
   s:write_le(4, self.compressed_size)
   s:write_le(4, self.uncompressed_size)
   s:write_le(2, #self.file_name)
   s:write_le(2, self.extra_field and #self.extra_field or 0)
   s:write_le(2, self.file_comment and #self.file_comment or 0)
   s:write_le(2, self.disk_number_start)
   s:write_le(2, self.internal_attributes)
   s:write_le(4, self.external_attributes)
   s:write_le(4, self.local_header_offset)
   s:write(self.file_name)
   if self.extra_field then
      s:write(self.extra_field)
   end
   if self.file_comment then
      s:write(self.file_comment)
   end
end

function ZipEntry:write_local_header(f)
   local s = stream(f)
   s:write_le(4, LOCAL_FILE_HEADER_SIGNATURE)
   s:write_le(2, self.extract_version)
   s:write_le(2, self.bit_flags)
   s:write_le(2, self.compression_method)
   local tm = time.gmtime(self.mtime)
   s:write_le(2, to_msdos_time(tm))
   s:write_le(2, to_msdos_date(tm))
   s:write_le(4, self.crc32)
   s:write_le(4, self.compressed_size)
   s:write_le(4, self.uncompressed_size)
   s:write_le(2, #self.file_name)
   s:write_le(2, self.extra_field and #self.extra_field or 0)
   s:write(self.file_name)
   if self.extra_field then
      s:write(self.extra_field)
   end
end

local function read_central_header(f)
   local s = stream.with_size(CENTRAL_FILE_HEADER_SIZE, f)
   local signature = s:read_le(4)
   assert(signature == CENTRAL_FILE_HEADER_SIGNATURE)
   local opts = {}
   opts.made_by_version = s:read_le(2)
   opts.extract_version = s:read_le(2)
   opts.bit_flags = s:read_le(2)
   opts.compression_method = s:read_le(2)
   local mtime = s:read_le(2)
   local mdate = s:read_le(2)
   local tm = from_msdos_date_and_time(mdate, mtime)
   opts.mtime = tm:timegm()
   opts.crc32 = s:read_le(4)
   opts.compressed_size = s:read_le(4)
   opts.uncompressed_size = s:read_le(4)
   local file_name_length = s:read_le(2)
   local extra_field_length = s:read_le(2)
   local file_comment_length = s:read_le(2)
   opts.disk_number_start = s:read_le(2)
   opts.internal_attributes = s:read_le(2)
   opts.external_attributes = s:read_le(4)
   opts.local_header_offset = s:read_le(4)

   s = stream.with_size(file_name_length + extra_field_length + file_comment_length, f)
   opts.file_name = tostring(s:read(file_name_length))
   if extra_field_length > 0 then
      opts.extra_field = s:read(extra_field_length)
   end
   if file_comment_length > 0 then
      opts.file_comment = tostring(s:read(file_comment_length))
   end

   return ZipEntry(opts)
end

local function read_local_header(f)
   local s = stream.with_size(LOCAL_FILE_HEADER_SIZE, f)
   local signature = s:read_le(4)
   assert(signature == LOCAL_FILE_HEADER_SIGNATURE)
   local opts = {}
   opts.extract_version = s:read_le(2)
   opts.bit_flags = s:read_le(2)
   opts.compression_method = s:read_le(2)
   local mtime = s:read_le(2)
   local mdate = s:read_le(2)
   local tm = from_msdos_date_and_time(mdate, mtime)
   opts.mtime = tm:timegm()
   opts.crc32 = s:read_le(4)
   opts.compressed_size = s:read_le(4)
   opts.uncompressed_size = s:read_le(4)
   local file_name_length = s:read_le(2)
   local extra_field_length = s:read_le(2)

   s = stream.with_size(file_name_length + extra_field_length, f)
   opts.file_name = tostring(s:read(file_name_length))
   if extra_field_length > 0 then
      opts.extra_field = s:read(extra_field_length)
   end

   return ZipEntry(opts)
end

local function read_entries(f, eocd)
   assert(eocd.disk_number == 0)
   assert(eocd.disk_number_of_eocd == 0)
   assert(eocd.num_entries_disk == eocd.num_entries_total)
   f:seek(eocd.central_directory_offset)
   local entries = {}
   for i=1,eocd.num_entries_total do
      local entry = read_central_header(f)
      table.insert(entries, entry)
   end
   return entries
end

local ZipFile = util.Class()

function ZipFile:new(path)
   local self = {
      path = path,
      entries = {},
      updated = false,
   }
   if fs.exists(path) then
      self.file = fs.open(path, bit.bor(ffi.C.O_RDWR))
   else
      self.file = fs.open(path, bit.bor(ffi.C.O_CREAT, ffi.C.O_RDWR))
   end
   self.eocd = read_eocd(self.file)
   if self.eocd then
      local entries = read_entries(self.file, self.eocd)
      for _,entry in ipairs(entries) do
         entries[entry.file_name] = entry
      end
      self.entries = entries
      -- move file pointer to the start of the central directory
      --
      -- before new files are added to the ZIP, the file will be
      -- truncated at the current position
      self.file:seek(self.eocd.central_directory_offset)
   else
      -- append new files to the end
      self.file:seek_end()
   end
   return self
end

function ZipFile:add(file_name, streamable, options)
   options = options or {}

   local crc32 = M.crc32
   local input = stream(streamable)

   local entry = ZipEntry {
      file_name = file_name,
      extra_field = options.extra_field,
      file_comment = options.file_comment,
      mtime = options.mtime,
   }

   input = stream.tap(input, function(ptr, len)
      entry.uncompressed_size = entry.uncompressed_size + len
      entry.crc32 = crc32(entry.crc32, ptr, len)
   end)
   input = M.deflate(input)
   input = stream.tap(input, function(ptr, len)
      entry.compressed_size = entry.compressed_size + len
   end)

   -- the file pointer is either at the end of file or at the start of
   -- the central directory (when calling add() for the first time on
   -- an existing archive)
   local header_offset = self.file:pos()
   entry.local_header_offset = header_offset
   self.file:truncate()
   local output = stream(self.file)
   entry:write_local_header(output)
   stream.copy(input, output)
   input:close()

   local next_offset = self.file:pos()
   self.file:seek(header_offset)
   -- stream writes are unbuffered so we don't have to worry about
   -- data left in output buffers
   entry:write_local_header(output)
   self.file:seek(next_offset)

   local old_entry_index
   for i,existing_entry in ipairs(self.entries) do
      if existing_entry.file_name == file_name then
         old_entry_index = i
         break
      end
   end
   if old_entry_index then
      table.remove(self.entries, old_entry_index)
   end
   table.insert(self.entries, entry)
   self.entries[file_name] = entry

   self.updated = true
end

function ZipFile:exists(file_name)
   return self.entries[file_name] ~= nil
end

function ZipFile:get_entry(file_name)
   local entry = self.entries[file_name]
   if not entry then
      ef("No such file: %s", file_name)
   end
   return entry
end

function ZipFile:stream(file_name)
   local entry = self:get_entry(file_name)
   self.file:seek(entry.local_header_offset)
   local header = read_local_header(self.file)
   return M.inflate(
      stream.with_size(header.compressed_size,
         -- prevent inflate from closing the zip file
         stream.no_close(self.file)))
end

function ZipFile:readfile(file_name)
   local s = self:stream(file_name)
   local data = s:read(0)
   s:close()
   return data
end

function ZipFile:close()
   if self.updated then
      -- file pointer is after last appended file
      local cd_start = self.file:pos()
      for _,entry in ipairs(self.entries) do
         entry:write_central_header(self.file)
      end
      local cd_end = self.file:pos()
      local cd_size = cd_end - cd_start
      local eocd = EOCD {
         num_entries_total = #self.entries,
         central_directory_size = cd_size,
         central_directory_offset = cd_start
      }
      eocd:write(self.file)
   end
   if self.file then
      self.file:close()
      self.file = nil
   end
end

function M.open(path)
   return ZipFile(path)
end

function M.crc32(crc, ptr, len)
   if ptr then
      return z.crc32(crc, ptr, len)
   else
      return z.crc32(0, nil, 0)
   end
end

return M
