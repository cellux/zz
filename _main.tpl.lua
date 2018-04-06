-- at the beginning, we still have LuaJIT's require which doesn't mangle module names
-- thus we have to import the sha1 module by its real (mangled) name
local sha1 = require('zz_51d23c0856aa2da92d0b3f21308af0b55ba313dd')

local function mangle(pkgname, modname)
   return 'zz_'..sha1(pkgname..'/'..modname)
end

local lj_require = _G.require

local function reverse(t)
   local rv = {}
   for i=#t,1,-1 do
      table.insert(rv, t[i])
   end
   return rv
end

local function setup_require(pname, seen)
   if seen[pname] then return end
   seen[pname] = true
   -- load package descriptor
   local pd = lj_require(mangle(pname, 'package'))
   local loaders = {}
   pd.imports = pd.imports or {}
   local imports_seen = {}
   local function process_import(dname)
      if not imports_seen[dname] then
         setup_require(dname, seen) -- generates dd.require()
         local dd = lj_require(mangle(dname, 'package'))
         -- modules exported by imported packages should be
         -- requireable by their short name
         dd.exports = dd.exports or {}
         for _,m in ipairs(dd.exports) do
            loaders[m] = dd.require             -- short
            loaders[dname..'/'..m] = dd.require -- qualified
         end
         imports_seen[dname] = true
      end
   end
   -- ZZ_CORE_PACKAGE is injected by the build system
   process_import(ZZ_CORE_PACKAGE)
   -- the order of packages in pd.imports matters: if packages P1 and
   -- P2 both define module M but P2 comes *before* P1 in the import
   -- list, require(M) will find the P2 version
   --
   -- a specific version can pulled in by requiring the fully
   -- qualified module name e.g. "github.com/cellux/zz/util"
   for _,dname in ipairs(reverse(pd.imports)) do
      process_import(dname)
   end
   pd.require = function(m)
      return (loaders[m] or lj_require)(m)
   end
   local pd_env = setmetatable({ require = pd.require }, { __index = _G })
   pd.exports = pd.exports or {}
   local function process_export(m)
      local mangled = mangle(pname, m)
      local loaded = nil
      local m_loader = function()
         if not loaded then
            -- in LuaJIT, the loader for linked bytecode is defined in
            -- lib_package.c:lj_cf_package_loader_preload() which is
            -- the first element of the package.loaders array
            --
            -- if (when?) package.loaders changes, this will blow up
            local preload = package.loaders[1]
            local chunk = preload(mangled)
            setfenv(chunk, pd_env)
            loaded = chunk()
         end
         return loaded
      end
      loaders[m] = m_loader
      loaders[pname..'/'..m] = m_loader
   end
   for _,m in ipairs(pd.exports) do
      process_export(m)
   end
   process_export("package")
   return pd.require
end

-- ZZ_PACKAGE is injected by the build system
_G.require = setup_require(ZZ_PACKAGE, {})

require('globals')

local function sched_main(M)
   if type(M) == 'table' and type(M.main) == 'function' then
      local sched = require('sched')
      sched(M.main)
      sched()
   end
end

local function run_module(modname)
   sched_main(lj_require(modname))
end

local function run_script(path)
   local chunk, err = loadfile(path)
   if type(chunk) ~= "function" then
      print(err)
   else
      sched_main(chunk())
   end
end

local function require_test(modname)
  local ok, err = pcall(require, modname)
  if ok then
     pf(modname..': OK')
  else
     pf(modname..': FAIL')
     print(err)
  end
end

-- build system will inject bootstrap code here
