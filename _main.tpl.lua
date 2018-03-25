-- at the beginning, we still have LuaJIT's require which doesn't mangle module names
-- thus we have to import the sha1 module by its real (mangled) name
local sha1 = require('zz_51d23c0856aa2da92d0b3f21308af0b55ba313dd')

local function mangle(pkgname, modname)
   return 'zz_'..sha1(pkgname..'/'..modname)
end

local lj_require = _G.require

local function setup_require(pname, seen)
   if seen[pname] then return end
   seen[pname] = true
   local pd = lj_require(mangle(pname, 'package')) -- package descriptor
   local loaders = {}
   pd.imports = pd.imports or {}
   -- ZZ_CORE_PACKAGE is injected by the build system
   table.insert(pd.imports, ZZ_CORE_PACKAGE)
   local imports_seen = {}
   for _,dname in ipairs(pd.imports) do
      if not imports_seen[dname] then
         setup_require(dname, seen) -- generates dd.require()
         local dd = lj_require(mangle(dname, 'package'))
         dd.exports = dd.exports or {}
         for _,m in ipairs(dd.exports) do
            local m_loader = function() return dd.require(m) end
            loaders[m] = m_loader
            loaders[dname..'/'..m] = m_loader
         end
         imports_seen[dname] = true
      end
   end
   pd.exports = pd.exports or {}
   for _,m in ipairs(pd.exports) do
      local m_mangled = mangle(pname, m)
      local m_loader = function() return lj_require(m_mangled) end
      loaders[m] = m_loader
      loaders[pname..'/'..m] = m_loader
   end
   pd.require = function(m)
      return (loaders[m] or lj_require)(m)
   end
   setfenv(pd.require, setmetatable({ require = pd.require }, { __index = _G }))
   return pd.require
end

-- ZZ_PACKAGE is injected by the build system
_G.require = setup_require(ZZ_PACKAGE, {})

require('globals')

local process = require('process')
local sched = require('sched')
local epoll = require('epoll')
sched.poller_factory = epoll.poller_factory

local function require_test(modname)
  local ok, err = pcall(require, modname)
  if ok then
     pf(modname..': OK')
  else
     pf(modname..': FAIL')
     pf(err)
  end
end

-- build system will inject bootstrap code here
