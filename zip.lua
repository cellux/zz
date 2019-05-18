local ffi = require('ffi')
local time = require('time') -- for time_t
local mm = require('mm')
local util = require('util')

ffi.cdef [[

/*** zipconf.h ***/

typedef int8_t zip_int8_t;
typedef uint8_t zip_uint8_t;
typedef int16_t zip_int16_t;
typedef uint16_t zip_uint16_t;
typedef int32_t zip_int32_t;
typedef uint32_t zip_uint32_t;
typedef int64_t zip_int64_t;
typedef uint64_t zip_uint64_t;

/* zip.h */

/* flags for zip_open */

enum {
  ZIP_CREATE    = 1,
  ZIP_EXCL      = 2,
  ZIP_CHECKCONS = 4,
  ZIP_TRUNCATE  = 8,
  ZIP_RDONLY    = 16
};

/* flags for zip_name_locate, zip_fopen, zip_stat, ... */

enum {
  ZIP_FL_NOCASE     = 1,    /* ignore case on name lookup */
  ZIP_FL_NODIR      = 2,    /* ignore directory component */
  ZIP_FL_COMPRESSED = 4,    /* read compressed data */
  ZIP_FL_UNCHANGED  = 8,    /* use original data, ignoring changes */
  ZIP_FL_RECOMPRESS = 16,   /* force recompression of data */
  ZIP_FL_ENCRYPTED  = 32,   /* read encrypted data */
  ZIP_FL_ENC_GUESS  = 0,    /* guess string encoding (is default) */
  ZIP_FL_ENC_RAW    = 64,   /* get unmodified string */
  ZIP_FL_ENC_STRICT = 128,  /* follow specification strictly */
  ZIP_FL_LOCAL      = 256,  /* in local header */
  ZIP_FL_CENTRAL    = 512,  /* in central directory */
  ZIP_FL_ENC_UTF_8  = 2048, /* string is UTF-8 encoded */
  ZIP_FL_ENC_CP437  = 4096, /* string is CP437 encoded */
  ZIP_FL_OVERWRITE  = 8192  /* zip_file_add: if file with name exists,
                               overwrite (replace) it */
};

/* compression methods */

enum {
  ZIP_CM_DEFAULT        = -1, /* better of deflate or store */
  ZIP_CM_STORE          = 0,  /* stored (uncompressed) */
  ZIP_CM_SHRINK         = 1,  /* shrunk */
  ZIP_CM_REDUCE_1       = 2,  /* reduced with factor 1 */
  ZIP_CM_REDUCE_2       = 3,  /* reduced with factor 2 */
  ZIP_CM_REDUCE_3       = 4,  /* reduced with factor 3 */
  ZIP_CM_REDUCE_4       = 5,  /* reduced with factor 4 */
  ZIP_CM_IMPLODE        = 6,  /* imploded */
  ZIP_CM_DEFLATE        = 8,  /* deflated */
  ZIP_CM_DEFLATE64      = 9,  /* deflate64 */
  ZIP_CM_PKWARE_IMPLODE = 10, /* PKWARE imploding */
  ZIP_CM_BZIP2          = 12, /* compressed using BZIP2 algorithm */
  ZIP_CM_LZMA           = 14, /* LZMA (EFS) */
  ZIP_CM_TERSE          = 18, /* compressed using IBM TERSE (new) */
  ZIP_CM_LZ77           = 19, /* IBM LZ77 z Architecture (PFS) */
  ZIP_CM_XZ             = 95, /* XZ compressed data */
  ZIP_CM_JPEG           = 96, /* Compressed Jpeg data */
  ZIP_CM_WAVPACK        = 97, /* WavPack compressed data */
  ZIP_CM_PPMD           = 98  /* PPMd version I, Rev 1 */
};

/* error information */

struct zip_error {
  int zip_err; /* libzip error code (ZIP_ER_*) */
  int sys_err; /* copy of errno (E*) or zlib error code */
  char *str;   /* string representation or NULL */
};

/* zip_stat */

enum {
  ZIP_STAT_NAME              = 0x0001,
  ZIP_STAT_INDEX             = 0x0002,
  ZIP_STAT_SIZE              = 0x0004,
  ZIP_STAT_COMP_SIZE         = 0x0008,
  ZIP_STAT_MTIME             = 0x0010,
  ZIP_STAT_CRC               = 0x0020,
  ZIP_STAT_COMP_METHOD       = 0x0040,
  ZIP_STAT_ENCRYPTION_METHOD = 0x0080,
  ZIP_STAT_FLAGS             = 0x0100
};

struct zip_stat {
  zip_uint64_t valid;             /* which fields have valid values */
  const char *name;               /* name of the file */
  zip_uint64_t index;             /* index within archive */
  zip_uint64_t size;              /* size of file (uncompressed) */
  zip_uint64_t comp_size;         /* size of file (compressed) */
  time_t mtime;                   /* modification time */
  zip_uint32_t crc;               /* crc of file data */
  zip_uint16_t comp_method;       /* compression method used */
  zip_uint16_t encryption_method; /* encryption method used */
  zip_uint32_t flags;             /* reserved for future use */
};

typedef struct zip zip_t;
typedef struct zip_error zip_error_t;
typedef struct zip_file zip_file_t;
typedef struct zip_source zip_source_t;
typedef struct zip_stat zip_stat_t;

typedef zip_uint32_t zip_flags_t;

const char *zip_libzip_version(void);
const char *zip_strerror(zip_t *);

zip_source_t *zip_source_file(zip_t *, const char *, zip_uint64_t, zip_int64_t);
zip_source_t *zip_source_buffer(zip_t *, const void *, zip_uint64_t, int);
void zip_source_free(zip_source_t *source);
int zip_source_close(zip_source_t *);

zip_t *zip_open(const char *, int, int *);
zip_t *zip_fdopen(int, int, int *);
zip_int64_t zip_dir_add(zip_t *, const char *, zip_flags_t);
zip_int64_t zip_file_add(zip_t *, const char *, zip_source_t *, zip_flags_t);
int zip_file_replace(zip_t *, zip_uint64_t, zip_source_t *, zip_flags_t);
int zip_delete(zip_t *, zip_uint64_t);
zip_int64_t zip_name_locate(zip_t *, const char *, zip_flags_t);
const char *zip_get_name(zip_t *, zip_uint64_t, zip_flags_t);
zip_int64_t zip_get_num_entries(zip_t *, zip_flags_t);
int zip_stat(zip_t *, const char *, zip_flags_t, zip_stat_t *);
int zip_stat_index(zip_t *, zip_uint64_t, zip_flags_t, zip_stat_t *);
int zip_close(zip_t *);

zip_file_t *zip_fopen(zip_t *, const char *, zip_flags_t);
zip_file_t *zip_fopen_index(zip_t *, zip_uint64_t, zip_flags_t);
zip_int64_t zip_fread(zip_file_t *, void *, zip_uint64_t);
int zip_fclose(zip_file_t *);

typedef void (*zip_progress_callback)(zip_t *, double, void *);
int zip_register_progress_callback_with_state(zip_t *, double, zip_progress_callback, void (*ud_free)(void *), void *ud);

void zip_error_init_with_code(zip_error_t *, int);
const char *zip_error_strerror(zip_error_t *);
void zip_error_fini(zip_error_t *);

]]

