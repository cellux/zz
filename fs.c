#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <dirent.h>
#include <assert.h>
#include <glob.h>

enum {
  ZZ_ASYNC_FS_OPEN,
  ZZ_ASYNC_FS_READ,
  ZZ_ASYNC_FS_WRITE,
  ZZ_ASYNC_FS_LSEEK,
  ZZ_ASYNC_FS_CLOSE,
  ZZ_ASYNC_FS_FUTIMENS,
  ZZ_ASYNC_FS_ACCESS,
  ZZ_ASYNC_FS_CHMOD,
  ZZ_ASYNC_FS_UNLINK,
  ZZ_ASYNC_FS_MKDIR,
  ZZ_ASYNC_FS_RMDIR,
  ZZ_ASYNC_FS_SYMLINK,
  ZZ_ASYNC_FS_READLINK,
  ZZ_ASYNC_FS_REALPATH,
  ZZ_ASYNC_FS_STAT,
  ZZ_ASYNC_FS_LSTAT,
  ZZ_ASYNC_FS_OPENDIR,
  ZZ_ASYNC_FS_READDIR,
  ZZ_ASYNC_FS_CLOSEDIR,
  ZZ_ASYNC_FS_GLOB
};

struct zz_async_fs_open {
  char *file;
  int oflag;
  mode_t mode;
  int rv;
};

void zz_async_fs_open(struct zz_async_fs_open *req) {
  req->rv = open(req->file, req->oflag, req->mode);
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

struct zz_async_fs_lseek {
  int fd;
  off_t offset;
  int whence;
  off_t rv;
};

void zz_async_fs_lseek(struct zz_async_fs_lseek *req) {
  req->rv = lseek(req->fd, req->offset, req->whence);
}

struct zz_async_fs_close {
  int fd;
  int rv;
};

void zz_async_fs_close(struct zz_async_fs_close *req) {
  req->rv = close(req->fd);
}

struct zz_async_fs_futimens {
  int fd;
  struct timespec *times;
  int rv;
};

void zz_async_fs_futimens(struct zz_async_fs_futimens *req) {
  req->rv = futimens(req->fd, req->times);
}

struct zz_async_fs_access {
  char *path;
  int how;
  int rv;
};

void zz_async_fs_access(struct zz_async_fs_access *req) {
  req->rv = access(req->path, req->how);
}

struct zz_async_fs_chmod {
  char *file;
  mode_t mode;
  int rv;
};

void zz_async_fs_chmod(struct zz_async_fs_chmod *req) {
  req->rv = chmod(req->file, req->mode);
}

struct zz_async_fs_unlink {
  char *filename;
  int rv;
};

void zz_async_fs_unlink(struct zz_async_fs_unlink *req) {
  req->rv = unlink(req->filename);
}

struct zz_async_fs_mkdir_rmdir {
  char *file;
  mode_t mode;
  int rv;
};

void zz_async_fs_mkdir(struct zz_async_fs_mkdir_rmdir *req) {
  req->rv = mkdir(req->file, req->mode);
}

void zz_async_fs_rmdir(struct zz_async_fs_mkdir_rmdir *req) {
  req->rv = rmdir(req->file);
}

struct zz_async_fs_symlink {
  char *oldname;
  char *newname;
  int rv;
};

void zz_async_fs_symlink(struct zz_async_fs_symlink *req) {
  req->rv = symlink(req->oldname, req->newname);
}

struct zz_async_fs_readlink {
  char *filename;
  char *buffer;
  size_t size;
  ssize_t rv;
};

void zz_async_fs_readlink(struct zz_async_fs_readlink *req) {
  req->rv = readlink(req->filename, req->buffer, req->size);
}

struct zz_async_fs_realpath {
  char *name;
  char *resolved;
  char *rv;
};

void zz_async_fs_realpath(struct zz_async_fs_realpath *req) {
  req->rv = realpath(req->name, req->resolved);
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

struct zz_async_fs_opendir_readdir_closedir {
  char *path;
  DIR *dir;
  struct dirent *dirent;
  int rv;
};

void zz_async_fs_opendir(struct zz_async_fs_opendir_readdir_closedir *req) {
  req->dir = opendir(req->path);
}

void zz_async_fs_readdir(struct zz_async_fs_opendir_readdir_closedir *req) {
  req->dirent = readdir(req->dir);
}

void zz_async_fs_closedir(struct zz_async_fs_opendir_readdir_closedir *req) {
  req->rv = closedir(req->dir);
}

struct zz_async_fs_glob {
  char *pattern;
  int flags;
  int (*errfunc) (const char *, int);
  glob_t *pglob;
  int rv;
};

void zz_async_fs_glob(struct zz_async_fs_glob *req) {
  req->rv = glob(req->pattern, req->flags, req->errfunc, req->pglob);
}

void *zz_async_fs_handlers[] = {
  zz_async_fs_open,
  zz_async_fs_read,
  zz_async_fs_write,
  zz_async_fs_lseek,
  zz_async_fs_close,
  zz_async_fs_futimens,
  zz_async_fs_access,
  zz_async_fs_chmod,
  zz_async_fs_unlink,
  zz_async_fs_mkdir,
  zz_async_fs_rmdir,
  zz_async_fs_symlink,
  zz_async_fs_readlink,
  zz_async_fs_realpath,
  zz_async_fs_stat,
  zz_async_fs_lstat,
  zz_async_fs_opendir,
  zz_async_fs_readdir,
  zz_async_fs_closedir,
  zz_async_fs_glob,
  0
};
