/*
 * libdpkg - Debian packaging suite library routines
 * varbuf.c - variable length expandable buffer handling
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
#include <config.h>

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include <dpkg.h>
#include <dpkg-db.h>

inline void varbufaddc(struct varbuf *v, int c) {
  if (v->used >= v->size) varbufextend(v);
  v->buf[v->used++]= c;
}

void varbufdupc(struct varbuf *v, int c, ssize_t n) {
  char *b = v->buf + v->used;
  v->used += n;
  if (v->used >= v->size) varbufextend(v);
 
  while(n) {
    *b= c;
    b++; n--;
  }
}

int varbufprintf(struct varbuf *v, const char *fmt, ...) {
  unsigned int ou, r;
  va_list al;

  ou= v->used;
  v->used+= strlen(fmt);

  do {
    varbufextend(v);
    va_start(al,fmt);
    r= vsnprintf(v->buf+ou,v->size-ou,fmt,al);
    va_end(al);
    if (r < 0) r= (v->size-ou+1) * 2;
    v->used= ou+r;
  } while (r >= v->size-ou-1);
  return r;
}

int varbufvprintf(struct varbuf *v, const char *fmt, va_list va) {
  unsigned int ou, r;
  va_list al;

  ou= v->used;
  v->used+= strlen(fmt);

  do {
    varbufextend(v);
    va_copy(al, va);
    r= vsnprintf(v->buf+ou,v->size-ou,fmt,al);
    if (r < 0) r= (v->size-ou+1) * 2;
    v->used= ou+r;
  } while (r >= v->size-ou-1);
  return r;
}

void varbufaddbuf(struct varbuf *v, const void *s, const int l) {
  int ou;
  ou= v->used;
  v->used += l;
  if (v->used >= v->size) varbufextend(v);
  memcpy(v->buf + ou, s, l);
}

void varbufinit(struct varbuf *v) {
  /* NB: dbmodify.c does its own init to get a big buffer */
  v->size= v->used= 0;
  v->buf= NULL;
}

void varbufreset(struct varbuf *v) {
  v->used= 0;
}

void varbufextend(struct varbuf *v) {
  int newsize;
  char *newbuf;

  newsize= v->size + 80 + v->used;
  newbuf= realloc(v->buf,newsize);
  if (!newbuf) ohshite(_("failed to realloc for variable buffer"));
  v->size= newsize;
  v->buf= newbuf;
}

void varbuffree(struct varbuf *v) {
  free(v->buf); v->buf=NULL; v->size=0; v->used=0;
}
