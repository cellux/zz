# ZZ

ZZ is a general-purpose app engine built on top of LuaJIT and C. It has a small core, a growing set of extension libraries and a command line tool `zz` which can be used to compile ZZ programs into self-contained binary executables.

The current version only runs on Linux.

> Warning: This project is work in progress. The code is continuously
> changing/evolving as I figure out what works and what doesn't. Use
> at your own risk.

## Core features

* coroutine-based, single-threaded scheduler and event loop (sched)
* async execution of synchronous C calls via thread pool and completion events (async, trigger)
* transparent conversion of OS signals into events (signal)
* memory buffers (buffer), arena allocator (mm)
* non-blocking timers (time)
* non-blocking Unix/TCP/UDP sockets (epoll, net)
* non-blocking file-system operations (fs)
* unified stream API over files, sockets and memory buffers (stream)
* inter-process communication via message passing (nanomsg, msgpack)
* process management (process)
* regular expressions (re)
* reading/writing of ZIP files (zip)
* access to command line arguments (argparser)
* access to environment variables (env)
* async testing framework (testing, assert)

## Internal dependencies

* [LuaJIT](http://luajit.org/)
* [nanomsg](http://nanomsg.org/)
* [cmp](https://github.com/camgunz/cmp)
* [libzip](https://libzip.org)
* [inspect.lua](https://github.com/kikito/inspect.lua)

These are either automatically downloaded upon compilation or bundled with the source.

## Installation

First install the following build dependencies:

```
bash curl sha1sum awk make gcc binutils cmake
```

Then run the following commands in a shell:

```bash
# everything is stored under $ZZPATH
ZZPATH=$HOME/zz

# create package directory
mkdir -p $ZZPATH/src/github.com/cellux/zz

# clone package
cd $ZZPATH/src/github.com/cellux/zz
git clone https://github.com/cellux/zz .

# compile, test, install
make
make test
make install
```

If installation succeeds, you shall find a `zz` executable under `$ZZPATH/bin`. It's advisable to place this directory onto PATH as all ZZ executables intended for global consumption are installed there.

## Examples

There are a couple of example programs in the [zz_examples](https://github.com/cellux/zz_examples) Git repository.

Once you have the `zz` tool, you can fetch and build the examples and their dependencies (recursively) using the following command:

```
zz get github.com/cellux/zz_examples
```

Example programs can be executed via `zz run`, for example:

```
cd $ZZPATH/src/github.com/cellux/zz_examples/opengl/progschj
zz run 07-geometry-shader-blending.lua
```

## Further information

* read the tests (`*_test.lua`)
* check INTERNALS.md for some further details

## Goals

* Learn as much as possible about the stuff that's under the hood in all of the world's software
* Create a platform which I can use to write the programs I always wanted to write, and which I can extend/modify when the problems I face cannot be solved in the higher layers
* Express myself

## Philosophy

* Small is beautiful
* Reinventing the wheel is a good way to learn
* Standing on the shoulders of giants is a good idea
* Perfection results from finding optimal trade-offs

## Inspiration

* [LuaJIT](https://luajit.org/)
* [Go](https://golang.org/)
* [OpenResty](https://openresty.org/)
* [Luvit](https://luvit.io/)
* [Raspberry Pi](https://www.raspberrypi.org/)
* [Scheme](http://www.schemers.org/Documents/Standards/R5RS/)
* [Extempore](https://github.com/digego/extempore)
* [SuperCollider](https://supercollider.github.io/)
