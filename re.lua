local ffi = require('ffi')
local buffer = require('buffer')

ffi.cdef [[
struct pcre;
struct pcre_extra;

void *(*pcre_malloc)(size_t);
void  (*pcre_free)(void *);

int  pcre_config(int, void *);
struct pcre *pcre_compile(const char *, int,
                          const char **, int *,
                          const unsigned char *);
int  pcre_exec(const struct pcre *,
               const struct pcre_extra *,
               const char*, int, int, int, int *, int);
struct pcre_extra *pcre_study(const struct pcre *,
                              int, const char **);
void pcre_free_study(struct pcre_extra *);
int pcre_fullinfo(const struct pcre *code,
                  const struct pcre_extra *extra,
                  int what, void *where);

enum {
  PCRE_INFO_OPTIONS             = 0,
  PCRE_INFO_SIZE                = 1,
  PCRE_INFO_CAPTURECOUNT        = 2,
  PCRE_INFO_BACKREFMAX          = 3,
  PCRE_INFO_FIRSTBYTE           = 4,
  PCRE_INFO_FIRSTCHAR           = 4,  /* For backwards compatibility */
  PCRE_INFO_FIRSTTABLE          = 5,
  PCRE_INFO_LASTLITERAL         = 6,
  PCRE_INFO_NAMEENTRYSIZE       = 7,
  PCRE_INFO_NAMECOUNT           = 8,
  PCRE_INFO_NAMETABLE           = 9,
  PCRE_INFO_STUDYSIZE           = 10,
  PCRE_INFO_DEFAULT_TABLES      = 11,
  PCRE_INFO_OKPARTIAL           = 12,
  PCRE_INFO_JCHANGED            = 13,
  PCRE_INFO_HASCRORLF           = 14,
  PCRE_INFO_MINLENGTH           = 15,
  PCRE_INFO_JIT                 = 16,
  PCRE_INFO_JITSIZE             = 17,
  PCRE_INFO_MAXLOOKBEHIND       = 18,
  PCRE_INFO_FIRSTCHARACTER      = 19,
  PCRE_INFO_FIRSTCHARACTERFLAGS = 20,
  PCRE_INFO_REQUIREDCHAR        = 21,
  PCRE_INFO_REQUIREDCHARFLAGS   = 22,
  PCRE_INFO_MATCHLIMIT          = 23,
  PCRE_INFO_RECURSIONLIMIT      = 24,
  PCRE_INFO_MATCH_EMPTY         = 25
};

]]

local pcre = ffi.load("pcre")

local M = {}

local OVECTOR_SLOTS = 16

M.CASELESS        = 0x00000001
M.MULTILINE       = 0x00000002
M.DOTALL          = 0x00000004
M.EXTENDED        = 0x00000008
M.ANCHORED        = 0x00000010
M.DOLLAR_ENDONLY  = 0x00000020
M.EXTRA           = 0x00000040
M.NOTBOL          = 0x00000080
M.NOTEOL          = 0x00000100
M.UNGREEDY        = 0x00000200
M.NOTEMPTY        = 0x00000400
M.UTF8            = 0x00000800
M.PARTIAL         = 0x00008000
M.NEWLINE_CR      = 0x00100000
M.NEWLINE_LF      = 0x00200000
M.NEWLINE_CRLF    = 0x00300000
M.NEWLINE_ANY     = 0x00400000
M.NEWLINE_ANYCRLF = 0x00500000

local function MatchObject(subject, buf, stringcount, ovector)
   local self = {
      subject = subject, -- prevent GC
      buf = buf,
      stringcount = stringcount,
      ovector = ovector,
   }
   function self:group(i)
      if i < 0 or i >= self.stringcount then
         return nil
      else
         local lo = self.ovector[i*2]
         local hi = self.ovector[i*2+1]
         if lo == -1 and hi == -1 then
            return nil
         else
            return ffi.string(self.buf.ptr+lo, hi-lo), lo, hi
         end
      end
   end
   return setmetatable(self, { __index = self.group })
end

local pcre_mt = {
   delete = function(self)
      pcre.pcre_free(self.pcre)
      if self.pcre_extra then
         pcre.pcre_free_study(self.pcre_extra)
      end
   end,
   study = function(self, options)
      local errptr = ffi.new("const char*[1]")
      self.pcre_extra = pcre.pcre_study(self.pcre,
                                        options or 0,
                                        errptr)
      if errptr[0] ~= nil then
         ef("pcre_study() failed: %s", ffi.string(errptr[0]))
      end
   end,
   options = function(self)
      local data = ffi.new("unsigned long[1]")
      local rv = pcre.pcre_fullinfo(self.pcre,
                                    self.pcre_extra,
                                    pcre.PCRE_INFO_OPTIONS,
                                    data)
      if rv ~= 0 then
         ef("pcre_fullinfo() failed")
      end
      return tonumber(data[0])
   end,
   match = function(self, subject, startoffset, options)
      local buf = buffer.wrap(subject)
      local ovecsize = 3 * OVECTOR_SLOTS
      local ovector = ffi.new("int[?]", ovecsize)
      local rv = pcre.pcre_exec(self.pcre,
                                self.pcre_extra,
                                buf.ptr,
                                buf.len,
                                startoffset or 0,
                                options or 0,
                                ovector,
                                ovecsize)
      if rv == -1 then
         -- PCRE_ERROR_NOMATCH
         return nil
      elseif rv == -12 then
         -- PCRE_ERROR_PARTIAL: match info stored in the first 3 slots
         return MatchObject(subject, buf, 3, ovector), true
      elseif rv < 0 then
         ef("pcre_exec() failed (%d)", rv)
      elseif rv == 0 then
         ef("pcre_exec() failed: vector overflow")
      else
         -- rv is the number of slots filled with match info
         return MatchObject(subject, buf, rv, ovector), false
      end
   end,
}

pcre_mt.__index = pcre_mt
pcre_mt.__gc = pcre_mt.delete

local function is_regex(x)
   return type(x) == "table" and getmetatable(x) == pcre_mt
end

M.is_regex = is_regex

function M.compile(pattern, options)
   if is_regex(pattern) then
      assert(options == nil)
      return pattern
   end
   local errptr = ffi.new("const char*[1]")
   local erroffset = ffi.new("int[1]")
   local pcre = pcre.pcre_compile(pattern,
                                  options or 0,
                                  errptr,
                                  erroffset,
                                  nil)
   if not pcre then
      ef("error in regex /%s/ at position %d: %s", pattern, erroffset[0], ffi.string(errptr[0]))
   end
   local self = { pcre = pcre }
   return setmetatable(self, pcre_mt)
end

function M.match(pattern, subject, startoffset, options)
   return M.compile(pattern):match(subject, startoffset, options)
end

function M.Matcher(subject)
   local self = {}
   local match
   function self:match(pattern)
      match = M.compile(pattern):match(subject)
      return match
   end
   function self:group(i)
      return match and match:group(i)
   end
   return setmetatable(self, { __index = self.group })
end

return M
