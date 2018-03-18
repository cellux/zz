local ffi = require('ffi')

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
]]

local pcre = ffi.load("pcre")

local M = {}

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
M.NEWLINE_CR      = 0x00100000
M.NEWLINE_LF      = 0x00200000
M.NEWLINE_CRLF    = 0x00300000
M.NEWLINE_ANY     = 0x00400000
M.NEWLINE_ANYCRLF = 0x00500000

local MatchObject_mt = {
   __index = function(self, i)
      if i < 0 or i >= self.stringcount then
         return nil
      else
         local lo = self.ovector[i*2]
         local hi = self.ovector[i*2+1]
         if lo == -1 and hi == -1 then
            return nil
         else
            return self.subject:sub(lo+1, hi)
         end
      end
   end,
}

local function MatchObject(subject, stringcount, ovector)
   local self = {
      subject = subject,
      stringcount = stringcount,
      ovector = ovector,
   }
   return setmetatable(self, MatchObject_mt)
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
   match = function(self, subject, startoffset, options)
      local ovecsize = 3*16
      local ovector = ffi.new("int[?]", ovecsize)
      local rv = pcre.pcre_exec(self.pcre,
                                self.pcre_extra,
                                subject,
                                #subject,
                                startoffset or 0,
                                options or 0,
                                ovector,
                                ovecsize)
      if rv == -1 then
         -- PCRE_ERROR_NOMATCH
         return nil
      elseif rv < 0 then
         ef("pcre_exec() failed (%d)", rv)
      elseif rv == 0 then
         error("pcre_exec() failed: vector overflow")
      else
         return MatchObject(subject, rv, ovector)
      end
   end,
}

pcre_mt.__index = pcre_mt

function M.compile(pattern, options)
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
   function self:at(i)
      return match[i]
   end
   return setmetatable(self, { __index = self.at })
end

return M
