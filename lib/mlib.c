/*
 * libdpkg - Debian packaging suite library routines
 * mlib.c - `must' library: routines will succeed or longjmp
 *
 * Copyright (C) 1994,1995 Ian Jackson <iwj10@cus.cam.ac.uk>
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

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <errno.h>
#include <sys/wait.h>
#include <sys/types.h>

#include <config.h>
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
  push_cleanup(cu_m_fork,~0, 0,0, 0);
  set_error_display(print_error_forked,0);
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

void checksubprocerr(int status, const char *description, int sigpipeok) {
  int n;
  if (WIFEXITED(status)) {
    n= WEXITSTATUS(status); if (!n) return;
    ohshit(_("subprocess %s returned error exit status %d"),description,n);
  } else if (WIFSIGNALED(status)) {
    n= WTERMSIG(status); if (!n || (sigpipeok && n==SIGPIPE)) return;
    ohshit(_("subprocess %s killed by signal (%s)%s"),
           description, strsignal(n), WCOREDUMP(status) ? ", core dumped" : "");
  } else {
    ohshit(_("subprocess %s failed with wait status code %d"),description,status);
  }
}

void waitsubproc(pid_t pid, const char *description, int sigpipeok) {
  pid_t r;
  int status;

  while ((r= waitpid(pid,&status,0)) == -1 && errno == EINTR);
  if (r != pid) { onerr_abort++; ohshite(_("wait for %s failed"),description); }
  checksubprocerr(status,description,sigpipeok);
}

ssize_t buffer_write(buffer_data_t data, void *buf, ssize_t length, char *desc) {
  ssize_t ret= length;
  switch(data->type) {
    case BUFFER_WRITE_BUF:
      memcpy(data->data, buf, length);
      (char*)data->data += length;
      break;
    case BUFFER_WRITE_VBUF:
      varbufaddbuf((struct varbuf *)data->data, buf, length);
      break;
    case BUFFER_WRITE_FD:
      if((ret= write((int)data->data, buf, length)) < 0 && errno != EINTR)
	ohshite(_("failed in buffer_write(fd) (%i, ret=%i, %s)"), (int)data->data, ret, desc);
      break;
    case BUFFER_WRITE_NULL:
      break;
    case BUFFER_WRITE_STREAM:
      ret= fwrite(buf, 1, length, (FILE *)data->data);
      if(feof((FILE *)data->data))
	ohshite(_("eof in buffer_write(stream): %s"), desc);
      if(ferror((FILE *)data->data))
	ohshite(_("error in buffer_write(stream): %s"), desc);
      break;
    case BUFFER_WRITE_MD5:
      MD5Update((struct MD5Context *)data->data, buf, length);
      break;
    default:
      fprintf(stderr, _("unknown data type `%i' in buffer_write\n"), data->type);
   }
   return ret;
}

ssize_t buffer_read(buffer_data_t data, void *buf, ssize_t length, char *desc) {
  ssize_t ret= length;
  switch(data->type) {
    case BUFFER_READ_FD:
      if((ret= read((int)data->data, buf, length)) < 0 && errno != EINTR)
	ohshite(_("failed in buffer_read(fd): %s"), desc);
      break;
    case BUFFER_READ_STREAM:
      ret= fread(buf, 1, length, (FILE *)data->data);
      if(feof((FILE *)data->data))
	return ret;
      if(ferror((FILE *)data->data))
	ohshite(_("error in buffer_read(stream): %s"), desc);
      break;
    default:
      fprintf(stderr, _("unknown data type `%i' in buffer_read\n"), data->type);
   }
   return ret;
}

ssize_t buffer_copy_setup(void *argIn, int typeIn, void *procIn,
		       void *argOut, int typeOut, void *procOut,
		       ssize_t limit, const char *desc, ...)
{
  struct buffer_data read_data = { procIn, argIn, typeIn },
		     write_data = { procOut, argOut, typeOut };
  va_list al;
  struct varbuf v;
  ssize_t ret;

  varbufinit(&v);

  va_start(al,desc);
  varbufvprintf(&v, desc, al);
  va_end(al);

  if ( procIn == NULL )
    read_data.proc = buffer_read;
  if ( procOut == NULL )
    write_data.proc = buffer_write;
  ret = buffer_copy(&read_data, &write_data, limit, v.buf);
  varbuffree(&v);
  return ret;
}

ssize_t buffer_md5_setup(void *argIn, int typeIn, void *procIn,
		      unsigned char hash[33], ssize_t limit, const char *desc, ...)
{
  struct MD5Context ctx;
  struct buffer_data read_data = { procIn, argIn, typeIn },
		     write_data = { buffer_write, &ctx, BUFFER_WRITE_MD5 };
  va_list al;
  struct varbuf v;
  int ret, i;
  unsigned char digest[16], *p = digest;

  varbufinit(&v);

  va_start(al,desc);
  varbufvprintf(&v, desc, al);
  va_end(al);

  if ( procIn == NULL )
    read_data.proc = buffer_read;
  MD5Init(&ctx);
  ret = buffer_copy(&read_data, &write_data, limit, v.buf);
  MD5Final(digest, &ctx);
  for (i = 0; i < 16; ++i) {
    sprintf(hash, "%02x", *p++);
    hash += 2;
  }
  varbuffree(&v);
  return ret;
}


ssize_t buffer_copy(buffer_data_t read_data, buffer_data_t write_data, ssize_t limit, char *desc) {
  char *buf, *writebuf;
  long bytesread= 0, byteswritten= 0;
  int bufsize= 32768;
  ssize_t totalread= 0, totalwritten= 0;
  if((limit != -1) && (limit < bufsize)) bufsize= limit;
  writebuf= buf= malloc(bufsize);
  if(buf== NULL) ohshite(_("failed to allocate buffer in buffer_copy (%s)"), desc);

  while(bytesread >= 0 && byteswritten >= 0) {
    bytesread= read_data->proc(read_data, buf, bufsize, desc);
    if (bytesread<0) {
      if (errno==EINTR) continue;
      break;
    }
    if (bytesread==0)
      break;

    totalread+= bytesread;
    if(limit!=-1) {
      limit-= bytesread;
      if(limit<bufsize)
	bufsize=limit;
    }
    writebuf= buf;
    while(bytesread) {
      byteswritten= write_data->proc(write_data, writebuf, bytesread, desc);
      if(byteswritten == -1) {
	if(errno == EINTR) continue;
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

  free(buf);
  return totalread;
}
