/*
 * libdpkg - Debian packaging suite library routines
 * compat.c - compatibility functions
 *
 * Copyright (C) 1995 Ian Jackson <iwj10@cus.cam.ac.uk>
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

#include "config.h"
#include "dpkg.h"

#ifndef HAVE_VSNPRINTF
int vsnprintf (char *buf, size_t maxsize, const char *fmt, va_list al) {
  static FILE *file= 0;

  struct stat stab;
  unsigned long want, nr;
  int retval;

  if (maxsize == 0) return -1;
  if (!file) {
    file= tmpfile(); if (!file) ohshite("unable to open tmpfile for vsnprintf");
  } else {
    if (fseek(file,0,0)) ohshite("unable to rewind at start of vsnprintf");
    if (ftruncate(fileno(file),0)) ohshite("unable to truncate in vsnprintf");
  }
  if (vfprintf(file,fmt,al) == EOF) ohshite("write error in vsnprintf");
  if (fflush(file)) ohshite("unable to flush in vsnprintf");
  if (fstat(fileno(file),&stab)) ohshite("unable to stat in vsnprintf");
  if (fseek(file,0,0)) ohshite("unable to rewind in vsnprintf");
  want= stab.st_size;
  if (want >= maxsize) {
    want= maxsize-1; retval= -1;
  } else {
    retval= want;
  }
  nr= fread(buf,1,want-1,file);
  if (nr != want-1) ohshite("read error in vsnprintf truncated");
  buf[want]= 0;

  return retval;
}
#endif

#ifndef HAVE_STRERROR
extern const char *const sys_errlist[];
extern const int sys_nerr;
const char *strerror(int e) {
  static char buf[100];
  if (e >= 0 && e < sys_nerr) return sys_errlist[e];
  sprintf(buf, "System error no.%d", e);
  return buf;
}
#endif

#ifndef HAVE_STRSIGNAL
extern const char *const sys_siglist[];
const char *strsignal(int e) {
  static char buf[100];
  if (e >= 0 && e < NSIG) return sys_siglist[e];
  sprintf(buf, "Signal no.%d", e);
  return buf;
}
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
  while ((e= readdir(d)) != 0) {
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
  (*namelist)[used]= 0;
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
