/*
 * libdpkg - Debian packaging suite library routines
 * nfmalloc.c - non-freeing malloc, used for in-core database
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

#include <stdlib.h>
#include <string.h>

#include <config.h>
#include <dpkg.h>
#include <dpkg-db.h>

#define ABLOCKSIZE 65536
#define UNIQUE      4096

union maxalign {
  long l; long double d;
  void *pv; char *pc; union maxalign *ps; void (*pf)(void);
};

static unsigned char *playground= 0;
static long remaining= 0;
static struct piece { struct piece *next; union maxalign space; } *pieces= 0;

void nffreeall(void) {
  struct piece *a,*b;
  for (a=pieces; a; a=b) { b=a->next; free(a); }
  pieces= 0; remaining= 0;
}

static void *nfmalloc_sysmalloc(size_t size) {
  struct piece *alc;
  alc= m_malloc(size + sizeof(struct piece));
  alc->next= pieces; pieces= alc;
  return &alc->space;
}

#ifndef MDEBUG
void *nfmalloc(size_t size) {
#else
static void *nfmalloc_r(size_t size) {
#endif
  const size_t alignment= sizeof(union maxalign);

  size -= (size + alignment-1) % alignment;
  size += alignment-1;
  if (size > UNIQUE) return nfmalloc_sysmalloc(size);
  remaining -= size;
  if (remaining > 0) return playground -= size;
  playground= (unsigned char*)nfmalloc_sysmalloc(ABLOCKSIZE) + ABLOCKSIZE - size;
  remaining= ABLOCKSIZE-size;
  return playground;
}

#ifdef MDEBUG
/* If we haven't switched off debugging we wrap nfmalloc in something
 * that fills the space with junk that may tell us what happened if
 * we dereference a wild pointer.  It's better than leaving it full of
 * nulls, anyway.
 */
void *nfmalloc(size_t size) {
  unsigned short *r, *r2, x;
  r= nfmalloc_r(size); r2=r; x= (unsigned short)size;
  while (size >= 2) { *r2++= x; size -= 2; }
  return r;
}
#endif

char *nfstrsave(const char *string) {
  char *r;
  
  r= nfmalloc(strlen(string)+1);
  strcpy(r,string);
  return r;
}
