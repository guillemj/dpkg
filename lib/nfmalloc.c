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

#include <obstack.h>

#define obstack_chunk_alloc m_malloc
#define obstack_chunk_free free
#define ALIGN_BOUNDARY 64
#define ALIGN_MASK (ALIGN_BOUNDARY - 1)

static struct obstack db_obs;
static int dbobs_init = 0;

#ifdef HAVE_INLINE
inline void *nfmalloc(size_t size)
#else
void *nfmalloc(size_t size)
#endif
{
  if (!dbobs_init) { obstack_init(&db_obs); dbobs_init = 1; }
    return obstack_alloc(&db_obs, size);
}

char *nfstrsave(const char *string) {
  int i = strlen(string) + 1;
  char *r = nfmalloc(i);
  memcpy(r, string, i);
  return r;
}

char *nfstrnsave(const char *string, int l) {
  char *r = nfmalloc(l+1);
  memcpy(r, string, l);
  r[l] = '\0';
  return r;
}

void nffreeall(void) {
  obstack_free(&db_obs, 0);
}
