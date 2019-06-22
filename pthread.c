#include <pthread.h>
#include <stdlib.h>

pthread_mutex_t *zz_pthread_mutex_alloc() {
  return (pthread_mutex_t*) calloc(1, sizeof(pthread_mutex_t));
}

void zz_pthread_mutex_free(pthread_mutex_t *mutex) {
  free(mutex);
}

pthread_cond_t *zz_pthread_cond_alloc() {
  return (pthread_cond_t*) calloc(1, sizeof(pthread_cond_t));
}

void zz_pthread_cond_free(pthread_cond_t *cond) {
  free(cond);
}
