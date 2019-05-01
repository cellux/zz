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

-- TestContext

local function TestContext()
   local tc = {}
   local _nextid = 0
   function tc:nextid()
      _nextid = _nextid + 1
      return _nextid
   end
   return tc
end

-- Test

local Test = util.Class()

function Test:new(name, testfn, opts)
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

function Test:run(tc, report)
   self.ok, self.err = util.pcall(self.testfn, tc)
   report(self)
end

-- TestSuite

local TestSuite = util.Class()

function TestSuite:new(name)
   return {
      name = name,
      tests = {},
      child_suites = {},
      hooks = {
         before = {},
         before_each = {},
         after_each = {},
         after = {}
      },
      __call = function(self, ...)
         return self:add(...)
      end
   }
end

function TestSuite:add(name, testfn, opts)
   if not testfn then
      -- add child suite
      local ts = TestSuite(name)
      ts.parent = self
      table.insert(self.child_suites, ts)
      return ts
   else
      -- add test
      local t = Test(name, testfn, opts)
      t.parent = self
      table.insert(self.tests, t)
      return t
   end
end

function TestSuite:exclusive(name, testfn)
   return self:add(name, testfn):exclusive()
end

function TestSuite:nosched(name, testfn)
   return self:add(name, testfn):nosched()
end

function TestSuite:add_hook(name, fn)
   local hook_list = self.hooks[name]
   if not hook_list then
      ef("invalid hook name: %s", name)
   end
   table.insert(hook_list, fn)
end

function TestSuite:before(fn)
   self:add_hook('before', fn)
end

function TestSuite:before_each(fn)
   self:add_hook('before_each', fn)
end

function TestSuite:after_each(fn)
   self:add_hook('after_each', fn)
end

function TestSuite:after(fn)
   self:add_hook('after', fn)
end

function TestSuite:run_hooks(name, ...)
   local hook_list = self.hooks[name]
   if not hook_list then
      ef("invalid hook name: %s", name)
   end
   for _,hook in ipairs(hook_list) do
      hook(...)
   end
end

function TestSuite:walk(process, test_filter)
   for _,ts in ipairs(self.child_suites) do
      ts:walk(process, test_filter)
   end
   for _,t in ipairs(self.tests) do
      if test_filter == nil or test_filter(t) then
         process(t)
      end
   end
end

function TestSuite:run(process, test_filter, tc, report)
   -- give each suite its own subcontext which inherits from the parent
   tc = util.chainlast({}, tc)
   self:run_hooks('before', tc)
   for _,ts in ipairs(self.child_suites) do
      ts:run(process, test_filter, tc, report)
   end
   for _,t in ipairs(self.tests) do
      if test_filter == nil or test_filter(t) then
         self:run_hooks('before_each', tc)
         process(t, tc, report)
         self:run_hooks('after_each', tc)
      end
   end
   self:run_hooks('after', tc)
end

function TestSuite:run_nosched_tests(tc, report)
   local function process(t, tc, report)
      t:run(tc, report)
   end
   local function test_filter(t)
      return t:is_nosched()
   end
   self:run(process, test_filter, tc, report)
end

function TestSuite:run_sched_tests(tc, report)
   local sched = require('sched')
   local signal = require('signal')
   local function process(t, tc, report)
      local function run_test()
         t:run(tc, report)
      end
      if t:is_exclusive() then
         sched.exclusive(run_test)
      else
         sched(run_test)
      end
   end
   local function test_filter(t)
      return not t:is_nosched()
   end
   self:run(process, test_filter, tc, report)
   sched()
end

function TestSuite:run_tests(report)
   local fdcount_at_start = fdcount()
   local tc = TestContext()
   self:run_nosched_tests(tc, report)
   self:run_sched_tests(tc, report)
   local fdcount_at_end = fdcount()
   if fdcount_at_start ~= fdcount_at_end then
      pf("detected file descriptor leakage: fdcount at start: %d, fdcount at end: %d", fdcount_at_start, fdcount_at_end)
   end
end

M.TestSuite = TestSuite

-- built-in reporters

local function ConsoleReporter(suite)
   local total = 0
   local function count_test(t)
      total = total + 1
   end
   suite:walk(count_test)
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
         suite:walk(report_failure, function(t) return not t.ok end)
      end
   end
   return report
end

--

local root_suite = TestSuite()

function M.run_tests(suite, report)
   suite = suite or root_suite
   report = report or ConsoleReporter(suite)
   suite:run_tests(report)
end

local M_mt = {}

function M_mt:__call(...)
   return root_suite:add(...)
end

return setmetatable(M, M_mt)
