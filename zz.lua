local M = {}

local argparser = require('argparser')
local process = require('process')
local env = require('env')
local fs = require('fs')
local re = require('re')
local inspect = require('inspect')
local util = require('util')
local bcsave = require('jit.bcsave')
local sha1 = require('sha1')

local verbose -- set in main()

local function log(msg, ...)
   if verbose then
      pf(sf(msg, ...))
   end
end

local function die(msg, ...)
   pf("ERROR: %s", sf(msg, ...))
   process.exit(1)
end

local ZZPATH = env['ZZPATH'] or sf("%s/zz", env['HOME'])

local function usage()
   pf [[
Usage: zz <command> [options] [args]

Available commands:

zz checkout [-u] <package> [<ref>]

  1. If $ZZPATH/src/<package> does not exist yet:

     git clone <package> into $ZZPATH/src/<package>

     Otherwise run `git fetch' under $ZZPATH/src/<package>

  2. Run `git checkout <ref>' under $ZZPATH/src/<package>

     <ref> defaults to `master'

  3. If -u has been given:

     Run `git pull` under $ZZPATH/src/<package>

zz build [<package>]

  Parse package descriptor P of the given <package> and build P
  according to the instructions inside the descriptor:

  1. For each native dependency N in P.native:

     a. download N
     b. extract N
     c. patch N (if needed)
     d. compile N
     e. copy the library to $ZZPATH/lib/<package>/libN.a

  2. For each module M in P.modules:

     a. compile M.lua into M.lo
     b. compile M.c into M.o (if it exists)
     c. add M.lo and M.o to $ZZPATH/lib/<package>/libP.a

  3. For each app A in P.apps:

     a. compile A.lua into A.lo
     b. compile A.c into A.o (if A.c exists)
     c. generate and compile _main.lua which:
        i.  requires A
        ii. invokes A.main() if it exists
     d. generate and compile _main.c which:
        i.  initalizes a LuaJIT VM
        ii. requires the _main module
     e. link _main.lo and _main.o with:
        i.   A.lo (and A.o if it exists)
        ii.  the library set of P
        iii. the library sets of all packages listed in P.depends
     f. save the resulting executable to $ZZPATH/bin/<package>/A

  The library set of package P consists of:

     a. $ZZPATH/lib/<package>/libP.a
     b. all native dependencies listed in P.native

  Without a <package> argument, attempt to determine which package
  contains the current directory (by looking for the package
  descriptor) and build that.

]]
   process.exit(0)
end

local function find_package_descriptor()
   local pd_path
   local found = false
   local cwd = process.getcwd()
   while not found do
      pd_path = fs.join(cwd, 'package.lua')
      if fs.exists(pd_path) then
         found = true
      elseif cwd == '/' then
         break
      else
         cwd = fs.dirname(cwd)
      end
   end
   return found and pd_path or nil
end

local function target_names(t)
   -- each pair in t is either number => string or string => function
   --
   -- return a list of (name, value) tuples where name is the string
   -- part in each pair and value is the associated function (if any)
   local index = nil
   local function iter()
      local k,v = next(t, index)
      if k == nil then
         return nil
      end
      index = k
      if type(k) == "number" then
         return v, nil
      elseif type(k) == "string" then
         return k, v
      else
         ef("invalid table key")
      end
   end
   return iter
end

local function PackageDescriptor(package_name)
   local pd, pd_path
   if not package_name or package_name == '.' then
      pd_path = find_package_descriptor()
   elseif type(package_name) == "string" then
      pd_path = fs.join(ZZPATH, 'src', package_name, 'package.lua')
   end
   if fs.exists(pd_path) then
      pd = loadfile(pd_path)()
   end
   if not pd then
      if package_name then
         die("cannot find package: %s", package_name)
      else
         die("no package")
      end
   end
   if not pd.package then
      die("missing package field in package descriptor: %s", pd_path)
   end
   -- set defaults
   pd.libname = pd.libname or fs.basename(pd.package)
   pd.depends = pd.depends or {}
   pd.native = pd.native or {}
   pd.modules = pd.modules or {}
   pd.module_deps = pd.module_deps or {}
   return pd
end

local Target = util.Class()

local function is_target(x)
   return type(x)=="table" and x.is_target
end

function Target:create(opts)
   -- ensure target.depends is a list of targets
   if not opts.depends then
      opts.depends = {}
   elseif is_target(opts.depends) then
      opts.depends = { opts.depends }
   end
   if opts.dirname and opts.basename then
      opts.path = fs.join(opts.dirname, opts.basename)
   end
   opts.is_target = true
   return opts
end

function Target:subtargets()
   -- a target may contain several subtargets
   --
   -- in the default case, there is only a single subtarget: itself
   return { self }
end

function Target:mtime()
   if self.path and fs.exists(self.path) then
      return fs.stat(self.path).mtime
   else
      return -1
   end
end

function Target:make()
   local my_mtime = self:mtime()
   local changed = {} -- list of updated dependencies
   local max_mtime = 0
   for _,t in ipairs(self.depends) do
      assert(is_target(t))
      t:make()
      local mtime = t:mtime()
      if mtime > my_mtime then
         table.insert(changed, t)
      end
      if mtime > max_mtime then
         max_mtime = mtime
      end
   end
   if my_mtime < max_mtime and self.build then
      log("[BUILD] %s", self.basename)
      self:build(changed)
   end
end

local function target_path(x)
   if is_target(x) then
      return x.path
   elseif type(x) == "string" then
      return x
   else
      ef("target_path() not applicable for %s", x)
   end
end

local function target_paths(targets)
   return util.map(target_path, targets)
end

local function touch_target(target)
   if target then
      fs.touch(target_path(target))
   end
end

local function with_cwd(cwd, fn)
   local oldcwd = process.getcwd()
   process.chdir(cwd or '.')
   local ok, err = pcall(fn)
   process.chdir(oldcwd)
   if not ok then
      die(err)
   end
end

function system(args)
   local msg = args
   if type(msg) == "table" then
      msg = table.concat(args, " ")
   end
   log(msg)
   return process.system(args)
end

local BuildContext = util.Class(M)

function BuildContext:create(package_name)
   local pd = PackageDescriptor(package_name)
   local ctx = {
      pd = pd,
      gbindir = fs.join(ZZPATH, "bin"),
      bindir = fs.join(ZZPATH, "bin", pd.package),
      objdir = fs.join(ZZPATH, "obj", pd.package),
      libdir = fs.join(ZZPATH, "lib", pd.package),
      srcdir = fs.join(ZZPATH, "src", pd.package),
   }
   ctx.nativedir = fs.join(ctx.srcdir, "native")
   return ctx
end

function BuildContext:mangle(name)
   return 'zz_'..sha1(sf("%s/%s", self.pd.package, name))
end

local shared_ctx_vars = {}

function BuildContext:set(key, value)
   local package_name = self.pd.package
   if not shared_ctx_vars[package_name] then
      shared_ctx_vars[package_name] = {}
   end
   shared_ctx_vars[package_name][key] = value
end

function BuildContext:get(key, package_name)
   package_name = package_name or self.pd.package
   local package_ctx_vars = shared_ctx_vars[package_name]
   if not package_ctx_vars then
      die("BuildContext:get(%s,%s) failed: unknown package", key, package_name)
   end
   return package_ctx_vars[key]
end

function BuildContext:collect(key, modname)
   local rv = {}
   local collected = {}
   local function collect(key, modname)
      if not collected[modname] then
         local target = self:get(modname)
         assert(is_target(target))
         util.extend(rv, target[key])
         collected[modname] = true
         local module_deps = self.pd.module_deps[modname]
         if module_deps then
            for _,modname in ipairs(module_deps) do
               collect(key, modname)
            end
         end
      end
   end
   collect(key, modname)
   return rv
end

function BuildContext:download(opts)
   with_cwd(opts.cwd, function()
      local status = system {
         "curl",
         "-L",
         "-o", target_path(opts.dst),
         opts.src
      }
      if status ~= 0 then
         die("download failed")
      end
   end)
end

function BuildContext:extract(opts)
   with_cwd(opts.cwd, function()
      local status = system {
         "tar", "xzf", target_path(opts.src)
      }
      if status ~= 0 then
         die("extract failed")
      end
      touch_target(opts.touch)
   end)
end

function BuildContext:system(opts)
   with_cwd(opts.cwd, function()
      local status = system(opts.command)
      if status ~= 0 then
         die("command failed")
      end
      touch_target(opts.touch)
   end)
end

function BuildContext:compile_c(opts)
   with_cwd(opts.cwd, function()
      local args = { "gcc", "-c" }
      util.extend(args, opts.cflags)
      table.insert(args, "-o")
      table.insert(args, target_path(opts.dst))
      table.insert(args, target_path(opts.src))
      local status = system(args)
      if status ~= 0 then
         die("compile_c failed")
      end
   end)
end

function BuildContext:compile_lua(opts)
   bcsave.start("-t", "o",
                "-n", opts.name,
                "-g",
                target_path(opts.src),
                target_path(opts.dst))
end

function BuildContext:ar(opts)
   with_cwd(opts.cwd, function()
      local status = system {
         "ar", "rsc",
         target_path(opts.dst),
         unpack(target_paths(opts.src))
      }
      if status ~= 0 then
         die("ar failed")
      end
   end)
end

function BuildContext:cp(opts)
   with_cwd(opts.cwd, function()
      local status = system {
         "cp",
         target_path(opts.src),
         target_path(opts.dst)
      }
      if status ~= 0 then
         die("copy failed")
      end
   end)
end

function BuildContext.Target(ctx, opts)
   return Target(opts)
end

function BuildContext.LuaModuleTarget(ctx, opts)
   local modname = opts.name
   if not modname then
      ef("LuaModuleTarget: missing name")
   end
   local m_src = ctx:Target {
      dirname = ctx.srcdir,
      basename = sf("%s.lua", modname)
   }
   if not fs.exists(m_src.path) then
      die("missing module: %s", m_src.basename)
   end
   return ctx:Target {
      dirname = ctx.objdir,
      basename = sf("%s.lo", modname),
      depends = m_src,
      build = function(self)
         ctx:compile_lua {
            src = m_src,
            dst = self,
            name = ctx:mangle(modname)
         }
      end
   }
end

function BuildContext.CModuleTarget(ctx, opts)
   local modname = opts.name
   if not modname then
      ef("CModuleTarget: missing name")
   end
   local c_src = ctx:Target {
      dirname = ctx.srcdir,
      basename = sf("%s.c", modname)
   }
   if not fs.exists(c_src.path) then
      -- pure Lua module
      return nil
   end
   local c_obj_depends = { c_src }
   local c_h = ctx:Target {
      dirname = ctx.srcdir,
      basename = sf("%s.h", modname)
   }
   if fs.exists(c_h.path) then
      table.insert(c_obj_depends, c_h)
   end
   return ctx:Target {
      dirname = ctx.objdir,
      basename = sf("%s.o", modname),
      depends = c_obj_depends,
      cflags = { "-iquote", ctx.srcdir },
      build = function(self)
         ctx:compile_c {
            src = c_src,
            dst = self,
            cflags = ctx:collect("cflags", modname)
         }
      end
   }
end

function BuildContext.ModuleTarget(ctx, opts)
   local depends = {}
   local lua_target = ctx:LuaModuleTarget(opts)
   table.insert(depends, lua_target)
   local c_target = ctx:CModuleTarget(opts)
   if c_target then
      table.insert(depends, c_target)
   end
   return ctx:Target {
      depends = depends,
      subtargets = function()
         return depends
      end
   }
end

function BuildContext:native_targets()
   local targets = {}
   for libname, target_factory in target_names(self.pd.native) do
      if type(target_factory) ~= "function" then
         ef("invalid target factory for native library %s: %s", libname, target_factory)
      end
      local target_opts = {
         name = libname
      }
      local libtarget = target_factory(self, target_opts)
      self:set(libname, libtarget)
      util.extend(targets, libtarget:subtargets())
   end
   return targets
end

function BuildContext:module_targets()
   local targets = {}
   for modname, target_factory in target_names(self.pd.modules) do
      if not target_factory then
         target_factory = self.ModuleTarget
      end
      if type(target_factory) ~= "function" then
         ef("invalid target factory for module %s: %s", modname, target_factory)
      end
      local target_opts = {
         name = modname
      }
      local modtarget = target_factory(self, target_opts)
      self:set(modname, modtarget)
      util.extend(targets, modtarget:subtargets())
   end
   return targets
end

function BuildContext:library_target()
   local ctx = self
   local depends = {}
   util.extend(depends, self:native_targets())
   util.extend(depends, self:module_targets())
   return Target {
      dirname = self.libdir,
      basename = sf("lib%s.a", self.pd.libname),
      depends = depends,
      build = function(self, changed)
         ctx:ar {
            dst = self,
            src = changed
         }
      end
   }
end

function BuildContext:build()
   fs.mkpath(self.objdir)
   fs.mkpath(self.libdir)
   process.chdir(self.srcdir)
   local library_target = self:library_target()
   library_target:make()
end

function BuildContext:clean()
   system { "rm", "-rf", self.bindir }
   system { "rm", "-rf", self.objdir }
   system { "rm", "-rf", self.libdir }
end

local function parse_package_name(name)
   if not name or name == '.' then
      local pd_path = find_package_descriptor()
      if pd_path then
         local pd = loadfile(pd_path)()
         name = pd.package
      else
         die("no package")
      end
   end
   local pkgname, pkgurl
   -- user@host:path
   local m = re.match("^(.+)@(.+):(.+?)(\\.git)?$", name)
   if m then
      pkgname = sf("%s/%s", m[2], m[3])
      pkgurl = m[0]
   end
   -- https://host/path
   local m = re.match("^https?://(.+?)/(.+?)(\\.git)?$", name)
   if m then
      pkgname = sf("%s/%s", m[1], m[2])
      pkgurl = m[0]
   end
   -- host/path
   local m = re.match("^(.+?)/(.+)$", name)
   if m then
      pkgname = m[0]
      pkgurl = sf("https://%s", pkgname)
   end
   if pkgname and pkgurl then
      return pkgname, pkgurl
   else
      die("cannot parse package name: %s", name)
   end
end

local function checkout(package_name, git_ref, update)
   local pkgname, pkgurl = parse_package_name(package_name)
   local srcdir = sf("%s/src/%s", ZZPATH, pkgname)
   if not fs.exists(srcdir) then
      fs.mkpath(srcdir)
      process.chdir(srcdir)
      local status = system { "git", "clone", pkgurl, "." }
      if status ~= 0 then
         die("git clone failed")
      end
   else
      process.chdir(srcdir)
      local status = system { "git", "fetch" }
      if status ~= 0 then
         die("git fetch failed")
      end
   end
   local status = process.system { "git", "checkout", git_ref or "master" }
   if status ~= 0 then
      die("git checkout failed")
   end
   if update then
      local status = system { "git", "pull" }
      if status ~= 0 then
         die("git pull failed")
      end
   end
   -- checkout dependencies
   local pd = PackageDescriptor(pkgname)
   for package_name in target_names(pd.depends) do
      checkout(package_name)
   end
end

local handlers = {}

function handlers.checkout(args)
   local ap = argparser()
   ap:add { name = "pkg", type = "string" }
   ap:add { name = "ref", type = "string" }
   ap:add { name = "update", option = "-u|--update" }
   local args = ap:parse(args)
   if args.pkg then
      checkout(args.pkg, args.ref, args.update)
   else
      die("Missing argument: pkg")
   end
end

function handlers.build(args)
   local ap = argparser()
   ap:add { name = "pkg", type = "string" }
   local args = ap:parse(args)
   BuildContext(args.pkg):build()
end

function handlers.clean(args)
   local ap = argparser()
   ap:add { name = "pkg", type = "string" }
   local args = ap:parse(args)
   BuildContext(args.pkg):clean()
end

function M.main()
   local ap = argparser("zz", "zz build tool")
   ap:add { name = "command", type = "string" }
   ap:add { name = "verbose", option = "-v|--verbose" }
   local args, rest_args = ap:parse()
   if not args.command then
      usage()
   end
   verbose = args.verbose
   local handler = handlers[args.command]
   if not handler then
      die("Invalid command: %s", args.command)
   else
      handler(rest_args)
   end
end

return M
