local P = {}

P.package = "github.com/cellux/zz"

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
}

P.libs = {
   "zz",
   "luajit",
   "cmp",
   "nanomsg",
}

return P