local M = {}

function M.version()
   return ffi.string(ffi.C.zip_libzip_version())
end

local stat_mask = {
   name = ffi.C.ZIP_STAT_NAME,
   index = ffi.C.ZIP_STAT_INDEX,
   size = ffi.C.ZIP_STAT_SIZE,
   comp_size = ffi.C.ZIP_STAT_COMP_SIZE,
   mtime = ffi.C.ZIP_STAT_MTIME,
   crc = ffi.C.ZIP_STAT_CRC,
   comp_method = ffi.C.ZIP_STAT_COMP_METHOD,
   encryption_method = ffi.C.ZIP_STAT_ENCRYPTION_METHOD,
   flags = ffi.C.ZIP_STAT_FLAGS,
}

local function ZipStat(st)
   local function get_field(self, k)
      local mask = stat_mask[k]
      if mask and bit.band(st.valid, mask) ~= 0 then
         if k == "name" then
            return ffi.string(st[k])
         else
            return tonumber(st[k])
         end
      end
   end
   return setmetatable({}, { __index = get_field })
end

ffi.cdef [[ struct zz_zip_ZipFile_ct { zip_file_t *file; }; ]]

local ZipFile_mt = {}

function ZipFile_mt:strerror()
   return ffi.string(ffi.C.zip_file_strerror(self.file))
end

function ZipFile_mt:check_error(funcname, rv)
   if rv == -1 then
      util.throwat(3, "zipfile-error", sf("%s: %s", funcname, self:strerror()))
   end
   return rv
end

function ZipFile_mt:fread(buf, nbytes)
   return self:check_error("zip_fread", tonumber(ffi.C.zip_fread(self.file, buf, nbytes)))
end

function ZipFile_mt:fclose()
   if self.file ~= nil then
      ffi.C.zip_fclose(self.file)
      self.file = nil
   end
end

function ZipFile_mt:as_stream()
   local stream = {}
   local zf = self
   local eof = false
   function stream:close()
      return zf:fclose()
   end
   function stream:eof()
      return eof
   end
   function stream:read1(ptr, size)
      local nbytes = zf:fread(ptr, size)
      if nbytes == 0 then
         eof = true
      end
      return nbytes
   end
   function stream:write1(ptr, size)
      ef("not implemented")
   end
   return stream
