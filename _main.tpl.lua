-- when this template is instantiated, the following global variables
-- are injected at the top:
--
-- ZZ_PACKAGE:
--   FQPN (fully qualified package name) of the main package
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
   -- create and return a require(M) function for package `fqpn` which
   -- looks up module M using the package's declared dependency order:
   --
   -- 1. look for M in the package itself
   --
   -- 2. look for M in the core package
   --
   -- 3. look for M in the package's imports, in the order they are
   --    listed in the package descriptor (`pd.imports`)
   --
   -- the newly created require function is also added to the package
   -- descriptor of `fqpn` (as `pd.require`)
   --
   -- the framework ensures that all modules of package P are loaded
   -- with the require() function of P in their environment. this
   -- guarantees that require() calls made by a module are resolved
   -- using the dependency order of its own package.
   if seen[fqpn] then return end
   seen[fqpn] = true
   -- load package descriptor
   local pd = zz_require(fqpn..'/package')
   -- the `loaders` table maps package names (either short or fully
   -- qualified) to functions which return the corresponding package
   local loaders = {}
   pd.imports = pd.imports or {}
   local imports_seen = {}
   local function process_import(fqpn)
      if not imports_seen[fqpn] then
         -- the following setup_require() call loads the package
         -- descriptor of `fqpn`, annotates/extends it with various
         -- fields (e.g. the package-specific require function) and
         -- places it into the module cache. the next zz_require()
         -- call fetches this annotated version from the cache.
         setup_require(fqpn, seen)
         local dd = zz_require(fqpn..'/package')
         -- modules exported by imported packages should be
         -- requireable by their short and fully qualified names
         for _,m in ipairs(dd.exports) do
            loaders[m] = dd.require            -- short
            loaders[fqpn..'/'..m] = dd.require -- fully qualified
         end
         imports_seen[fqpn] = true
      end
   end
   -- the order of packages in pd.imports matters: if packages P1 and
   -- P2 both define module M but P2 comes *before* P1 in the import
   -- list, require(M) shall find the P2 version
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
      -- non-zz modules are handled by lj_require
      return (loaders[m] or lj_require)(m)
   end
   -- each package gets its own environment which overrides require()
   -- with the package-specific version and sets some global variables
   -- to package-specific values
   local package_env = setmetatable({
      require = pd.require,
      ZZ_PACKAGE = pd.package,
      ZZ_PACKAGE_DESCRIPTOR = pd
   }, { __index = _G })
   pd.exports = pd.exports or {}
   local function process_export(m)
      local mangled = ZZ_MODNAME_MAP[fqpn..'/'..m]
      local cached = nil
      local m_loader = function()
         if not cached then
            -- in LuaJIT, the loader for linked bytecode is defined in
            -- lib_package.c:lj_cf_package_loader_preload()
            --
            --- when I wrote this, lj_cf_package_loader_preload() was
            --- the first element of the package.loaders array - if
            --- (when?) its position changes, this will blow up
            local lj_cf_package_loader_preload = package.loaders[1]
            local chunk = lj_cf_package_loader_preload(mangled)
            -- ensure that require() calls inside the module use the
            -- containing package's require function
            setfenv(chunk, package_env)
            -- execute the module chunk (shall return the module)
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
   -- require('package') inside package `fqpn` shall return the
   -- extended/annotated package descriptor we prepared above
   local package_loader = function() return pd end
   loaders['package'] = package_loader
   loaders[fqpn..'/package'] = package_loader
   return pd.require
end

-- ZZ_PACKAGE is injected by the build system
_G.require = setup_require(ZZ_PACKAGE, {})

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
   sched_main(require(mangled_module_name))
end

local function make_package_env()
   -- load the cached version of the package descriptor
   local pd = require('package')

   assert(type(pd)=="table")
   assert(type(pd.package)=="string")
   assert(type(pd.require)=="function")

   local package_env = setmetatable({
      require = pd.require,
      ZZ_PACKAGE = pd.package,
      ZZ_PACKAGE_DESCRIPTOR = pd
   }, { __index = _G })

   return package_env
end

local function run_script(path)
   local chunk, err = loadfile(path)
   if type(chunk) ~= "function" then
      print(err)
   else
      setfenv(chunk, make_package_env())
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
   local package_env = make_package_env()
   for _,path in ipairs(paths) do
      local testname = strip(path)
      local chunk, err = loadfile(path)
      if type(chunk) ~= "function" then
         pf(testname..': COMPILE ERROR')
         print(err)
      else
         setfenv(chunk, package_env)
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
