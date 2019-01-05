local testing = require('testing')('re')
local re = require('re')

testing("match", function()
   local m = re.match("f(.)o", "barfoobar")
   assert(m)
   assert(m.stringcount==2)
   assert(m[0]=="foo")
   assert(m[1]=="o")
   assert(m[2]==nil)
   m = re.match("f(.)o", "barfoebar")
   assert(m==nil)

   m = re.match("\\s+$", "joo\n\nabc", 2)
   assert(m==nil)
   m = re.match("\\s+$", "joo\n\nabc", 3)
   assert(m==nil)
   m = re.match("\\s+", "joo\n\nabc", 3)
   assert(m[0]=="\n\n")

   assert(re.match("\\s+$", "hello, world!\n", 8))
   assert(not re.match("\\s+$", "hello, world!\n", 8, re.ANCHORED))
end)

testing("MatchObject:group()", function()
   local m = re.match("(\\w+).*?(\\d+)", " Chirac   123Regale")

   -- group(0) corresponds to the entire match
   local match,lo,hi = m:group(0)
   assert(match=="Chirac   123")
   assert(lo==1)
   assert(hi==13)

   -- group(1) corresponds to the first subpattern
   local match,lo,hi = m:group(1)
   assert(match=="Chirac")
   assert(lo==1)
   assert(hi==7)

   -- group(2) corresponds to the second subpattern
   local match,lo,hi = m:group(2)
   assert(match=="123")
   assert(lo==10)
   assert(hi==13)
end)

testing("compile", function()
   local r = re.compile("f(.)o")
   local m = r:match("barfoobar")
   assert(m)
   assert(m.stringcount==2)
   assert(m[0]=="foo")
   assert(m[1]=="o")
   assert(m[2]==nil)
   m = r:match("barfoebar")
   assert(m==nil)
end)

testing("match accepts compiled pattern", function()
   local r = re.compile("f(.)o")
   local m = re.match(r, "barfoobar")
   assert(m[0]=="foo")
   assert(m[1]=="o")
end)

testing("match at beginning", function()
   assert(re.match("^abc", "abcdef"))
   assert(re.match("def", "abcdef"))
   assert(not re.match("^def", "abcdef"))
end)

testing("match at end", function()
   assert(re.match("def$", "abcdef"))
   assert(re.match("abc", "abcdef"))
   assert(not re.match("abc$", "abcdef"))
end)

testing("empty match groups", function()
   local m = re.match("^([a-z]+)?([.:,])?([0-9]+)?$", "abc123")
   assert(m.stringcount==4, sf("m.stringcount=%d", m.stringcount))
   assert(m[0]=="abc123")
   assert(m[1]=="abc")
   assert(m[2]==nil, sf("m[2]=%s", m[2]))
   assert(m[3]=="123")
end)

-- Matcher simpifies regex matching in if-else-else... flows

testing("Matcher", function()
   local m = re.Matcher("abc123")
   assert(m:match("([0-9]+)([a-z]+)")==nil)
   assert(m:match("([a-z]+)([0-9]+)"))
   -- groups can be retrieved by indexing the matcher
   assert(m[0]=="abc123")
   assert(m[1]=="abc")
   assert(m[2]=="123")
end)

testing("is_regex", function()
   assert(not re.is_regex("f(.)o"))
   local r = re.compile("f(.)o")
   assert(re.is_regex(r))
   assert(not re.is_regex({}))
end)

testing("caseless matching", function()
  local subj = "The Neverending Story Begins Here"
  local m = re.match("story", subj)
  assert(m==nil)
  local m = re.match("(?i)story", subj)
  assert(m[0]=="Story")
  local m = re.compile("story", re.CASELESS):match(subj)
  assert(m[0]=="Story")
end)

testing("multiline matching", function()
  local subj = [[int main(int argc, char **argv) {
  printf("Hello, world!\n");
}
/* end of main */]]
  local m = re.compile("..$"):match(subj)
  assert(m[0]=="*/")
  local m = re.compile("(?m)..$"):match(subj)
  assert(m[0]==" {")
  local m = re.compile("..$", re.MULTILINE):match(subj)
  assert(m[0]==" {")
end)

testing("partial matching", function()
  local m = re.match("(?<=abc)123", "xyzabc12")
  assert(m==nil)
  local m, is_partial = re.match("(?<=abc)123", "xyzabc12", 0, re.PARTIAL)
  assert(is_partial)
  assert(m[0]=="abc12")
  local m, is_partial = re.match("(?<=abc)123", "xyzabc123", 0, re.PARTIAL)
  assert(not is_partial)
  assert(m[0]=="123")
end)

testing("matches are returned as Lua strings", function()
  local m = re.match("^-?[0-9]+(\\.[0-9]+)?(e-?[0-9]+)?$", "1.56e5")
  assert(type(m[0])=="string")
  assert(m[0]=="1.56e5")
  assert(type(m[1])=="string")
  assert(m[1]==".56")
  assert(type(m[2])=="string")
  assert(m[2]=="e5")
end)
