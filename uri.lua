local ffi = require('ffi')
local bit = require('bit')
local re = require('re')

local M = {}

local hex_digits = '0123456789ABCDEF'

local function PctEncoder(reserved_set)
   -- encode characters if:
   --
   -- a) their byte value < 0x20 or
   -- a) their byte value >= 0x7F or
   -- b) they are included in reserved_set (a string)
   --
   local reserved = ffi.new("uint8_t[256]") -- LuaJIT zero-initializes
   reserved[0x25] = 1 -- % should be always encoded
   for i=0,0x1f do
      reserved[i] = 1
   end
   for i=0x7f,0xff do
      reserved[i] = 1
   end
   if reserved_set then
      for i=1,#reserved_set do
         reserved[reserved_set:byte(i)] = 1
      end
   end
   return function(str)
      local buf = ffi.new("uint8_t[?]", #str*3)
      local dst = 0
      for i=1,#str do
         local b = str:byte(i)
         if reserved[b]==1 then
            buf[dst] = 0x25 -- %
            buf[dst+1] = hex_digits:byte(bit.rshift(b,4)+1)
            buf[dst+2] = hex_digits:byte(bit.band(b,0x0f)+1)
            dst = dst + 3
         else
            buf[dst] = b
            dst = dst + 1
         end
      end
      return ffi.string(buf, dst)
   end
end

function decode_hex_digit(ascii_code)
   local rv = ascii_code-0x30
   if rv >= 10 then
      rv = rv - (0x41-0x3a)
   end
   if rv >= 16 then
      rv = rv - (0x61-0x41)
   end
   return rv
end

function pct_decode(pct)
   --pct must match %[0-9a-fA-F][0-9a-fA-F]
   local hi = decode_hex_digit(pct:byte(2))
   local lo = decode_hex_digit(pct:byte(3))
   return string.char(hi*16+lo)
end

function decode(str)
   local rv, match_count = str:gsub("%%[0-9a-fA-F][0-9a-fA-F]", pct_decode)
   return rv
end

local gen_delims = ":/?#[]@" -- from the RFC
local sub_delims = "!$&'()*+,;="

local URI_mt = {}

-- PctEncoders take some memory so we create them lazily as needed

local function make_encoder(field_name, reserved_set)
   local encode = nil
   return function(self)
      if not encode then
         encode = PctEncoder(reserved_set)
      end
      return encode(self[field_name])
   end
end

URI_mt.encode_user = make_encoder("user", " :/?#@")
URI_mt.encode_password = make_encoder("password", " :/?#@")
URI_mt.encode_host = make_encoder("host")
URI_mt.encode_path = make_encoder("path", " !\"#$%&'()?`|")
URI_mt.encode_query = make_encoder("query", " #")
URI_mt.encode_fragment = make_encoder("fragment")

function URI_mt:encode()
   local parts = {}
   -- scheme does not allow percent-encoding
   table.insert(parts, sf("%s:", self.scheme))
   if self.user or self.host then
      table.insert(parts, '//')
   end
   if self.user then
      table.insert(parts, self:encode_user())
      if self.password then
         table.insert(parts, sf(":%s", self:encode_password()))
      end
      table.insert(parts, '@')
   end
   if self.host then
      table.insert(parts, self:encode_host())
   end
   if self.port then
      table.insert(parts, sf(":%d", tonumber(self.port)))
   end
   if self.path then
      table.insert(parts, self:encode_path())
   end
   if self.query then
      table.insert(parts, sf("?%s", self:encode_query()))
   end
   if self.fragment then
      table.insert(parts, sf("#%s", self:encode_fragment()))
   end
   return table.concat(parts)
end

function URI_mt:__tostring()
   return self:encode()
end

URI_mt.__index = URI_mt

local function validate_scheme(scheme)
   local canonical_scheme = string.lower(scheme)
   if not re.match("^[a-z][a-z0-9+.-]*$", canonical_scheme) then
      ef("invalid scheme: %s", scheme)
   end
   return canonical_scheme
end

local function validate_host(host)
   local canonical_host = string.lower(host)
   -- we should probably check something here but the RFC seems
   -- ambiguous about what characters are allowed in the host field
   -- (it's not just DNS domain names)
   return canonical_host
end

local function validate_port(port)
   if not re.match("^[0-9]+$", port) then
      ef("invalid port: %s", port)
   end
   return port
end

function M.build(uri)
   assert(type(uri)=="table")
   if not uri.scheme then
      ef("missing scheme")
   else
      uri.scheme = validate_scheme(uri.scheme)
   end
   if not uri.path then
      -- Section 3: "The scheme and path components are required,
      -- though the path may be empty (no characters)."
      uri.path = ""
   end
   if uri.host then
      if uri.path ~= "" and uri.path:sub(1,1) ~= "/" then
         ef("If authority is present, path must be empty or begin with a slash character.")
      end
      uri.host = validate_host(uri.host)
      if uri.port then
         uri.port = validate_port(uri.port)
      end
   else
      if uri.path:sub(1,2) == "//" then
         ef("In the absence of authority, path cannot begin with two slash characters.")
      end
      if uri.port then
         ef("Port without host")
      end
      if uri.user then
         ef("User without host")
      elseif uri.password then
         ef("Password without user and host")
      end
   end
   return setmetatable(uri, URI_mt)
end

function M.decode(uri)
   assert(type(uri)=="string")
   local m = re.match("^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?$", uri)
   local rv = nil
   if m then
      rv = {}
      if m[2] then
         rv.scheme = validate_scheme(m[2])
      end
      if m[4] then
         local authority = m[4]
         local ma = re.match("^(([^:]+)(:([^:]+))?@)?(.+?)(:([0-9]+))?$", authority)
         if ma then
            rv.user = ma[2] and decode(ma[2])
            rv.password = ma[4] and decode(ma[4])
            rv.host = ma[5] and validate_host(decode(ma[5]))
            rv.port = ma[7] and validate_port(decode(ma[7]))
         end
      end
      if m[5] then
         rv.path = decode(m[5])
      end
      if m[7] then
         rv.query = decode(m[7])
      end
      if m[9] then
         rv.fragment = decode(m[9])
      end
   end
   return rv and setmetatable(rv, URI_mt)
end

return setmetatable(M, {
   __call = function(self, uri)
      if not uri or uri=="" then
         return nil
      end
      if type(uri)=="string" then
         return M.decode(uri)
      elseif type(uri)=="table" then
         return M.build(uri)
      else
         ef("cannot construct an URI from value: %s", uri)
      end
   end
})
