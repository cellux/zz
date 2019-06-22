local ffi = require('ffi')

ffi.cdef [[

/* threads */

typedef unsigned long int pthread_t;

// dummy typedef to avoid dependency on pthread internals
typedef union pthread_attr_t pthread_attr_t;

int pthread_create (pthread_t *thread,
                    const pthread_attr_t *attr,
                    void *(*start_routine) (void *),
                    void *arg);

int pthread_join (pthread_t thread, void **retval);

/* mutexes */

// dummy typedefs to avoid dependency on pthread internals
typedef union pthread_mutex_t pthread_mutex_t;
typedef union pthread_mutexattr_t pthread_mutexattr_t;

pthread_mutex_t *zz_pthread_mutex_alloc();

int pthread_mutex_init    (pthread_mutex_t *mutex,
                           const pthread_mutexattr_t *attr);
int pthread_mutex_lock    (pthread_mutex_t *mutex);
int pthread_mutex_trylock (pthread_mutex_t *mutex);
int pthread_mutex_unlock  (pthread_mutex_t *mutex);
int pthread_mutex_destroy (pthread_mutex_t *mutex);

void zz_pthread_mutex_free(pthread_mutex_t *mutex);

/* condition variables */

// dummy typedefs to avoid dependency on pthread internals
typedef union pthread_cond_t pthread_cond_t;
typedef union pthread_condattr_t pthread_condattr_t;

pthread_cond_t *zz_pthread_cond_alloc();

int pthread_cond_init      (pthread_cond_t *cond,
                            const pthread_condattr_t *attr);
int pthread_cond_signal    (pthread_cond_t *cond);
int pthread_cond_broadcast (pthread_cond_t *cond);
int pthread_cond_wait      (pthread_cond_t *cond,
                            pthread_mutex_t *mutex);
int pthread_cond_destroy   (pthread_cond_t *cond);

void zz_pthread_cond_free(pthread_cond_t *cond);

]]

local M = {}

return M
