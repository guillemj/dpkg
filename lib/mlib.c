/*
 * libdpkg - Debian packaging suite library routines
 * mlib.c - `must' library: routines will succeed or longjmp
 *
 * Copyright (C) 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 *
 * This is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2,
 * or (at your option) any later version.
 *
 * This is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with dpkg; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */
#include "config.h"

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/types.h>

#include <dpkg.h>
#include <dpkg-db.h>
#include <md5.h>

/* Incremented when we do some kind of generally necessary operation, so that
 * loops &c know to quit if we take an error exit.  Decremented again afterwards.
 */
volatile int onerr_abort= 0;

void *m_malloc(size_t amount) {
#ifdef MDEBUG
  unsigned short *r2, x;
#endif
  void *r;
  
  onerr_abort++;
  r= malloc(amount);
  if (!r) ohshite(_("malloc failed (%ld bytes)"),(long)amount);
  onerr_abort--;
  
#ifdef MDEBUG
  r2= r; x= (unsigned short)amount ^ 0xf000;
  while (amount >= 2) { *r2++= x; amount -= 2; }
#endif
  return r;
}

void *m_realloc(void *r, size_t amount) {
  onerr_abort++;
  r= realloc(r,amount);
  if (!r) ohshite(_("realloc failed (%ld bytes)"),(long)amount);
  onerr_abort--;

  return r;
}

static void print_error_forked(const char *emsg, const char *contextstring) {
  fprintf(stderr, _("%s (subprocess): %s\n"), thisname, emsg);
}

static void cu_m_fork(int argc, void **argv) NONRETURNING;
static void cu_m_fork(int argc, void **argv) {
  exit(2);
  /* Don't do the other cleanups, because they'll be done by/in the parent
   * process.
   */
}

int m_fork(void) {
  pid_t r;
  r= fork();
  if (r == -1) { onerr_abort++; ohshite(_("fork failed")); }
  if (r > 0) return r;
  push_cleanup(cu_m_fork,~0, NULL,0, 0);
  set_error_display(print_error_forked,NULL);
  return r;
}

void m_dup2(int oldfd, int newfd) {
  const char *const stdstrings[]= { "in", "out", "err" };
  
  if (dup2(oldfd,newfd) == newfd) return;

  onerr_abort++;
  if (newfd < 3) ohshite(_("failed to dup for std%s"),stdstrings[newfd]);
  ohshite(_("failed to dup for fd %d"),newfd);
}

void m_pipe(int *fds) {
  if (!pipe(fds)) return;
  onerr_abort++;
  ohshite(_("failed to create pipe"));
}

int checksubprocerr(int status, const char *description, int flags) {
  int n;
  if (WIFEXITED(status)) {
    n= WEXITSTATUS(status); if (!n) return n;
    if(!(flags & PROCNOERR)) {
      if(flags & PROCWARN)
        fprintf(stderr, _("dpkg: warning - %s returned error exit status %d\n"),description,n);
      else
        ohshit(_("subprocess %s returned error exit status %d"),description,n);
    }
  } else if (WIFSIGNALED(status)) {
    n= WTERMSIG(status); if (!n || ((flags & PROCPIPE) && n==SIGPIPE)) return 0;
    if (flags & PROCWARN)
      ohshit(_("dpkg: warning - %s killed by signal (%s)%s\n"),
           description, strsignal(n), WCOREDUMP(status) ? ", core dumped" : "");
    else
      ohshit(_("subprocess %s killed by signal (%s)%s"),
           description, strsignal(n), WCOREDUMP(status) ? ", core dumped" : "");
  } else {
    ohshit(_("subprocess %s failed with wait status code %d"),description,status);
  }
  return -1;
}

int waitsubproc(pid_t pid, const char *description, int flags) {
  pid_t r;
  int status;

  while ((r= waitpid(pid,&status,0)) == -1 && errno == EINTR);
  if (r != pid) { onerr_abort++; ohshite(_("wait for %s failed"),description); }
  return checksubprocerr(status,description,flags);
}

