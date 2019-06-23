#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <math.h>
#include <poll.h>

#include "trigger.h"

typedef void (*zz_async_handler)(void *request_data);

#define MAX_REGISTERED_WORKERS 256

struct zz_async_worker {
  int handler_count;
  zz_async_handler *handlers;
};

static struct zz_async_worker registered_workers[MAX_REGISTERED_WORKERS];
static int registered_worker_count = 0;

int zz_async_register_worker(void *handlers[]) {
  if (registered_worker_count == MAX_REGISTERED_WORKERS) {
    fprintf(stderr, "async: cannot register more workers, %d limit exceeded\n",
            MAX_REGISTERED_WORKERS);
    exit(1);
  }
  struct zz_async_worker *z = &registered_workers[registered_worker_count++];
  z->handlers = (zz_async_handler *) handlers;
  z->handler_count = 0;
  // list of handlers must be NULL-terminated
  while (*handlers != NULL) {
    z->handler_count++;
    handlers++;
  }
  // worker id is 1-based
  return registered_worker_count;
}

struct zz_async_worker_info {
  zz_trigger request_trigger;
  int worker_id;
  int handler_id;
  void *request_data;
  zz_trigger response_trigger;
};

void *zz_async_worker_thread(void *arg) {
  struct zz_async_worker_info *info = (struct zz_async_worker_info*) arg;

  /* When the Lua side wants to execute something which would block
   * the event loop, it posts it as a request to one of the async
   * worker threads.
   *
   * Every module can define its request types in C code and register
   * the corresponding handlers with the async module by calling
   * zz_async_register_worker(). A worker is a group of handlers
   * registered in this way. Worker threads can be asked to execute
   * any handler provided by a registered worker.
   *
   * To make a request, the Lua side fills out the selected worker
   * thread's zz_async_worker_info structure with the worker_id,
   * handler_id and a pointer to a structure describing the request
   * (the layout varies by request type). The Lua side then fires the
   * worker thread's request_trigger - this wakes up the thread which
   * then looks up the desired handler and passes request_data to it.
   *
   * Before the request handler completes, it should store any return
   * values in the request_data structure. The worker thread then
   * fires response_trigger which is being polled on the Lua side in
   * the coroutine which is waiting for the completion of the async
   * request.
   */

  while (1) {
    zz_trigger_wait(&info->request_trigger);
    /* worker_id is a 1-based index to the registered_workers array */
    int worker_id = info->worker_id;
    /* worker_id == -1 is the exit signal */
    if (worker_id == -1) {
      zz_trigger_fire(&info->response_trigger);
      break;
    }
    if (worker_id < 1 || worker_id > registered_worker_count) {
      fprintf(stderr, "invalid async request: worker_id is out of range (registered_worker_count=%d, worker_id=%d)\n", registered_worker_count, worker_id);
      exit(1);
    }
    struct zz_async_worker *worker = &registered_workers[worker_id-1];
    /* handler id identifies the handler within the selected worker */
    int handler_id = info->handler_id;
    /* handler_id is 0-based */
    if (handler_id < 0 || handler_id >= worker->handler_count) {
      fprintf(stderr, "invalid async request: handler_id is out of range (worker_id=%d, handler_id=%u, handler_count=%d)\n", worker_id, handler_id, worker->handler_count);
      exit(1);
    }
    zz_async_handler handler = worker->handlers[handler_id];
    handler(info->request_data); /* process request */
    zz_trigger_fire(&info->response_trigger);
  }
  return NULL;
}

/* a pre-defined handler for testing purposes */

enum {
  ZZ_ASYNC_ECHO
};

struct zz_async_echo {
  double delay;
  double payload;
  double response;
};

void zz_async_echo(struct zz_async_echo *r) {
  double fractional_part, integer_part;
  fractional_part = modf(r->delay, &integer_part);
  struct timespec rqtp;
  rqtp.tv_sec = integer_part;
  rqtp.tv_nsec = fractional_part * 1e9;
  if (nanosleep(&rqtp, NULL) != 0) {
    fprintf(stderr, "zz_async_echo: nanosleep() failed\n");
  }
  r->response = r->payload;
}

void *zz_async_handlers[] = {
  zz_async_echo,
  0
};
