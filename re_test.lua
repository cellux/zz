local re = require('re')

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

-- compiled
local r = re.compile("f(.)o")
local m = r:match("barfoobar")
assert(m)
assert(m.stringcount==2)
assert(m[0]=="foo")
assert(m[1]=="o")
assert(m[2]==nil)
m = r:match("barfoebar")
assert(m==nil)

-- match at beginning
assert(re.match("^abc", "abcdef"))
assert(re.match("def", "abcdef"))
assert(not re.match("^def", "abcdef"))

-- match at end
assert(re.match("def$", "abcdef"))
assert(re.match("abc", "abcdef"))
assert(not re.match("abc$", "abcdef"))

-- empty match groups
local m = re.match("^([a-z]+)?([.:,])?([0-9]+)?$", "abc123")
assert(m.stringcount==4, sf("m.stringcount=%d", m.stringcount))
assert(m[0]=="abc123")
assert(m[1]=="abc")
assert(m[2]==nil, sf("m[2]=%s", m[2]))
assert(m[3]=="123")

-- Matcher simpifies regex matching in if-else-else... flows
local m = re.Matcher("abc123")
assert(m:match("([0-9]+)([a-z]+)")==nil)
assert(m:match("([a-z]+)([0-9]+)"))
-- groups can be retrieved by indexing the matcher
assert(m[0]=="abc123")
assert(m[1]=="abc")
assert(m[2]=="123")