void setcloexec(int fd, const char* fn) {
  int f;

  if ((f=fcntl(fd, F_GETFD))==-1)
    ohshite(_("unable to read filedescriptor flags for %.250s"),fn);
  if (fcntl(fd, F_SETFD, (f|FD_CLOEXEC))==-1)
    ohshite(_("unable to set close-on-exec flag for %.250s"),fn);
}

struct buffer_write_md5ctx {
  struct MD5Context ctx;
  unsigned char **hash;
};
off_t buffer_write(buffer_data_t data, void *buf, off_t length, const char *desc) {
  off_t ret= length;
  if(data->type & BUFFER_WRITE_SETUP) {
    switch(data->type ^ BUFFER_WRITE_SETUP) {
      case BUFFER_WRITE_MD5:
	{
	  struct buffer_write_md5ctx *ctx = malloc(sizeof(struct buffer_write_md5ctx));
	  ctx->hash = data->data.ptr;
	  data->data.ptr = ctx;
	  MD5Init(&ctx->ctx);
	}
	break;
    }
    return 0;
  }
  if(data->type & BUFFER_WRITE_SHUTDOWN) {
    switch(data->type ^ BUFFER_WRITE_SHUTDOWN) {
      case BUFFER_WRITE_MD5:
	{
	  int i;
	  unsigned char digest[16], *p = digest;
	  struct buffer_write_md5ctx *ctx = (struct buffer_write_md5ctx *)data->data.ptr;
	  unsigned char *hash = *ctx->hash = malloc(33);
	  MD5Final(digest, &ctx->ctx);
	  for (i = 0; i < 16; ++i) {
	    sprintf((char *)hash, "%02x", *p++);
	    hash += 2;
	  }
	  *hash = 0;
	  free(ctx);
	}
	break;
    }
    return 0;
  }
  switch(data->type) {
    case BUFFER_WRITE_BUF:
      memcpy(data->data.ptr, buf, length);
      data->data.ptr += length;
      break;
    case BUFFER_WRITE_VBUF:
      varbufaddbuf((struct varbuf *)data->data.ptr, buf, length);
      break;
    case BUFFER_WRITE_FD:
      if((ret= write(data->data.i, buf, length)) < 0 && errno != EINTR)
	ohshite(_("failed in buffer_write(fd) (%i, ret=%li): %s"), data->data.i, (long)ret, desc);
      break;
    case BUFFER_WRITE_NULL:
      break;
    case BUFFER_WRITE_STREAM:
      ret= fwrite(buf, 1, length, (FILE *)data->data.ptr);
      if(feof((FILE *)data->data.ptr))
	ohshite(_("eof in buffer_write(stream): %s"), desc);
      if(ferror((FILE *)data->data.ptr))
	ohshite(_("error in buffer_write(stream): %s"), desc);
      break;
    case BUFFER_WRITE_MD5:
      MD5Update(&(((struct buffer_write_md5ctx *)data->data.ptr)->ctx), buf, length);
      break;
    default:
      fprintf(stderr, _("unknown data type `%i' in buffer_write\n"), data->type);
   }
   return ret;
}

off_t buffer_read(buffer_data_t data, void *buf, off_t length, const char *desc) {
  off_t ret= length;
  if(data->type & BUFFER_READ_SETUP) {
    return 0;
  }
  if(data->type & BUFFER_READ_SHUTDOWN) {
    return 0;
  }
  switch(data->type) {
    case BUFFER_READ_FD:
      if((ret= read(data->data.i, buf, length)) < 0 && errno != EINTR)
	ohshite(_("failed in buffer_read(fd): %s"), desc);
      break;
    case BUFFER_READ_STREAM:
      ret= fread(buf, 1, length, (FILE *)data->data.ptr);
      if(feof((FILE *)data->data.ptr))
	return ret;
      if(ferror((FILE *)data->data.ptr))
	ohshite(_("error in buffer_read(stream): %s"), desc);
      break;
    default:
      fprintf(stderr, _("unknown data type `%i' in buffer_read\n"), data->type);
   }
   return ret;
}