end

ZipFile_mt.close = ZipFile_mt.fclose
ZipFile_mt.__index = ZipFile_mt

local ZipFile = ffi.metatype("struct zz_zip_ZipFile_ct", ZipFile_mt)

ffi.cdef [[ struct zz_zip_Zip_ct { zip_t *archive; }; ]]

local Zip_mt = {}

function Zip_mt:strerror()
   return ffi.string(ffi.C.zip_strerror(self.archive))
end

function Zip_mt:source_file(fname, start, len)
   return util.check_bad("zip_source_file", nil, ffi.C.zip_source_file(self.archive, fname, start or 0, len or 0))
end

function Zip_mt:source_buffer(data, len)
   return util.check_bad("zip_source_buffer", nil, ffi.C.zip_source_buffer(self.archive, data, len or #data, 0))
end

function Zip_mt:check_error(funcname, rv, source)
   if rv == -1 then
      if source then
         ffi.C.zip_source_free(source)
      end
      util.throwat(3, "zip-error", sf("%s: %s", funcname, self:strerror()))
   end
   return rv
end

function Zip_mt:file_add(name, source, flags)
   return self:check_error("zip_file_add", tonumber(ffi.C.zip_file_add(self.archive, name, source, flags or 0)), source)
end

function Zip_mt:file_replace(index, source, flags)
   return self:check_error("zip_file_replace", tonumber(ffi.C.zip_file_replace(self.archive, index, source, flags or 0)), source)
end

function Zip_mt:delete(index)
   return self:check_error("zip_delete", ffi.C.zip_delete(self.archive, index))
end

local function add_default_name_lookup_flags(flags)
   return bit.bor(flags or 0, ffi.C.ZIP_FL_ENC_RAW)
end

function Zip_mt:name_locate(fname, flags)
   flags = add_default_name_lookup_flags(flags)
   return tonumber(ffi.C.zip_name_locate(self.archive, fname, flags))
end

function Zip_mt:get_name(index, flags)
   flags = add_default_name_lookup_flags(flags)
   local name = ffi.C.zip_get_name(self.archive, index, flags)
   if name == nil then
      util.throw("zip-error", sf("zip_get_name: %s", self:strerror()))
   end
   return ffi.string(name)
end

function Zip_mt:get_num_entries(flags)
   return self:check_error("zip_get_num_entries", tonumber(ffi.C.zip_get_num_entries(self.archive, flags or 0)))
end

function Zip_mt:stat(fname, flags)
   flags = add_default_name_lookup_flags(flags)
   local st = ffi.new("zip_stat_t")
   self:check_error("zip_stat", ffi.C.zip_stat(self.archive, fname, flags, st))
   return ZipStat(st)
end

function Zip_mt:stat_index(index, flags)
   flags = add_default_name_lookup_flags(flags)
   local st = ffi.new("zip_stat_t")
   self:check_error("zip_stat_index", ffi.C.zip_stat_index(self.archive, index, flags, st))
   return ZipStat(st)
end

function Zip_mt:fopen(fname, flags)
   flags = add_default_name_lookup_flags(flags)
   local file = ffi.C.zip_fopen(self.archive, fname, flags)
   if file == nil then
      util.throw("zip-error", sf("zip_fopen: %s", self:strerror()))
   end
   return ZipFile(file)
end

function Zip_mt:fopen_index(index, flags)
   flags = add_default_name_lookup_flags(flags)
   local file = ffi.C.zip_fopen_index(self.archive, index, flags)
   if file == nil then
      util.throw("zip-error", sf("zip_fopen_index: %s", self:strerror()))
   end
   return ZipFile(file)
end

function Zip_mt:close()
   if self.archive ~= nil then
      local rv = ffi.C.zip_close(self.archive)
      if rv < 0 then
         ffi.C.free(self.archive)
      end
      self.archive = nil
      self:check_error("zip_close", rv)
   end
   return rv
end

Zip_mt.__index = Zip_mt

local Zip = ffi.metatype("struct zz_zip_Zip_ct", Zip_mt)

local function strerror(code)
   local e = ffi.new("zip_error_t")
   ffi.C.zip_error_init_with_code(e, code)
   local rv = ffi.string(ffi.C.zip_error_strerror(e))
   ffi.C.zip_error_fini(e)
   return rv
end

function M.open(path, flags)
   local status = ffi.new("int[1]")
   local archive = ffi.C.zip_open(path, flags or 0, status)
   if archive == nil then
      util.throw("zip-error", sf("zip_open: %s", strerror(status[0])))
   end
   return Zip(archive)
end

return setmetatable(M, { __index = ffi.C })
