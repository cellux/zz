#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <assert.h>

enum {
  ZZ_ASYNC_FS_LSEEK,
  ZZ_ASYNC_FS_READ,
  ZZ_ASYNC_FS_WRITE,
  ZZ_ASYNC_FS_CLOSE,
  ZZ_ASYNC_FS_STAT,
  ZZ_ASYNC_FS_LSTAT
};

struct zz_async_fs_lseek {
  int fd;
  off_t offset;
  int whence;
  off_t rv;
};

void zz_async_fs_lseek(struct zz_async_fs_lseek *req) {
  req->rv = lseek(req->fd, req->offset, req->whence);
}

struct zz_async_fs_read_write {
  int fd;
  void *buf;
  size_t count;
  ssize_t nbytes;
};

void zz_async_fs_read(struct zz_async_fs_read_write *req) {
  req->nbytes = read(req->fd, req->buf, req->count);
}

void zz_async_fs_write(struct zz_async_fs_read_write *req) {
  req->nbytes = write(req->fd, req->buf, req->count);
}

struct zz_async_fs_close {
  int fd;
  int rv;
};

void zz_async_fs_close(struct zz_async_fs_close *req) {
  req->rv = close(req->fd);
}

struct stat * zz_fs_Stat_new() {
  return malloc(sizeof(struct stat));
}

dev_t     zz_fs_Stat_dev(struct stat * buf) { return buf->st_dev; }
ino_t     zz_fs_Stat_ino(struct stat * buf) { return buf->st_ino; }
mode_t    zz_fs_Stat_mode(struct stat *buf) { return buf->st_mode; }
mode_t    zz_fs_Stat_type(struct stat *buf) { return buf->st_mode & S_IFMT; }
mode_t    zz_fs_Stat_perms(struct stat *buf) { return buf->st_mode & ~S_IFMT; }
nlink_t   zz_fs_Stat_nlink(struct stat *buf) { return buf->st_nlink; }
uid_t     zz_fs_Stat_uid(struct stat *buf) { return buf->st_uid; }
gid_t     zz_fs_Stat_gid(struct stat *buf) { return buf->st_gid; }
dev_t     zz_fs_Stat_rdev(struct stat *buf) { return buf->st_rdev; }
off_t     zz_fs_Stat_size(struct stat *buf) { return buf->st_size; }
blksize_t zz_fs_Stat_blksize(struct stat *buf) { return buf->st_blksize; }
blkcnt_t  zz_fs_Stat_blocks(struct stat *buf) { return buf->st_blocks; }

struct timespec * zz_fs_Stat_atime(struct stat *buf) { return &buf->st_atim; }
struct timespec * zz_fs_Stat_mtime(struct stat *buf) { return &buf->st_mtim; }
struct timespec * zz_fs_Stat_ctime(struct stat *buf) { return &buf->st_ctim; }

void zz_fs_Stat_free(struct stat * buf) {
  free(buf);
}

int zz_fs_stat(const char *path, struct stat *buf) {
  return stat(path, buf);
}

int zz_fs_lstat(const char *path, struct stat *buf) {
  return lstat(path, buf);
}

char * zz_fs_dirent_name(struct dirent *entry) {
  return entry->d_name;
}

const char * zz_fs_type(mode_t mode) {
  if (S_ISREG(mode))
    return "reg";
  else if (S_ISDIR(mode))
    return "dir";
  else if (S_ISLNK(mode))
    return "lnk";
  else if (S_ISCHR(mode))
    return "chr";
  else if (S_ISBLK(mode))
    return "blk";
  else if (S_ISFIFO(mode))
    return "fifo";
  else if (S_ISSOCK(mode))
    return "sock";
  else
    return NULL;
}

struct zz_async_fs_stat {
  char *path;
  struct stat *buf;
  int rv;
};

void zz_async_fs_stat(struct zz_async_fs_stat *req) {
  req->rv = stat(req->path, req->buf);
}

void zz_async_fs_lstat(struct zz_async_fs_stat *req) {
  req->rv = lstat(req->path, req->buf);
}

void *zz_async_fs_handlers[] = {
  zz_async_fs_lseek,
  zz_async_fs_read,
  zz_async_fs_write,
  zz_async_fs_close,
  zz_async_fs_stat,
  zz_async_fs_lstat,
  0
};
