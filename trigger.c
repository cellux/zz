#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <poll.h>

#include "trigger.h"

void zz_trigger_poll(zz_trigger *t) {
  if (!t->fd) {
    fprintf(stderr, "zz_trigger_poll(): fd=0\n");
    exit(1);
  }
  struct pollfd fds[1];
  fds[0].fd = t->fd;
  fds[0].events = POLLIN;
  int status = poll(fds, 1, -1);
  if (status != 1) {
    fprintf(stderr, "zz_trigger_poll(): status=%d, expected 1\n", status);
    exit(1);
  }
  uint64_t data = 0;
  int nbytes = read(t->fd, &data, 8);
  if (nbytes != 8) {
    fprintf(stderr, "zz_trigger_poll(): nbytes=%d, expected 8\n", nbytes);
    exit(1);
  }
  if (data != 1) {
    fprintf(stderr, "zz_trigger_poll(): data=%lld, expected 1\n", data);
    exit(1);
  }
}

void zz_trigger_fire(zz_trigger *t) {
  if (!t->fd) return;
  uint64_t data = 1;
  int nbytes = write(t->fd, &data, sizeof(uint64_t));
  if (nbytes != 8) {
    fprintf(stderr, "zz_trigger_fire(): cannot write to event fd\n");
    exit(1);
  }
}
