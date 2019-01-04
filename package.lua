local P = {}

P.package = "github.com/cellux/zz"

local LUAJIT_VER  = "2.1.0-beta3"
local CMP_VER     = "10"
local NANOMSG_VER = "1.1.5"

P.native = {}

P.native.luajit = function(ctx)
   local LUAJIT_TGZ = sf("LuaJIT-%s.tar.gz", LUAJIT_VER)
   local LUAJIT_URL = sf("http://luajit.org/download/%s", LUAJIT_TGZ)
   local LUAJIT_DIR = sf("LuaJIT-%s", LUAJIT_VER)
   local LUAJIT_ROOT = sf("%s/%s", ctx.nativedir, LUAJIT_DIR)
   local LUAJIT_SRC = sf("%s/src", LUAJIT_ROOT)
   local LUAJIT_EMBEDDED_MODULES = { "bcsave" }
   local luajit_tgz = ctx:Target {
      dirname = ctx.nativedir,
      basename = LUAJIT_TGZ,
      build = function(self)
         ctx:download {
            src = LUAJIT_URL,
            dst = self,
         }
      end
   }
   local luajit_extracted = ctx:Target {
      dirname = LUAJIT_ROOT,
      basename = ".extracted",
      depends = luajit_tgz,
      build = function(self)
         ctx:extract {
            cwd = ctx.nativedir,
            src = luajit_tgz
         }
      end
   }
   local luajit_patched = ctx:Target {
      dirname = LUAJIT_ROOT,
      basename = ".patched",
      depends = luajit_extracted,
      build = function(self)
         ctx:system {
            cwd = LUAJIT_SRC,
            command = {
               "sed", "-i", "-r",
               "-e", "s/^(BUILDMODE)=.*/\\1= static/",
               "-e", "s/^(XCFLAGS)=.*/\\1= -DLUAJIT_ENABLE_LUA52COMPAT/",
               "Makefile"
            }
         }
      end
   }
   local libluajit_a = ctx:Target {
      dirname = LUAJIT_SRC,
      basename = "libluajit.a",
      depends = luajit_patched,
      build = function(self)
         ctx:system {
            cwd = LUAJIT_ROOT,
            command = "make clean amalg"
         }
      end
   }
   local jit_module_targets = {}
   for _,m in ipairs(LUAJIT_EMBEDDED_MODULES) do
      local m_lua = ctx:Target {
         dirname = sf("%s/%s", LUAJIT_SRC, "jit"),
         basename = sf("%s.lua", m)
      }
      local m_lo = ctx:Target {
         dirname = sf("%s/%s", ctx.objdir, "jit"),
         basename = sf("%s.lo", m),
         depends = m_lua,
         build = function(self)
            ctx:compile_lua {
               src = m_lua,
               dst = self,
               sym = sf("jit.%s", m)
            }
         end
      }
      table.insert(jit_module_targets, m_lo)
   end
   return ctx:Target {
      dirname = ctx.libdir,
      basename = "libluajit.a",
      depends = { libluajit_a, jit_module_targets },
      cflags = { "-iquote", LUAJIT_SRC },
      build = function(self)
         ctx:cp {
            src = libluajit_a,
            dst = self,
         }
         ctx:ar {
            dst = self,
            src = jit_module_targets
         }
      end
   }
end

P.native.cmp = function(ctx)
   local CMP_TGZ = sf("cmp-%s.tar.gz", CMP_VER)
   local CMP_URL = sf("https://github.com/camgunz/cmp/archive/v%s.tar.gz", CMP_VER)
   local CMP_DIR = sf("cmp-%s", CMP_VER)
   local CMP_ROOT = sf("%s/%s", ctx.nativedir, CMP_DIR)
   local cmp_tgz = ctx:Target {
      dirname = ctx.nativedir,
      basename = CMP_TGZ,
      build = function(self)
         ctx:download {
            src = CMP_URL,
            dst = self,
         }
      end
   }
   local cmp_extracted = ctx:Target {
      dirname = CMP_ROOT,
      basename = ".extracted",
      depends = cmp_tgz,
      build = function(self)
         ctx:extract {
            cwd = ctx.nativedir,
            src = cmp_tgz
         }
      end
   }
   local cmp_o = ctx:Target {
      dirname = CMP_ROOT,
      basename = "cmp.o",
      depends = cmp_extracted,
      build = function(self)
         ctx:compile_c {
            cwd = CMP_ROOT,
            src = "cmp.c",
            dst = self
         }
      end
   }
   return ctx:Target {
      dirname = ctx.libdir,
      basename = "libcmp.a",
      depends = cmp_o,
      cflags = { "-iquote", CMP_ROOT },
      build = function(self)
         ctx:ar {
            dst = self,
            src = { cmp_o }
         }
      end
   }
