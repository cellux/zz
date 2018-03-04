#!/bin/bash

set -eu

PACKAGE="github.com/cellux/zz"
PACKAGE_MODULES=(
  adt
  argparser
  assert
  async
  buffer
  digest
  env
  epoll
  err
  errno
  fs
  globals
  iconv
  inspect
  mm
  msgpack
  nanomsg
  net
  openssl
  parser
  process
  pthread
  re
  sched
  sha1
  signal
  stream
  time
  trigger
  uri
  util
)
PACKAGE_LIBS=(zz luajit cmp nanomsg)
PACKAGE_APPS=(zz)
PACKAGE_INSTALL=(zz)

ZZPATH="${ZZPATH:-$HOME/zz}"
SRCDIR="$ZZPATH/src/$PACKAGE"
OBJDIR="$ZZPATH/obj/$PACKAGE"
LIBDIR="$ZZPATH/lib/$PACKAGE"
BINDIR="$ZZPATH/bin/$PACKAGE"
GBINDIR="$ZZPATH/bin" # for globally installed executables

mkdir -p "$OBJDIR"
mkdir -p "$LIBDIR"
mkdir -p "$BINDIR"

TMPDIR="$ZZPATH/tmp/$PACKAGE/$$"

mkdir -p "$TMPDIR"
trap "rm -rf $TMPDIR" EXIT

LUAJIT_VER="2.1.0-beta3"
LUAJIT_TGZ="LuaJIT-$LUAJIT_VER.tar.gz"
LUAJIT_URL="http://luajit.org/download/$LUAJIT_TGZ"
LUAJIT_DIR="LuaJIT-${LUAJIT_VER}"
LUAJIT_ROOT="native/$LUAJIT_DIR"
LUAJIT_SRC="$LUAJIT_ROOT/src"
LUAJIT_LIB="$LUAJIT_SRC/libluajit.a"
LUAJIT_BIN="$LUAJIT_SRC/luajit"

CMP_VER=10
CMP_TGZ="cmp-$CMP_VER.tar.gz"
CMP_URL="https://github.com/camgunz/cmp/archive/v$CMP_VER.tar.gz"
CMP_DIR="cmp-$CMP_VER"
CMP_ROOT="native/$CMP_DIR"
CMP_SRC="$CMP_ROOT"
CMP_OBJ="$CMP_SRC/cmp.o"

NANOMSG_VER="1.1.2"
NANOMSG_TGZ="nanomsg-$NANOMSG_VER.tar.gz"
NANOMSG_URL="https://github.com/nanomsg/nanomsg/archive/$NANOMSG_VER.tar.gz"
NANOMSG_DIR="nanomsg-$NANOMSG_VER"
NANOMSG_ROOT="native/$NANOMSG_DIR"
NANOMSG_LIB="$NANOMSG_ROOT/libnanomsg.a"
NANOMSG_SRC="$NANOMSG_ROOT/src"

CC="${CC:-gcc}"
CFLAGS="-Wall -iquote $LUAJIT_SRC -iquote $NANOMSG_SRC -iquote $CMP_SRC"
LDFLAGS="-Wl,-E -lm -ldl -lpthread -lanl"

cd "$(dirname "${BASH_SOURCE[0]}")"

log() {
  echo "$@"
}

die() {
  echo "$@"
  exit 1
}

run() {
  echo "$@"
  "$@"
}

if [ "$PWD" != "$SRCDIR" ]; then
  die "$PACKAGE should be checked out to $SRCDIR"
fi

download() {
  local url="$1"
  local target="$2"
  if [ ! -e "native/$target" ]; then
    if ! run curl -skL -o "native/$target" "$url"; then
      rm -f "native/$target"
      die "$url: download failed!"
    fi
  fi
}

extract() {
  local tgz="$1"
  local dir="$2"
  if [ ! -e "native/$dir/.extracted" ]; then
    if ! run tar xzf "native/$tgz" -C native || [ ! -d "native/$dir" ]; then
      die "native/$tgz: extraction failed!"
    fi
    run touch "native/$dir/.extracted"
  fi
}

usorted() {
  # sort arguments, remove duplicates
  for x in "$@"; do echo "$x"; done | sort -u
}

mangle() {
  # mangle module names to prevent clashes between packages
  local name="$1"
  echo -n "zz_"
  echo -n "$PACKAGE/$name" | sha1sum | awk '{print $1}'
}

