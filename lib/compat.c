/*
 * libdpkg - Debian packaging suite library routines
 * compat.c - compatibility functions
 *
 * Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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
#include <config.h>

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <stdarg.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include <dpkg.h>

#ifndef HAVE_VSNPRINTF
int vsnprintf (char *buf, size_t maxsize, const char *fmt, va_list al) {
  static FILE *file= NULL;

  struct stat stab;
  unsigned long want, nr;
  int retval;

  if (maxsize == 0) return -1;
  if (!file) {
    file= tmpfile(); if (!file) ohshite(_("unable to open tmpfile for vsnprintf"));
  } else {
    if (fseek(file,0,0)) ohshite(_("unable to rewind at start of vsnprintf"));
    if (ftruncate(fileno(file),0)) ohshite(_("unable to truncate in vsnprintf"));
  }
  if (vfprintf(file,fmt,al) == EOF) ohshite(_("write error in vsnprintf"));
  if (fflush(file)) ohshite(_("unable to flush in vsnprintf"));
  if (fstat(fileno(file),&stab)) ohshite(_("unable to stat in vsnprintf"));
  if (fseek(file,0,0)) ohshite(_("unable to rewind in vsnprintf"));
  want= stab.st_size;
  if (want >= maxsize) {
    want= maxsize-1; retval= -1;
  } else {
    retval= want;
  }
  nr= fread(buf,1,want-1,file);
  if (nr != want-1) ohshite(_("read error in vsnprintf truncated"));
  buf[want]= NULL;

  return retval;
}
#endif

#ifndef HAVE_SNPRINTF
int
snprintf (char *str, size_t n, char const *format, ...)
{
  va_list ap;
  int i;
  (void)n;
  va_start (ap, format);
  i = vsprintf (str, format, ap);
  va_end (ap);
  return i;
}
#endif

#ifndef HAVE_STRERROR
extern const char *const sys_errlist[];
extern const int sys_nerr;
const char *strerror(int e) {
  static char buf[100];
  if (e >= 0 && e < sys_nerr) return sys_errlist[e];
  sprintf(buf, _("System error no.%d"), e);
  return buf;
}
#endif

#ifndef HAVE_STRSIGNAL
extern const char *const sys_siglist[];
const char *strsignal(int e) {
  static char buf[100];
  if (e >= 0 && e < NSIG) return sys_siglist[e];
  sprintf(buf, _("Signal no.%d"), e);
  return buf;
}
#endif

#ifndef HAVE_DECL_SYS_SIGLIST
const char *const sys_siglist[32] = {
  "SIGHUP",      /*1*/
  "SIGINT",      /*2*/
  "SIGQUIT",     /*3*/
  "SIGILL",      /*4*/
  "SIGTRAP",     /*5*/
  "SIGABRT",     /*6*/
  "SIGEMT",      /*7*/
  "SIGFPE",      /*8*/
  "SIGKILL",     /*9*/
  "SIGUSR1",     /*10*/
  "SIGSEGV",     /*11*/
  "SIGUSR2",     /*12*/
  "SIGPIPE",     /*13*/
  "SIGALRM",     /*14*/
  "SIGTERM",     /*15*/
  "SIGSTKFLT",   /*16*/
  "SIGCHLD",     /*17*/
  "SIGCONT",     /*18*/
  "SIGSTOP",     /*19*/
  "SIGTSTP",     /*20*/
  "SIGTTIN",     /*21*/
  "SIGTTOU",     /*22*/
  "SIGXXX",      /*23*/
  "SIGXXX",      /*24*/
  "SIGXXX",      /*25*/
  "SIGXXX",      /*26*/
  "SIGXXX",      /*27*/
  "SIGXXX",      /*28*/
  "SIGXXX",      /*29*/
  "SIGXXX",      /*30*/
  "SIGXXX",      /*31*/
  "SIGXXX"       /*32*/
};
#endif

#ifndef HAVE_SCANDIR

static int (*scandir_comparfn)(const void*, const void*);
static int scandir_compar(const void *a, const void *b) {
  return scandir_comparfn(*(const struct dirent**)a,*(const struct dirent**)b);
}
      
int scandir(const char *dir, struct dirent ***namelist,
            int (*select)(const struct dirent *),
            int (*compar)(const void*, const void*)) {
  DIR *d;
  int used, avail;
  struct dirent *e, *m;
  d= opendir(dir);  if (!d) return -1;
  used=0; avail=20;
  *namelist= malloc(avail*sizeof(struct dirent*));
  if (!*namelist) return -1;
  while ((e= readdir(d)) != NULL) {
    if (!select(e)) continue;
    m= malloc(sizeof(struct dirent) + strlen(e->d_name));
    if (!m) return -1;
    *m= *e;
    strcpy(m->d_name,e->d_name);
    if (used >= avail-1) {
      avail+= avail;
      *namelist= realloc(*namelist, avail*sizeof(struct dirent*));
      if (!*namelist) return -1;
    }
    (*namelist)[used]= m;
    used++;
  }
  (*namelist)[used]= NULL;
  scandir_comparfn= compar;
  qsort(*namelist, used, sizeof(struct dirent*), scandir_compar);
  return used;
}
#endif

#ifndef HAVE_ALPHASORT
int alphasort(const struct dirent *a, const struct dirent *b) {
  return strcmp(a->d_name,b->d_name);
}
#endif

#ifndef HAVE_UNSETENV
void unsetenv(const char *p) {
  char *q;
  q= malloc(strlen(p)+3); if (!q) return;
  strcpy(q,p); strcat(q,"="); putenv(q);
}
#endif
