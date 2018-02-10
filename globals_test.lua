-- tests for global definitions

local assert = require('assert')
local fs = require('fs') -- for dup2
local process = require('process')
local ffi = require('ffi')
local sched = require('sched')

-- sf

assert.equals(sf("Hello, %s", "world"), "Hello, world")

-- pf

local pid, sp = process.fork(function(sc)
   ffi.C.dup2(sc.fd, 1)
   pf("Hello, %s\n", "world")
end)
assert.equals(sp:read(13), "Hello, world\n")
sp:close()
process.waitpid(pid)

-- ef

local status, err = pcall(function() ef("Hello, %s", "world") end)
assert.equals(status, false)
assert.type(err, "string")
assert.equals(err, "./globals_test.lua:25: Hello, world")

-- if we throw an error from a coroutine running inside the scheduler,
-- we'd like to get a valid backtrace which correctly shows where the
-- error happened

local function throwit()
   ef("Hello, %s", "world")
end
sched(function() throwit() end)
local status, err = pcall(sched)
assert.equals(status, false)
assert.type(err, "string")
-- we check only the first part of the error
--
-- the second part contains the global (non-coroutine-specific)
-- traceback appended by error()
local expected = [[./globals_test.lua:35: Hello, world
stack traceback:
	./globals_test.lua:35: in function 'throwit'
	./globals_test.lua:37: in function <./globals_test.lua:37>]]
assert.equals(err:sub(1,#expected), expected)
