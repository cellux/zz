#include <sys/wait.h>
#include <errno.h>

enum {
  ZZ_ASYNC_PROCESS_WAITPID
};

union zz_async_process_req {
  struct {
    pid_t pid;
    int status;
    int options;
    pid_t rv;
    int _errno;
  } waitpid;
};

void zz_async_process_waitpid(union zz_async_process_req *req) {
  req->waitpid.rv = waitpid(req->waitpid.pid, &req->waitpid.status, req->waitpid.options);
  req->waitpid._errno = errno;
}

void *zz_async_process_handlers[] = {
  zz_async_process_waitpid,
  0
};
