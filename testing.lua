local util = require('util')

local M = {}

local function fdcount()
   local fs = require('fs')
   local count = 0
   local dir = "/proc/self/fd"
   for entry in fs.readdir(dir) do
      if fs.is_lnk(fs.join(dir, entry)) then
         count = count + 1
      end
   end
   return count
end

-- Test

local Test = util.Class()

function Test:create(name, testfn, opts)
   return {
      name = name,
      testfn = testfn,
      opts = opts or {},
      ok = nil,
      err = nil,
   }
end

function Test:exclusive()
   self.opts.exclusive = true
   return self
end

function Test:is_exclusive()
   return self.opts.exclusive
end

function Test:nosched()
   self.opts.nosched = true
   return self
end

function Test:is_nosched()
   return self.opts.nosched
end

function Test:run(tc)
   self.ok, self.err = util.pcall(self.testfn, tc)
end

-- TestContext

local TestContext = util.Class()

function TestContext:create()
   return {
      _nextid = 0
   }
end

function TestContext:nextid()
   self._nextid = self._nextid + 1
   return self._nextid
end

-- TestSuite

local TestSuite = util.Class()

function TestSuite:create(name)
   return {
      name = name,
      tests = {},
      suites = {},
      __call = function(self, ...)
         return self:add(...)
      end
   }
end

function TestSuite:add(name, testfn, opts)
   if not testfn then
      local ts = TestSuite(name)
      ts.parent = self
      table.insert(self.suites, ts)
      return ts
   else
      local t = Test(name, testfn, opts)
      t.parent = self
      table.insert(self.tests, t)
      return t
   end
end

function TestSuite:exclusive(name, testfn)
   return self:add(name, testfn, { exclusive = true })
end

function TestSuite:nosched(name, testfn)
   return self:add(name, testfn, { nosched = true })
end

function TestSuite:walk(process, filter)
   for _,ts in ipairs(self.suites) do
      ts:walk(process, filter)
   end
   for _,t in ipairs(self.tests) do
      if filter == nil or filter(t) then
         process(t)
      end
   end
end

function TestSuite:run(tc)
   tc = tc or TestContext()
   local total = 0
   local function count_test(t)
      total = total + 1
   end
   self:walk(count_test)
   local remaining = total
   local passed = 0
   local failed = 0
   local function report(t)
      if t.ok then
         passed = passed + 1
      else
         failed = failed + 1
      end
      remaining = remaining - 1
      io.stderr:write(sf("\r%d/%d tests passed.", passed, total))
      if remaining == 0 then
         io.stderr:write("\n")
         local function report_failure(t)
            local err = t.err
            if util.is_error(err) then
               err = err.traceback
            end
            io.stderr:write(sf("\nwhile testing '%s'\nat %s:%d\n\n%s\n",
                               t.name,
                               t.err.info.short_src,
                               t.err.info.currentline,
                               err))
         end
         self:walk(report_failure, function(t) return not t.ok end)
      end
   end
   local function run_test(t)
      t:run(tc)
      report(t)
   end
   local fdcount_at_start = fdcount()
   self:walk(run_test, function(t) return t:is_nosched() end)
   local sched = require('sched')
   local function sched_test(t)
      if t:is_exclusive() then
         sched.exclusive(run_test, t)
      else
         sched(run_test, t)
      end
   end
   self:walk(sched_test, function(t) return not t:is_nosched() end)
   sched()
   local fdcount_at_end = fdcount()
   if fdcount_at_start ~= fdcount_at_end then
      pf("detected file descriptor leakage: fdcount at start: %d, fdcount at end: %d", fdcount_at_start, fdcount_at_end)
   end
end

M.TestSuite = TestSuite

local root = TestSuite()

function M.run_tests()
   root:run()
end

local M_mt = {}

function M_mt:__call(...)
   return root:add(...)
end

return setmetatable(M, M_mt)