#define buffer_copy_setup_dual(name, type1, name1, type2, name2) \
off_t buffer_copy_setup_##name(type1 n1, int typeIn, void *procIn,\
					type2 n2, int typeOut, void *procOut,\
					off_t limit, const char *desc, ...)\
{\
  va_list al;\
  buffer_arg a1, a2;\
  struct varbuf v;\
  off_t ret;\
  a1.name1 = n1; a2.name2 = n2;\
  varbufinit(&v);\
  va_start(al,desc);\
  varbufvprintf(&v, desc, al);\
  va_end(al);\
  ret = buffer_copy_setup(a1, typeIn, procIn,\
			   a2, typeOut, procOut,\
			   limit, v.buf);\
  varbuffree(&v);\
  return ret;\
}

buffer_copy_setup_dual(IntInt, int, i, int, i);
buffer_copy_setup_dual(IntPtr, int, i, void *, ptr);
buffer_copy_setup_dual(PtrInt, void *, ptr, int, i);
buffer_copy_setup_dual(PtrPtr, void *, ptr, void *, ptr);

off_t buffer_copy_setup(buffer_arg argIn, int typeIn, void *procIn,
		       buffer_arg argOut, int typeOut, void *procOut,
		       off_t limit, const char *desc)
{
  struct buffer_data read_data = { procIn, argIn, typeIn },
		     write_data = { procOut, argOut, typeOut };
  off_t ret;

  if ( procIn == NULL )
    read_data.proc = buffer_read;
  if ( procOut == NULL )
    write_data.proc = buffer_write;
  read_data.type |= BUFFER_READ_SETUP;
  read_data.proc(&read_data, NULL, 0, desc);
  read_data.type = typeIn;
  write_data.type |= BUFFER_WRITE_SETUP;
  write_data.proc(&write_data, NULL, 0, desc);
  write_data.type = typeOut;
  ret = buffer_copy(&read_data, &write_data, limit, desc);
  write_data.type |= BUFFER_WRITE_SHUTDOWN;
  write_data.proc(&write_data, NULL, 0, desc);
  read_data.type |= BUFFER_READ_SHUTDOWN;
  read_data.proc(&read_data, NULL, 0, desc);
  return ret;
}

off_t buffer_copy(buffer_data_t read_data, buffer_data_t write_data, off_t limit, const char *desc) {
  char *buf, *writebuf;
  long bytesread= 0, byteswritten= 0;
  int bufsize= 32768;
  off_t totalread= 0, totalwritten= 0;
  if((limit!=-1) && (limit < bufsize)) bufsize= limit;
  if(bufsize == 0)
    return 0;
  writebuf= buf= malloc(bufsize);
  if(buf== NULL) ohshite(_("failed to allocate buffer in buffer_copy (%s)"), desc);

  while(bytesread >= 0 && byteswritten >= 0 && bufsize > 0) {
    bytesread= read_data->proc(read_data, buf, bufsize, desc);
    if (bytesread<0) {
      if (errno==EINTR || errno==EAGAIN) continue;
      break;
    }
    if (bytesread==0)
      break;

    totalread+= bytesread;
    if(limit != -1) {
      limit-= bytesread;
      if(limit<bufsize)
	bufsize=limit;
    }
    writebuf= buf;
    while(bytesread) {
      byteswritten= write_data->proc(write_data, writebuf, bytesread, desc);
      if(byteswritten == -1) {
	if(errno == EINTR || errno==EAGAIN) continue;
	break;
      }
      if(byteswritten==0)
	break;
      bytesread-= byteswritten;
      totalwritten+= byteswritten;
      writebuf+= byteswritten;
    }
  }
  if (bytesread<0 || byteswritten<0) ohshite(_("failed in buffer_copy (%s)"), desc);
  if (limit > 0) ohshit(_("short read in buffer_copy (%s)"), desc);

  free(buf);
  return totalread;
}