build_luajit() {
  download "$LUAJIT_URL" "$LUAJIT_TGZ"
  extract "$LUAJIT_TGZ" "$LUAJIT_DIR"
  if [ ! -e "$LUAJIT_LIB" ]; then
    run sed -i -r \
      -e 's/^(BUILDMODE)=.*/\1= static/' \
      -e 's/^(XCFLAGS)=.*/\1= -DLUAJIT_ENABLE_LUA52COMPAT/' \
      "$LUAJIT_ROOT/src/Makefile"
    run make -C "$LUAJIT_ROOT" clean amalg
  fi
  if [ "$LUAJIT_LIB" -nt "$LIBDIR/$(basename "$LUAJIT_LIB")" ]; then
    run install -v -t "$LIBDIR" -D -m 0644 "$LUAJIT_LIB"
  fi
}

build_cmp() {
  download "$CMP_URL" "$CMP_TGZ"
  extract "$CMP_TGZ" "$CMP_DIR"
  if [ ! -e "$CMP_OBJ" ]; then
    (cd "$CMP_SRC" && run $CC -c cmp.c)
  fi
  if [ "$CMP_OBJ" -nt "$LIBDIR/libcmp.a" ]; then
    run ar rsvc "$LIBDIR/libcmp.a" "$CMP_OBJ"
  fi
}

build_nanomsg() {
  download "$NANOMSG_URL" "$NANOMSG_TGZ"
  extract "$NANOMSG_TGZ" "$NANOMSG_DIR"
  if [ ! -e "$NANOMSG_LIB" ]; then
    run ln -sfvT . "$NANOMSG_ROOT/src/nanomsg"
    (cd "$NANOMSG_ROOT" && run cmake -DNN_STATIC_LIB=ON -DNN_ENABLE_DOC=OFF -DNN_TOOLS=OFF .)
    (cd "$NANOMSG_ROOT" && run cmake --build .)
    (cd "$NANOMSG_ROOT" && run ctest -G Debug .)
  fi
  if [ "$NANOMSG_LIB" -nt "$LIBDIR/$(basename "$NANOMSG_LIB")" ]; then
    run install -v -t "$LIBDIR" -D -m 0644 "$NANOMSG_LIB"
  fi
}

compile_lua() {
  local src="$1"
  local obj="$2"
  local name="$3"
  # compile Lua module into bytecode and wrap result into linkable object file
  #
  # -b: save (or list) bytecode
  # -t o: output shall be an object file
  # -n $name: name of the symbol table entry
  # -g: keep debug info
  # $src: input file
  # $obj: output file
  echo "[C] $(basename "$src")"
  LUA_PATH="$LUAJIT_SRC/?.lua" $LUAJIT_BIN -b -t o -n "$name" -g "$src" "$obj"
}

compile_c() {
  local src="$1"
  local obj="$2"
  echo "[C] $(basename "$src")"
  $CC $CFLAGS -c "$src" -o "$obj"
}

compile_module() {
  local m="$1"
  local m_src="$m.lua"
  local m_obj="$OBJDIR/$m.lo"
  if [ $m_src -nt $m_obj ]; then
    compile_lua "$m_src" "$m_obj" "$(mangle $m)"
  fi
  # if there is C support for this module, compile it too
  local c_src="$m.c"
  if [ -e $c_src ]; then
    local c_obj="$OBJDIR/$m.o"
    local c_h="$m.h"
    if [ $c_src -nt $c_obj ] || [ -e $c_h -a $c_h -nt $c_obj ]; then
        compile_c "$c_src" "$c_obj"
    fi
  fi
}

compile_main() {
  # $@: objects and libraries to link in
  # stdin: main program
  cp _main.tpl.c "$TMPDIR/_main.c"
  {
    echo "local PACKAGE = '$PACKAGE'"
    cat _main.tpl.lua
    cat # inject main program
  } > "$TMPDIR/_main.lua"
  #cat "$TMPDIR/_main.lua"
  {
    compile_c "$TMPDIR/_main.c" "$TMPDIR/_main.o"
    compile_lua "$TMPDIR/_main.lua" "$TMPDIR/_main.lo" "_main"
    $CC \
      "$TMPDIR/_main.o" "$TMPDIR/_main.lo" \
      -Wl,--whole-archive "$@" -Wl,--no-whole-archive \
      $LDFLAGS -o "$TMPDIR/_main"
  } > /dev/null # only errors should be shown from these steps
}

jit_modules() {
  for f in $(cd $LUAJIT_SRC/jit && ls *.lua); do
    echo "${f%.lua}"
  done
}

package_modules() {
  # list of modules defined in this package
  for m in "${PACKAGE_MODULES[@]}"; do
    echo "$m"
  done
}

test_modules() {
  # list of test modules defined in this package
  for m in "${PACKAGE_MODULES[@]}"; do
    [ -e "${m}_test.lua" ] && echo "${m}_test"
  done
  # jit is a cuckoo's egg
  echo "jit_test"
}

