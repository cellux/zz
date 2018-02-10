local ffi = require('ffi')
local bit = require('bit')
local util = require('util')

local M = {}

ffi.cdef [[

typedef struct _SDL_iconv_t *SDL_iconv_t;

SDL_iconv_t SDL_iconv_open(const char *tocode, const char *fromcode);
size_t SDL_iconv(SDL_iconv_t cd,
                 const char **inbuf, size_t * inbytesleft,
                 char **outbuf, size_t * outbytesleft);
int SDL_iconv_close(SDL_iconv_t cd);

char * SDL_iconv_string(const char *tocode, const char *fromcode,
                        const char *inbuf, size_t inbytesleft);

void SDL_free(void *mem);

]]

local sdl = ffi.load("SDL2")

function M.utf8_strlen(utf8_string)
   local len = 0
   for i=1,#utf8_string do
      local b = utf8_string:byte(i)
      if bit.band(b,0xc0) ~= 0x80 then
         len = len + 1
      end
   end
   return len
end

function M.utf8_codepoints(utf8_string)
   local tocode = ffi.abi("le") and "UTF-32LE" or "UTF-32BE"
   local fromcode = "UTF-8"
   local iconv = util.check_bad("SDL_iconv_open", nil,
                                sdl.SDL_iconv_open(tocode, fromcode))
   local inbuf = ffi.new("const char*[1]",
                         ffi.cast("const char*", utf8_string))
   local inbytesleft = ffi.new("size_t[1]", #utf8_string)
   local len = M.utf8_strlen(utf8_string)
   local utf32_buf = ffi.new("uint32_t[?]", len)
   local outbuf = ffi.new("char*[1]", ffi.cast("char*", utf32_buf))
   local outbytesleft = ffi.new("size_t[1]", ffi.sizeof(utf32_buf))
   local rv = sdl.SDL_iconv(iconv,
                            inbuf, inbytesleft,
                            outbuf, outbytesleft)
   util.check_ok("SDL_iconv_close", 0, sdl.SDL_iconv_close(iconv))
   if rv == -1 then
      ef("iconv failed")
   end
   local code_points = {}
   for i=1,len do
      table.insert(code_points, utf32_buf[i-1])
   end
   return code_points
end

return M
