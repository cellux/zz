typedef struct {
  int fd;
} zz_trigger;

void zz_trigger_write(zz_trigger *t, uint64_t data);
void zz_trigger_fire(zz_trigger *t);
void zz_trigger_poll(zz_trigger *t);
uint64_t zz_trigger_read(zz_trigger *t);
uint64_t zz_trigger_wait(zz_trigger *t);
