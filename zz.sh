#!/bin/bash

set -eu

PACKAGE="github.com/cellux/zz"

ZZPATH="${ZZPATH:-$HOME/zz}"
SRCDIR="$ZZPATH/src/$PACKAGE"
OBJDIR="$ZZPATH/obj/$PACKAGE"
LIBDIR="$ZZPATH/lib/$PACKAGE"
BINDIR="$ZZPATH/bin"

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
LUAJIT_ROOT="deps/$LUAJIT_DIR"
LUAJIT_SRC="$LUAJIT_ROOT/src"
LUAJIT_LIB="$LUAJIT_SRC/libluajit.a"
LUAJIT_BIN="$LUAJIT_SRC/luajit"

CMP_VER=10
CMP_TGZ="cmp-$CMP_VER.tar.gz"
CMP_URL="https://github.com/camgunz/cmp/archive/v$CMP_VER.tar.gz"
CMP_DIR="cmp-$CMP_VER"
CMP_ROOT="deps/$CMP_DIR"
CMP_SRC="$CMP_ROOT"
CMP_OBJ="$CMP_SRC/cmp.o"

NANOMSG_VER="1.1.2"
NANOMSG_TGZ="nanomsg-$NANOMSG_VER.tar.gz"
NANOMSG_URL="https://github.com/nanomsg/nanomsg/archive/$NANOMSG_VER.tar.gz"
NANOMSG_DIR="nanomsg-$NANOMSG_VER"
NANOMSG_ROOT="deps/$NANOMSG_DIR"
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
  if [ ! -e "deps/$target" ]; then
    if ! run curl -skL -o "deps/$target" "$url"; then
      rm -f "deps/$target"
      die "$url: download failed!"
    fi
  fi
}

extract() {
  local tgz="$1"
  local dir="$2"
  if [ ! -e "deps/$dir/.extracted" ]; then
    if ! run tar xzf "deps/$tgz" -C deps || [ ! -d "deps/$dir" ]; then
      die "deps/$tgz: extraction failed!"
    fi
    run touch "deps/$dir/.extracted"
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

all_modules() {
  # list of modules defined in this package
  find . -mindepth 1 -maxdepth 1 -type f -name '*.lua' -printf '%P\n' \
  | sed -r -e 's/\.lua$//' -e '/^_/d' \
  | sort
}

modules() {
  all_modules | grep -v '_test$'
}

test_modules() {
  all_modules | grep '_test$'
}

objs() {
  # converts a list of module names to the corresponding Lua/C object files
  while read m; do
    echo "$OBJDIR/$m.lo"
    [ -e "$m.c" ] && echo "$OBJDIR/$m.o"
  done
}

update_archive() {
  local basename="$1"; shift
  local archive="$LIBDIR/lib${basename}.a"
  # rest of args are object files to add
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

build_core() {
  for m in $(modules); do
    compile_module $m
  done
  update_archive zz $(modules | objs)
}

build_tests() {
  for m in $(test_modules); do
    compile_module $m
  done
  update_archive zz_test $(test_modules | objs)
  cp _main.tpl.c "$TMPDIR/_main.c"
  {
    echo "local PACKAGE = '$PACKAGE'"
    cat _main.tpl.lua
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
  } > "$TMPDIR/_main.lua"
  #cat "$TMPDIR/_main.lua"
  {
    compile_c "$TMPDIR/_main.c" "$TMPDIR/_main.o"
    compile_lua "$TMPDIR/_main.lua" "$TMPDIR/_main.lo" "_main"
    $CC $CFLAGS \
      "$TMPDIR/_main.o" "$TMPDIR/_main.lo" \
      -Wl,--whole-archive \
      "$LIBDIR/libzz_test.a" \
      "$LIBDIR/libzz.a" \
      "$LIBDIR/libluajit.a" \
      "$LIBDIR/libcmp.a" \
      "$LIBDIR/libnanomsg.a" \
      -Wl,--no-whole-archive \
      $LDFLAGS -o "$TMPDIR/_main"
  } > /dev/null
}

build_deps() {
  mkdir -pv deps
  build_luajit
  build_cmp
  build_nanomsg
}

do_build() {
  build_deps
  build_core
}

do_test() {
  build_deps
  build_core
  build_tests "$@"
  "$TMPDIR/_main"
}

do_clean() {
  run rm -rf "$OBJDIR" "$LIBDIR"
  [ -e "$LUAJIT_ROOT/Makefile" ] && (cd "$LUAJIT_ROOT" && run make clean)
  [ -e "$CMP_OBJ" ] && run rm -f "$CMP_OBJ"
  [ -e "$NANOMSG_ROOT/Makefile" ] && (cd "$NANOMSG_ROOT" && run make clean)
}

do_distclean() {
  do_clean
  run rm -rf deps
}

GOAL="${1:-build}"
[ $# -gt 0 ] && shift

GOAL_FUNC="do_$GOAL"
if [ "$(type -t "$GOAL_FUNC")" = "function" ]; then
  $GOAL_FUNC "$@"
else
  die "Unknown goal: $GOAL"
fi
