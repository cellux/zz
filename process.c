#include <sys/wait.h>

enum {
  ZZ_ASYNC_PROCESS_WAITPID
};

union zz_async_process_req {
  struct {
    pid_t pid;
    int status;
    int options;
    pid_t rv;
  } waitpid;
};

void zz_async_process_waitpid(union zz_async_process_req *req) {
  req->waitpid.rv = waitpid(req->waitpid.pid, &req->waitpid.status, req->waitpid.options);
}

void *zz_async_process_handlers[] = {
  zz_async_process_waitpid,
  0
};
