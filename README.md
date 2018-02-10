# ZZ

ZZ is a LuaJIT-based app engine with a small core, a growing set of extension libraries and a command line tool `zz` which can be used to compile ZZ programs into self-contained binary executables.

The current version only runs on Linux.

> Warning: This project is work in progress. The code is continuously changing/evolving as I figure out what works and what doesn't. Use at your own risk.

## Core features

* coroutine-based scheduler (sched)
* asynchronous execution of synchronous C calls via a thread pool (async)
* message-based communication between Lua code and C threads (nanomsg, msgpack)
* OS signals are converted into events and injected into the event queue (signal)
* non-blocking timers (time)
* non-blocking Unix/TCP/UDP sockets via epoll (socket)
* non-blocking file operations (file)
* process management (process)
* access to environment variables (env)
* append a zip file to the executable, access its contents through a virtual filesystem (vfs)

## Internal dependencies

* [LuaJIT](http://luajit.org/)
* [nanomsg](http://nanomsg.org/)
* [cmp](https://github.com/camgunz/cmp)
* [inspect.lua](https://github.com/kikito/inspect.lua)

These are either automatically downloaded upon compilation or bundled with the source.

## Usage

The packaging system has been borrowed from Go: the environment variable `ZZPATH` points to a directory (default: `$HOME/zz`) which stores the source code, object files, libraries and binaries of all ZZ packages.

```bash
ZZPATH=$HOME/zz

# create directory for this package
mkdir -p $ZZPATH/src/github.com/cellux/zz

# clone package
cd $ZZPATH/src/github.com/cellux/zz
git clone https://github.com/cellux/zz .

# compile
make
make test
```

If compilation succeeds, you shall find a `zz` executable under `$ZZPATH/bin`. It's advisable to place this directory onto PATH as all ZZ executables intended for global consumption are installed there.

Once `zz` is available, you can install a package of example programs:

```bash
zz get github.com/cellux/zz_examples
```

The resulting executables can be found at `$ZZPATH/bin/github.com/cellux/zz_examples` (the reason it doesn't install into `$ZZPATH/bin` is that I didn't want to pollute the global command namespace with lots of example programs).

If you tinker with the source code of an example, the easiest way to test your changes is via `zz run`:

```bash
cd $ZZPATH/src/github.com/cellux/zz_examples
zz run <example>
```

This would compile `<example>.lua` into a temporary directory and run the resulting binary from there (without copying anything into the `bin` hierarcy).

Further documentation for the `zz` tool can be found in the [wiki](zz.txt).

## Goals

* Learn as much as possible about the stuff that's under the hood in all of the world's software
* Create a platform which I can use to write the programs I want to write, and which I can extend/modify when the problems I face cannot be solved in the higher layers
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
* [Leonard and Sylvia Ritter](http://www.duangle.com/)
* [William A. Adams](https://williamaadams.wordpress.com/)