package_libs() {
  # list of libraries generated by this package
  for lib in "${PACKAGE_LIBS[@]}"; do
    echo "$lib"
  done
}

package_apps() {
  # list of apps generated by this package
  for app in "${PACKAGE_APPS[@]}"; do
    echo "$app"
  done
}

package_install() {
  # list of apps installed by this package
  for app in "${PACKAGE_INSTALL[@]}"; do
    echo "$app"
  done
}

resolve_obj() {
  # module name -> corresponding object files
  local m="$1"
  echo "$OBJDIR/$m.lo"
  [ -e "$m.c" ] && echo "$OBJDIR/$m.o"
}

resolve_objs() {
  # list of modules names -> corresponding object files
  while read m; do
    resolve_obj $m
  done
}

resolve_lib() {
  # library name -> corresponding archive file
  local lib="$1"
  echo "$LIBDIR/lib${lib}.a"
}

resolve_libs() {
  # list of library names -> corresponding archive files
  while read lib; do
    resolve_lib $lib
  done
}

update_archive() {
  local lib="$1"; shift
  # $@: object files to add
  local archive="$LIBDIR/lib${lib}.a"
  local need_update=
  for o in "$@"; do
    if [ "$o" -nt "$archive" ]; then
      need_update=1
      break
    fi
  done
  if [ -n "$need_update" ]; then
    echo "[A] $archive"
    ar rsc "$archive" "$@"
  fi
}

build_jit_modules() {
  mkdir -p "$OBJDIR/jit"
  local -a objs
  for m in $(jit_modules); do
    local m_src="$LUAJIT_SRC/jit/$m.lua"
    local m_obj="$OBJDIR/jit/$m.lo"
    if [ $m_src -nt $m_obj ]; then
      # jit module names are not mangled
      compile_lua "$m_src" "$m_obj" "jit.$m"
    fi
    objs+=($m_obj)
  done
  # these belong to libluajit.a
  update_archive luajit "${objs[@]}"
}

build_modules() {
  for m in $(package_modules) package; do
    compile_module $m
  done
  update_archive "$(basename $PACKAGE)" \
    $(package_modules | resolve_objs) \
    $(resolve_obj package)
}

build_test_modules() {
  for m in $(test_modules); do
    compile_module $m
  done
  update_archive "$(basename $PACKAGE)_test" \
    $(test_modules | resolve_objs)
}

build_apps() {
  for app in $(package_apps); do
    compile_module $app
    {
      echo "local app_module = require('$(mangle $app)')"
      echo "if type(app_module)=='table' and app_module.main then"
      echo "  app_module.main()"
      echo "end"
    } | compile_main \
      $(resolve_obj $app) \
      $(package_libs | resolve_libs)
    install -v -T -m 0755 "$TMPDIR/_main" "$BINDIR/$app"
  done
}

install_apps() {
  for app in $(package_install); do
    cp -v "$BINDIR/$app" "$GBINDIR/$app"
  done
}

build_native() {
  mkdir -pv native
  build_luajit
  build_cmp
  build_nanomsg
}

do_build() {
  build_native
  build_jit_modules
  build_modules
  build_apps
}

do_install() {
  do_build
  install_apps
}

do_test() {
  build_native
  build_jit_modules
  build_modules
  build_test_modules
  {
    if [ $# -gt 0 ]; then
      # modules to test have been passed on command line
      for m in "$@"; do
        t="${m}_test"
        echo "require_test('$t')"
      done
    else
      # run all tests
      for t in $(test_modules); do
        echo "require_test('$t')"
      done
    fi
  } | compile_main \
    $(resolve_lib zz_test) \
    $(package_libs | resolve_libs)
  "$TMPDIR/_main" # run tests
}

do_clean() {
  run rm -rf "$OBJDIR" "$LIBDIR"
  [ -e "$LUAJIT_ROOT/Makefile" ] && (cd "$LUAJIT_ROOT" && run make clean)
  [ -e "$CMP_OBJ" ] && run rm -f "$CMP_OBJ"
  [ -e "$NANOMSG_ROOT/Makefile" ] && (cd "$NANOMSG_ROOT" && run make clean)
}

do_distclean() {
  do_clean
  run rm -rf native
}

GOAL="${1:-build}"
[ $# -gt 0 ] && shift

GOAL_FUNC="do_$GOAL"
if [ "$(type -t "$GOAL_FUNC")" = "function" ]; then
  $GOAL_FUNC "$@"
else
  die "Unknown goal: $GOAL"
fi
