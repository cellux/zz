local P = {}

P.package = "github.com/cellux/zz"

local LUAJIT_VER  = "2.1.0-beta3"
local CMP_VER     = "10"
local NANOMSG_VER = "1.1.2"

P.native = {}

P.native.libluajit = function(ctx)
   local LUAJIT_TGZ = sf("LuaJIT-%s.tar.gz", LUAJIT_VER)
   local LUAJIT_URL = sf("http://luajit.org/download/%s", LUAJIT_TGZ)
   local LUAJIT_DIR = sf("LuaJIT-%s", LUAJIT_VER)
   local LUAJIT_ROOT = sf("%s/%s", ctx.nativedir, LUAJIT_DIR)
   local LUAJIT_SRC = sf("%s/src", LUAJIT_ROOT)
   local LUAJIT_LIB = sf("%s/libluajit.a", LUAJIT_SRC)
   local LUAJIT_BIN = sf("%s/luajit", LUAJIT_SRC)
   local luajit_tgz = ctx:Target {
      dirname = ctx.nativedir,
      basename = LUAJIT_TGZ,
      build = function(self)
         ctx:download {
            cwd = ctx.nativedir,
            src = LUAJIT_URL,
            dst = LUAJIT_TGZ,
         }
      end
   }
   local luajit_src = ctx:Target {
      dirname = LUAJIT_ROOT,
      basename = ".extracted",
      depends = luajit_tgz,
      build = function(self)
         ctx:extract {
            cwd = ctx.nativedir,
            src = luajit_tgz,
            touch = self,
         }
      end
   }
   local luajit_patched = ctx:Target {
      dirname = LUAJIT_ROOT,
      basename = ".patched",
      depends = luajit_src,
      build = function(self)
         ctx:system {
            cwd = LUAJIT_SRC,
            command = {
               "sed", "-i", "-r",
               "-e", "s/^(BUILDMODE)=.*/\\1= static/",
               "-e", "s/^(XCFLAGS)=.*/\\1= -DLUAJIT_ENABLE_LUA52COMPAT/",
               "Makefile"
            },
            touch = self,
         }
      end
   }
   local luajit_a = ctx:Target {
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
   return ctx:Target {
      dirname = ctx.libdir,
      basename = "libluajit.a",
      depends = luajit_a,
      cflags = { "-iquote", LUAJIT_SRC },
      build = function(self)
         ctx:cp {
            src = luajit_a,
            dst = self,
         }
      end
   }
end

P.native.libcmp = function(ctx)
   local CMP_TGZ = sf("cmp-%s.tar.gz", CMP_VER)
   local CMP_URL = sf("https://github.com/camgunz/cmp/archive/v%s.tar.gz", CMP_VER)
   local CMP_DIR = sf("cmp-%s", CMP_VER)
   local CMP_ROOT = sf("%s/%s", ctx.nativedir, CMP_DIR)
   local CMP_SRC = CMP_ROOT
   local CMP_OBJ = sf("%s/cmp.o", CMP_SRC)
   local cmp_tgz = ctx:Target {
      dirname = ctx.nativedir,
      basename = CMP_TGZ,
      build = function(self)
         ctx:download {
            cwd = ctx.nativedir,
            src = CMP_URL,
            dst = CMP_TGZ,
         }
      end
   }
   local cmp_src = ctx:Target {
      dirname = CMP_ROOT,
      basename = ".extracted",
      depends = cmp_tgz,
      build = function(self)
         ctx:extract {
            cwd = ctx.nativedir,
            src = cmp_tgz,
            touch = self,
         }
      end
   }
   local cmp_o = ctx:Target {
      dirname = CMP_ROOT,
      basename = "cmp.o",
      depends = { cmp_c, cmp_h },
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
            src = { cmp_o },
            dst = self
         }
      end
   }
end

P.native.libnanomsg = function(ctx)
   local NANOMSG_TGZ = sf("nanomsg-%s.tar.gz", NANOMSG_VER)
   local NANOMSG_URL = sf("https://github.com/nanomsg/nanomsg/archive/%s.tar.gz", NANOMSG_VER)
   local NANOMSG_DIR = sf("nanomsg-%s", NANOMSG_VER)
   local NANOMSG_ROOT = sf("%s/%s", ctx.nativedir, NANOMSG_DIR)
   local NANOMSG_LIB = sf("%s/libnanomsg.a", NANOMSG_ROOT)
   local NANOMSG_SRC = sf("%s/src", NANOMSG_ROOT)
   local nanomsg_tgz = ctx:Target {
      dirname = ctx.nativedir,
      basename = NANOMSG_TGZ,
      build = function(self)
         ctx:download {
            cwd = ctx.nativedir,
            src = NANOMSG_URL,
            dst = NANOMSG_TGZ,
         }
      end
   }
   local nanomsg_src = ctx:Target {
      dirname = NANOMSG_ROOT,
      basename = ".extracted",
      depends = nanomsg_tgz,
      build = function(self)
         ctx:extract {
            cwd = ctx.nativedir,
            src = nanomsg_tgz,
            touch = self,
         }
      end
   }
   local nanomsg_patched = ctx:Target {
      dirname = NANOMSG_ROOT,
      basename = ".patched",
      depends = nanomsg_src,
      build = function(self)
         ctx:system {
            cwd = NANOMSG_ROOT,
            command = {"ln", "-sfvT", ".", "src/nanomsg"},
            touch = self,
         }
      end
   }
   local nanomsg_a = ctx:Target {
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
      depends = nanomsg_a,
      cflags = { "-iquote", NANOMSG_SRC },
      build = function(self)
         ctx:cp {
            src = nanomsg_a,
            dst = self,
         }
      end
   }
end

P.modules = {
   "adt",
   "argparser",
   "assert",
   "async",
   "buffer",
   "digest",
   "env",
   "epoll",
   "err",
   "errno",
   "fs",
   "globals",
   "iconv",
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
   "time",
   "trigger",
   "uri",
   "util",
   "zz",
}

P.module_deps = {
   async = { "trigger" },
   msgpack = { "buffer", "libcmp" },
   signal = { "libnanomsg", "buffer", "msgpack" },
}

P.apps = {
   "zz"
}

P.install = {
   "zz"
}

return P
