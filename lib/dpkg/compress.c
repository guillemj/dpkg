/*
 * libdpkg - Debian packaging suite library routines
 * compress.c - compression support functions
 *
 * Copyright © 2000 Wichert Akkerman <wakkerma@debian.org>
 * Copyright © 2004 Scott James Remnant <scott@netsplit.com>
 * Copyright © 2006-2009 Guillem Jover <guillem@debian.org>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <config.h>
#include <compat.h>

#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

#ifdef WITH_ZLIB
#include <zlib.h>
#endif
#ifdef WITH_BZ2
#include <bzlib.h>
#endif

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/varbuf.h>
#include <dpkg/buffer.h>
#include <dpkg/compress.h>

static void
fd_fd_filter(int fd_in, int fd_out,
	     const char *file, const char *cmd, const char *args,
	     const char *desc)
{
  if (fd_in != 0) {
    m_dup2(fd_in, 0);
    close(fd_in);
  }
  if (fd_out != 1) {
    m_dup2(fd_out, 1);
    close(fd_out);
  }
  execlp(file, cmd, args, NULL);
  ohshite(_("%s: failed to exec '%s %s'"), desc, cmd, args);
}

void
decompress_cat(enum compress_type type, int fd_in, int fd_out,
               const char *desc, ...)
{
  va_list al;
  struct varbuf v = VARBUF_INIT;

  va_start(al,desc);
  varbufvprintf(&v, desc, al);
  va_end(al);

  switch(type) {
    case compress_type_gzip:
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
      fd_fd_filter(fd_in, fd_out, GZIP, "gzip", "-dc", v.buf);
#endif
    case compress_type_bzip2:
#ifdef WITH_BZ2
      {   
        char buffer[4096];
        int actualread;
        BZFILE *bzfile = BZ2_bzdopen(fd_in, "r");
        while ((actualread= BZ2_bzread(bzfile,buffer,sizeof(buffer))) > 0) {
          if (actualread < 0 ) {
            int err = 0;
            const char *errmsg = BZ2_bzerror(bzfile, &err);
            if (err == BZ_IO_ERROR) {
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
      fd_fd_filter(fd_in, fd_out, BZIP2, "bzip2", "-dc", v.buf);
#endif
    case compress_type_lzma:
      fd_fd_filter(fd_in, fd_out, LZMA, "lzma", "-dc", v.buf);
    case compress_type_cat:
      fd_fd_copy(fd_in, fd_out, -1, _("%s: decompression"), v.buf);
      exit(0);
    default:
      exit(1);
  }
}

void
compress_cat(enum compress_type type, int fd_in, int fd_out,
             const char *compression, const char *desc, ...)
{
  va_list al;
  struct varbuf v = VARBUF_INIT;
  char combuf[6];

  va_start(al,desc);
  varbufvprintf(&v, desc, al);
  va_end(al);

  if(compression == NULL) compression= "9";
  else if (*compression == '0')
    type = compress_type_cat;

  switch(type) {
    case compress_type_gzip:
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
      strncpy(combuf, "-9c", sizeof(combuf));
      combuf[1]= *compression;
      fd_fd_filter(fd_in, fd_out, GZIP, "gzip", combuf, v.buf);
#endif
    case compress_type_bzip2:
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
      strncpy(combuf, "-9c", sizeof(combuf));
      combuf[1]= *compression;
      fd_fd_filter(fd_in, fd_out, BZIP2, "bzip2", combuf, v.buf);
#endif
    case compress_type_lzma:
      strncpy(combuf, "-9c", sizeof(combuf));
      combuf[1] = *compression;
      fd_fd_filter(fd_in, fd_out, LZMA, "lzma", combuf, v.buf);
    case compress_type_cat:
      fd_fd_copy(fd_in, fd_out, -1, _("%s: compression"), v.buf);
      exit(0);
    default:
      exit(1);
  }
}
