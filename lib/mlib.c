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

typedef struct do_fd_copy_data {
  int fd;
} do_fd_copy_data_t;
typedef struct do_fd_buf_data {
  void *buf;
  int type;
} do_fd_buf_data_t;

void do_fd_write_combined(char *buf, int length, void *proc_data, char *desc) {
  do_fd_buf_data_t *data = (do_fd_buf_data_t *)proc_data;
  switch(data->type) {
    case FD_WRITE_BUF:
      memcpy(data->buf, buf, length);
      data->buf += length;
      break;
    case FD_WRITE_VBUF:
      varbufaddbuf((struct varbuf *)data->buf, buf, length);
      data->buf += length;
      break;
    case FD_WRITE_FD:
      if(write((int)data->buf, buf, length) < length)
	ohshite(_("failed in do_fd_write_combined (%i, %s)"), FD_WRITE_FD, desc);
      break;
    default:
      fprintf(stderr, _("unknown data type `%i' in do_fd_write_buf\n"), data->type);
   }
}

int read_fd_combined(int fd, void *buf, int type, int limit, char *desc, ...) {
  do_fd_buf_data_t data = { buf, type };
  va_list al;
  struct varbuf v;

  varbufinit(&v);

  va_start(al,desc);
  varbufvprintf(&v, desc, al);
  va_end(al);

  do_fd_read(fd, limit, do_fd_write_combined, &data, v.buf);
  varbuffree(&v);
}


int do_fd_read(int fd1, int limit, do_fd_write_t write_proc, void *proc_data, char *desc) {
  char *buf;
  int count, bufsize= 32768, bytesread= 0;

  if((limit != -1) && (limit < bufsize)) bufsize= limit;
  buf= malloc(bufsize);
  if(buf== NULL) ohshite(_("failed to allocate buffer in do_fd_read (%s)"), desc);

  while(1) {
    count= read(fd1, buf, bufsize);
    if (count<0) {
      if (errno==EINTR) continue;
      break;
    }
    if (count==0)
      break;

    bytesread+= count;
    write_proc(buf, count, proc_data, desc);
    if(limit!=-1) {
      limit-= count;
      if(limit<bufsize)
	bufsize=limit;
    }
  }
  if (count<0) ohshite(_("failed in do_fd_read on read (%s)"), desc);

  free(buf);
}
