local ffi = require('ffi')

ffi.cdef [[

typedef unsigned long int pthread_t;

typedef union {
  char __size[56];
  long int __align;
} pthread_attr_t;

int pthread_create(pthread_t *thread,
                   const pthread_attr_t *attr,
                   void *(*start_routine) (void *),
                   void *arg);

int pthread_join(pthread_t thread, void **retval);

]]

local M = {}

return M
