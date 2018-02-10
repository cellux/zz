typedef struct {
  int fd;
} zz_trigger;

void zz_trigger_poll(zz_trigger *t);
void zz_trigger_fire(zz_trigger *t);
