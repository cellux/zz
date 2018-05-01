#include <sys/wait.h>

enum {
  ZZ_ASYNC_PROCESS_WAITPID
};

struct zz_async_process_waitpid {
  pid_t pid;
  int status;
  int options;
  pid_t rv;
};

void zz_async_process_waitpid(struct zz_async_process_waitpid *req) {
  req->rv = waitpid(req->pid, &req->status, req->options);
}

void *zz_async_process_handlers[] = {
  zz_async_process_waitpid,
  0
};
