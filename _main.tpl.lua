-- when this template is instantiated, the following local variables
-- are injected at the top:
--
-- ZZ_MAIN_PACKAGE:
--   FQPN (fully qualified package name) of the executing package
--   e.g. github.com/cellux/zz_examples
--
-- ZZ_CORE_PACKAGE:
--   FQPN of the ZZ core package (github.com/cellux/zz)
--
-- ZZ_MODNAME_MAP:
--   a map which can be used to resolve fully qualified module names
--   (`FQPN/module`) to their lj_requireable mangled names

-- save the original require function
local lj_require = _G.require

local function zz_require(modname)
   return lj_require(ZZ_MODNAME_MAP[modname] or modname)
end

local function reverse(t)
   local rv = {}
   for i=#t,1,-1 do
      table.insert(rv, t[i])
   end
   return rv
end

local function setup_require(fqpn, seen)
   -- create and return a require function for package `fqpn` which
   -- looks up modules in the package's declared dependency order
   --
   -- the new require function is also added to the package descriptor
   -- of `fqpn` (pd.require)
   --
   -- while a module of `fqpn` is loaded, it uses the require function
   -- of `fqpn`. this ensures that require() calls made by the module
   -- are resolved using the dependency order of its own package.
   if seen[fqpn] then return end
   seen[fqpn] = true
   -- load package descriptor
   local pd = zz_require(fqpn..'/package')
   local loaders = {}
   pd.imports = pd.imports or {}
   local imports_seen = {}
   local function process_import(fqpn)
      if not imports_seen[fqpn] then
         setup_require(fqpn, seen) -- generates dd.require()
         local dd = zz_require(fqpn..'/package') -- loaded from cache
         -- modules exported by imported packages should be
         -- requireable by their short name
         dd.exports = dd.exports or {}
         for _,m in ipairs(dd.exports) do
            loaders[m] = dd.require            -- short
            loaders[fqpn..'/'..m] = dd.require -- fully qualified
         end
         imports_seen[fqpn] = true
      end
   end
   -- the order of packages in pd.imports matters: if packages P1 and
   -- P2 both define module M but P2 comes *before* P1 in the import
   -- list, require(M) will find the P2 version
   --
   -- a specific module can pulled in by requiring the fully
   -- qualified module name e.g. "github.com/cellux/zz/util"
   for _,fqpn in ipairs(reverse(pd.imports)) do
      process_import(fqpn)
   end
   -- import the ZZ core library last: this ensures that none of the
   -- imports can override core modules like `sched`, `fs`, etc.
   process_import(ZZ_CORE_PACKAGE)
   -- create package-specific require function
   pd.require = function(m)
      return (loaders[m] or lj_require)(m)
   end
   -- each package gets its own global environment which overrides
   -- require() with the package-specific version
   local package_env = setmetatable({ require = pd.require }, { __index = _G })
   pd.exports = pd.exports or {}
   local function process_export(m)
      local mangled = ZZ_MODNAME_MAP[fqpn..'/'..m]
      local cached = nil
      local m_loader = function()
         if not cached then
            -- in LuaJIT, the loader for linked bytecode is defined in
            -- lib_package.c:lj_cf_package_loader_preload() which is
            -- the first element of the package.loaders array
            --
            -- if (when?) package.loaders changes, this will blow up
            local preload = package.loaders[1]
            local chunk = preload(mangled)
            -- ensure that require() calls inside the module use the
            -- containing package's require function
            setfenv(chunk, package_env)
            cached = chunk()
         end
         return cached
      end
      -- if package P exports module M, require(M) inside P shall
      -- return the local M even if a dependency (or core) exports M
      loaders[m] = m_loader
      loaders[fqpn..'/'..m] = m_loader
   end
   for _,m in ipairs(pd.exports) do
      process_export(m)
   end
   process_export("package")
   return pd.require
end

-- ZZ_MAIN_PACKAGE is injected by the build system
_G.require = setup_require(ZZ_MAIN_PACKAGE, {})

require('globals')

local function sched_main(M)
   if type(M) == 'table' and type(M.main) == 'function' then
      local sched = require('sched')
      local signal = require('signal')
      sched(M.main)
      sched()
   end
end

local function run_module(mangled_module_name)
   -- if the module has no main function,
   -- requiring it is the same as running it
   --
   -- if it has a main function, sched_main() will invoke it
   sched_main(lj_require(mangled_module_name))
end

local function run_script(path)
   local chunk, err = loadfile(path)
   if type(chunk) ~= "function" then
      print(err)
   else
      sched_main(chunk())
   end
end

local function run_tests(paths)
   local fs = require('fs')
   local function strip(test_path)
      local basename = fs.basename(test_path)
      local testname = basename:sub(1,-5) -- strip ".lua" extension
      return testname
   end
   for _,path in ipairs(paths) do
      local testname = strip(path)
      local chunk, err = loadfile(path)
      if type(chunk) ~= "function" then
         pf(testname..': COMPILE ERROR')
         print(err)
      else
         local ok, err = pcall(chunk)
         if not ok then
            pf(testname..': LOAD ERROR')
            print(err)
         end
      end
   end
   -- the *_test.lua files we loaded above populated the root_suite
   -- with tests
   local root_suite = require('testing')
   root_suite:run_tests()
end

-- build system will inject bootstrap code after this line
