#include <config.h>

#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

#ifdef WITH_ZLIB
#include <zlib.h>
#endif
#ifdef WITH_BZ2
#include <bzlib.h>
#endif

#include <dpkg.h>

#include "dpkg.h"
#include "dpkg-db.h"

void decompress_cat(enum compression_type type, int fd_in, int fd_out, char *desc, ...) {
  va_list al;
  struct varbuf v;

  varbufinit(&v);

  va_start(al,desc);
  varbufvprintf(&v, desc, al);
  va_end(al);

  switch(type) {
    case GZ:
#ifdef WITH_ZLIB
      {
        char buffer[4096];
        int actualread;
        gzFile gzfile = gzdopen(fd_in, "r");
        while ((actualread= gzread(gzfile,buffer,sizeof(buffer))) > 0) {
          if (actualread < 0 ) {
            int err = 0;
            const char *errmsg = gzerror(gzfile, &err);
            if (err == Z_ERRNO) {
              if (errno == EINTR) continue;
              errmsg= strerror(errno);
            }
          ohshite(_("%s: internal gzip error: `%s'"), v.buf, errmsg);
          }
          write(fd_out,buffer,actualread);
        }
      }
      exit(0);
#else
      if (fd_in != 0) {
        m_dup2(fd_in, 0);
        close(fd_in);
      }
      if (fd_out != 1) {
        m_dup2(fd_out, 1);
        close(fd_out);
      }
      execlp(GZIP,"gzip","-dc",(char*)0); ohshite(_("%s: failed to exec gzip -dc"), v.buf);
#endif
    case BZ2:
#ifdef WITH_BZ2
      {   
        char buffer[4096];
        int actualread;
        BZFILE *bzfile = BZ2_bzdopen(fd_in, "r");
        while ((actualread= BZ2_bzread(bzfile,buffer,sizeof(buffer))) > 0) {
          if (actualread < 0 ) {
            int err = 0;
            const char *errmsg = BZ2_bzerror(bzfile, &err);
            if (err == Z_ERRNO) {
              if (errno == EINTR) continue;
              errmsg= strerror(errno);
            }
          ohshite(_("%s: internal bzip2 error: `%s'"), v.buf, errmsg);
          }
          write(fd_out,buffer,actualread);
        }
      }
      exit(0);
#else
      if (fd_in != 0) {
        m_dup2(fd_in, 0);
        close(fd_in);
      }
      if (fd_out != 1) {
        m_dup2(fd_out, 1);
        close(fd_out);
      }
      execlp(BZIP2,"bzip2","-dc",(char*)0); ohshite(_("%s: failed to exec bzip2 -dc"), v.buf);
#endif
    case CAT:
      fd_fd_copy(fd_in, fd_out, -1, _("%s: decompression"), v.buf);
      exit(0);
    default:
      exit(1);
  }
}

void compress_cat(enum compression_type type, int fd_in, int fd_out, const char *compression, char *desc, ...) {
  va_list al;
  struct varbuf v;
  char combuf[6];

  varbufinit(&v);

  va_start(al,desc);
  varbufvprintf(&v, desc, al);
  va_end(al);

  if(compression == NULL) compression= "9";
  else if(*compression == '0') type = CAT;

  switch(type) {
    case GZ:
#ifdef WITH_ZLIB
      {
        int actualread, actualwrite;
        char buffer[4096];
        gzFile gzfile;
        strncpy(combuf, "w9", sizeof(combuf));
        combuf[1]= *compression;
        gzfile = gzdopen(1, combuf);
        while((actualread = read(0,buffer,sizeof(buffer))) > 0) {
          if (actualread < 0 ) {
            if (errno == EINTR) continue;
            ohshite(_("%s: internal gzip error: read: `%s'"), v.buf, strerror(errno));
          }
          actualwrite= gzwrite(gzfile,buffer,actualread);
          if (actualwrite < 0 ) {
            int err = 0;
            const char *errmsg = gzerror(gzfile, &err);
            if (err == Z_ERRNO) {
              if (errno == EINTR) continue;
            errmsg= strerror(errno);
            }
            ohshite(_("%s: internal gzip error: write: `%s'"), v.buf, errmsg);
          }
          if (actualwrite != actualread)
            ohshite(_("%s: internal gzip error: read(%i) != write(%i)"), v.buf, actualread, actualwrite);
        }
        gzclose(gzfile);
        exit(0);
      }
#else
      if (fd_in != 0) {
        m_dup2(fd_in, 0);
        close(fd_in);
      }
      if (fd_out != 1) {
        m_dup2(fd_out, 1);
        close(fd_out);
      }
      strncpy(combuf, "-9c", sizeof(combuf));
      combuf[1]= *compression;
      execlp(GZIP,"gzip",combuf,(char*)0); ohshit(_("%s: failed to exec gzip %s"), v.buf, combuf);
#endif
    case BZ2:
#ifdef WITH_BZ2
      {
        int actualread, actualwrite;
        char buffer[4096];
        BZFILE *bzfile;
        strncpy(combuf, "w9", sizeof(combuf));
        combuf[1]= *compression;
        bzfile = BZ2_bzdopen(1, combuf);
        while((actualread = read(0,buffer,sizeof(buffer))) > 0) {
          if (actualread < 0 ) {
            if (errno == EINTR) continue;
            ohshite(_("%s: internal bzip2 error: read: `%s'"), v.buf, strerror(errno));
          }
          actualwrite= BZ2_bzwrite(bzfile,buffer,actualread);
          if (actualwrite < 0 ) {
            int err = 0;
            const char *errmsg = BZ2_bzerror(bzfile, &err);
            if (err == BZ_IO_ERROR) {
              if (errno == EINTR) continue;
              errmsg= strerror(errno);
            }
            ohshite(_("%s: internal bzip2 error: write: `%s'"), v.buf, errmsg);
          }
          if (actualwrite != actualread)
            ohshite(_("%s: internal bzip2 error: read(%i) != write(%i)"), v.buf, actualread, actualwrite);
        }
        BZ2_bzclose(bzfile);
        exit(0);
      }
#else
      if (fd_in != 0) {
        m_dup2(fd_in, 0);
        close(fd_in);
      }
      if (fd_out != 1) {
        m_dup2(fd_out, 1);
        close(fd_out);
      }
      strncpy(combuf, "-9c", sizeof(combuf));
      combuf[1]= *compression;
      execlp(BZIP2,"bzip2",combuf,(char*)0); ohshit(_("%s: failed to exec bzip2 %s"), v.buf, combuf);
#endif
    case CAT:
      fd_fd_copy(fd_in, fd_out, -1, _("%s: compression"), v.buf);
      exit(0);
    default:
      exit(1);
  }
}