end

P.native.nanomsg = function(ctx)
   local NANOMSG_TGZ = sf("nanomsg-%s.tar.gz", NANOMSG_VER)
   local NANOMSG_URL = sf("https://github.com/nanomsg/nanomsg/archive/%s.tar.gz", NANOMSG_VER)
   local NANOMSG_DIR = sf("nanomsg-%s", NANOMSG_VER)
   local NANOMSG_ROOT = sf("%s/%s", ctx.nativedir, NANOMSG_DIR)
   local NANOMSG_SRC = sf("%s/src", NANOMSG_ROOT)
   local nanomsg_tgz = ctx:Target {
      dirname = ctx.nativedir,
      basename = NANOMSG_TGZ,
      build = function(self)
         ctx:download {
            src = NANOMSG_URL,
            dst = self,
         }
      end
   }
   local nanomsg_extracted = ctx:Target {
      dirname = NANOMSG_ROOT,
      basename = ".extracted",
      depends = nanomsg_tgz,
      build = function(self)
         ctx:extract {
            cwd = ctx.nativedir,
            src = nanomsg_tgz
         }
      end
   }
   local nanomsg_patched = ctx:Target {
      dirname = NANOMSG_ROOT,
      basename = ".patched",
      depends = nanomsg_extracted,
      build = function(self)
         ctx:system {
            cwd = NANOMSG_ROOT,
            command = { "ln", "-sfvT", ".", "src/nanomsg" }
         }
      end
   }
   local libnanomsg_a = ctx:Target {
      dirname = NANOMSG_ROOT,
      basename = "libnanomsg.a",
      depends = nanomsg_patched,
      build = function(self)
         ctx:system {
            cwd = NANOMSG_ROOT,
            command = {
               "cmake",
               "-DNN_STATIC_LIB=ON",
               "-DNN_ENABLE_DOC=OFF",
               "-DNN_TOOLS=OFF",
            }
         }
         ctx:system {
            cwd = NANOMSG_ROOT,
            command = { "cmake", "--build", ".", "--clean-first" }
         }
         ctx:system {
            cwd = NANOMSG_ROOT,
            command = { "ctest", "-G", "Debug", "." }
         }
      end
   }
   return ctx:Target {
      dirname = ctx.libdir,
      basename = "libnanomsg.a",
      depends = libnanomsg_a,
      cflags = { "-iquote", NANOMSG_SRC },
      build = function(self)
         ctx:cp {
            src = libnanomsg_a,
            dst = self,
         }
      end
   }
end

P.exports = {
   "adt",
   "argparser",
   "assert",
   "async",
   "buffer",
   "digest",
   "env",
   "epoll",
   "errno",
   "fs",
   "globals",
   "http",
   "inspect",
   "mm",
   "msgpack",
   "nanomsg",
   "net",
   "openssl",
   "parser",
   "process",
   "pthread",
   "re",
   "sched",
   "sha1",
   "signal",
   "stream",
   "testing",
   "time",
   "trigger",
   "uri",
   "util",
   "vfs",
   "zz",
}

P.depends = {
   async = { "trigger" },
   msgpack = { "buffer", "libcmp.a" },
   signal = { "libnanomsg.a", "buffer", "msgpack" },
}

P.ldflags = {
   "-lc",
   "-lm",
   "-ldl",
   "-lpthread",
   "-lanl",
}

P.apps = {
   "zz"
}

P.install = {
   "zz"
}

return P
