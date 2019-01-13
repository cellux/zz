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

union zz_async_fs_req {
  struct {
    char *file;
    int oflag;
    mode_t mode;
    int rv;
  } open;

  struct {
    int fd;
    void *buf;
    size_t count;
    ssize_t nbytes;
  } read, write;

  struct {
    int fd;
    off_t offset;
    int whence;
    off_t rv;
  } lseek;

  struct {
    int fd;
    int rv;
  } close;

  struct {
    int fd;
    struct timespec *times;
    int rv;
  } futimens;

  struct {
    char *path;
    int how;
    int rv;
  } access;

  struct {
    char *file;
    mode_t mode;
    int rv;
  } chmod;

  struct {
    char *filename;
    int rv;
  } unlink;

  struct {
    char *file;
    mode_t mode;
    int rv;
  } mkdir, rmdir;

  struct {
    char *oldname;
    char *newname;
    int rv;
  } symlink;

  struct {
    char *filename;
    char *buffer;
    size_t size;
    ssize_t rv;
  } readlink;

  struct {
    char *name;
    char *resolved;
    char *rv;
  } realpath;

  struct {
    char *path;
    struct stat *buf;
    int rv;
  } stat;

  struct {
    char *path;
    DIR *dir;
    struct dirent *dirent;
    int rv;
  } opendir, readdir, closedir;

  struct {
    char *pattern;
    int flags;
    int (*errfunc) (const char *, int);
    glob_t *pglob;
    int rv;
  } glob;
};

void zz_async_fs_open(union zz_async_fs_req *req) {
  req->open.rv = open(req->open.file, req->open.oflag, req->open.mode);
}

void zz_async_fs_read(union zz_async_fs_req *req) {
  req->read.nbytes = read(req->read.fd, req->read.buf, req->read.count);
}

void zz_async_fs_write(union zz_async_fs_req *req) {
  req->write.nbytes = write(req->write.fd, req->write.buf, req->write.count);
}

void zz_async_fs_lseek(union zz_async_fs_req *req) {
  req->lseek.rv = lseek(req->lseek.fd, req->lseek.offset, req->lseek.whence);
}

void zz_async_fs_close(union zz_async_fs_req *req) {
  req->close.rv = close(req->close.fd);
}

void zz_async_fs_futimens(union zz_async_fs_req *req) {
  req->futimens.rv = futimens(req->futimens.fd, req->futimens.times);
}

void zz_async_fs_access(union zz_async_fs_req *req) {
  req->access.rv = access(req->access.path, req->access.how);
}

void zz_async_fs_chmod(union zz_async_fs_req *req) {
  req->chmod.rv = chmod(req->chmod.file, req->chmod.mode);
}

void zz_async_fs_unlink(union zz_async_fs_req *req) {
  req->unlink.rv = unlink(req->unlink.filename);
}

void zz_async_fs_mkdir(union zz_async_fs_req *req) {
  req->mkdir.rv = mkdir(req->mkdir.file, req->mkdir.mode);
}

void zz_async_fs_rmdir(union zz_async_fs_req *req) {
  req->rmdir.rv = rmdir(req->rmdir.file);
}

void zz_async_fs_symlink(union zz_async_fs_req *req) {
  req->symlink.rv = symlink(req->symlink.oldname, req->symlink.newname);
}

void zz_async_fs_readlink(union zz_async_fs_req *req) {
  req->readlink.rv = readlink(req->readlink.filename, req->readlink.buffer, req->readlink.size);
}

void zz_async_fs_realpath(union zz_async_fs_req *req) {
  req->realpath.rv = realpath(req->realpath.name, req->realpath.resolved);
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

void zz_async_fs_stat(union zz_async_fs_req *req) {
  req->stat.rv = stat(req->stat.path, req->stat.buf);
}

void zz_async_fs_lstat(union zz_async_fs_req *req) {
  req->stat.rv = lstat(req->stat.path, req->stat.buf);
}

void zz_async_fs_opendir(union zz_async_fs_req *req) {
  req->opendir.dir = opendir(req->opendir.path);
}

void zz_async_fs_readdir(union zz_async_fs_req *req) {
  req->readdir.dirent = readdir(req->readdir.dir);
}

void zz_async_fs_closedir(union zz_async_fs_req *req) {
  req->closedir.rv = closedir(req->closedir.dir);
}

void zz_async_fs_glob(union zz_async_fs_req *req) {
  req->glob.rv = glob(req->glob.pattern, req->glob.flags, req->glob.errfunc, req->glob.pglob);
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
