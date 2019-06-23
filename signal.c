#include <stdio.h>
#include <stdlib.h>
#include <signal.h>

#include "buffer.h"
#include "msgpack.h"
#include "msgqueue.h"

void *zz_signal_handler_thread(void *arg) {
  sigset_t ss;
  siginfo_t siginfo;
  int signum;

  zz_msgqueue *q = (zz_msgqueue*) arg;

  sigfillset(&ss);

  for (;;) {
    signum = sigwaitinfo(&ss, &siginfo);
    if (signum < 0) {
      fprintf(stderr, "signal: sigwait() failed\n");
      exit(1);
    }
    if (signum == SIGALRM) {
      /* SIGALRM is our exit signal */
      break;
    }
    zz_msgqueue_lock(q);
    zz_msgqueue_prepare_write(q, 32);
    zz_msgqueue_pack_array(q, 2);
    zz_msgqueue_pack_str(q, "signal", 6);
    zz_msgqueue_pack_array(q, 2);
    zz_msgqueue_pack_integer(q, signum);
    zz_msgqueue_pack_integer(q, siginfo.si_pid);
    zz_msgqueue_finish_write(q);
    zz_msgqueue_unlock(q);
  }

  return NULL;
}
