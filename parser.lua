local re = require("re")

local M = {}

local Parser_mt = {}

function Parser_mt:eof()
   return self.pos == self.len or re.match("\\s+$", self.source, self.pos, re.ANCHORED)
end

function Parser_mt:skip(regex)
   local m = re.match(regex, self.source, self.pos, re.ANCHORED)
   if m then
      self.pos = self.pos + #m[0]
   end
end

function Parser_mt:match(regex)
   self:skip("\\s*")
   self.m = re.match(regex, self.source, self.pos, re.ANCHORED)
   return self.m
end

function Parser_mt:text(index)
   if index then
      return self.m[index]
   else
      return self.m[0]
   end
end

function Parser_mt:eat(regex, what)
   local m = regex and self:match(regex) or self.m
   if m then
      self.pos = self.pos + #m[0]
      return m.stringcount == 1 and m[0] or m
   else
      if what then
         ef("parse error: expected %s matching %s at position %d: %s",
            what, regex, self.pos, re.match(".+\n", self.source, self.pos))
      else
         ef("parse error: expected a match for %s at position %d: %s",
            regex, self.pos, re.match(".+\n", self.source, self.pos))
      end
   end
end

Parser_mt.__index = Parser_mt

local function Parser(source)
   local self = {
      source = source,
      len = #source,
      pos = 0,
   }
   return setmetatable(self, Parser_mt)
end

M.Parser = Parser

local M_mt = {}

function M_mt:__call(...)
   return Parser(...)
end

return setmetatable(M, M_mt)
