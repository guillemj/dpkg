/*
 * libdpkg - Debian packaging suite library routines
 * dpkg-db.h - Low level package database routines (hash tables, etc.)
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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

#include <ctype.h>
#include <string.h>
#include <stdlib.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

/* This must always be a prime for optimal performance.
 * With 4093 buckets, we glean a 20% speedup, for 8191 buckets
 * we get 23%. The nominal increase in memory usage is a mere
 * sizeof(void *) * 8063 (i.e. less than 32 KiB on 32bit systems). */
#define BINS 8191

static struct pkginfo *bins[BINS];
static int npackages;

#define FNV_offset_basis 2166136261ul
#define FNV_mixing_prime 16777619ul

/**
 * Fowler/Noll/Vo -- simple string hash.
 *
 * For more info, see <http://www.isthe.com/chongo/tech/comp/fnv/index.html>.
 */
static unsigned int hash(const char *name) {
  register unsigned int h = FNV_offset_basis;
  register unsigned int p = FNV_mixing_prime;
  while( *name ) {
    h *= p;
    h ^= *name++;
  }
  return h;
}

struct pkginfo *
pkg_db_find(const char *inname)
{
  struct pkginfo **pointerp, *newpkg;
  char *name = m_strdup(inname), *p;

  p= name;
  while(*p) { *p= tolower(*p); p++; }

  pointerp= bins + (hash(name) % (BINS));
  while (*pointerp && strcasecmp((*pointerp)->name,name))
    pointerp= &(*pointerp)->next;
  if (*pointerp) { free(name); return *pointerp; }

  newpkg= nfmalloc(sizeof(struct pkginfo));
  pkg_blank(newpkg);
  newpkg->name= nfstrsave(name);
  newpkg->next= NULL;
  *pointerp= newpkg;
  npackages++;

  free(name);
  return newpkg;
}

int
pkg_db_count(void)
{
  return npackages;
}

struct pkgiterator {
  struct pkginfo *pigp;
  int nbinn;
};

struct pkgiterator *
pkg_db_iter_new(void)
{
  struct pkgiterator *i;
  i= m_malloc(sizeof(struct pkgiterator));
  i->pigp= NULL;
  i->nbinn= 0;
  return i;
}

struct pkginfo *
pkg_db_iter_next(struct pkgiterator *i)
{
  struct pkginfo *r;
  while (!i->pigp) {
    if (i->nbinn >= BINS) return NULL;
    i->pigp= bins[i->nbinn++];
  }
  r= i->pigp; i->pigp= r->next; return r;
}

void
pkg_db_iter_free(struct pkgiterator *i)
{
  free(i);
}

void
pkg_db_reset(void)
{
  int i;
  nffreeall();
  npackages= 0;
  for (i=0; i<BINS; i++) bins[i]= NULL;
}

void hashreport(FILE *file) {
  int i, c;
  struct pkginfo *pkg;
  int *freq;

  freq= m_malloc(sizeof(int)*npackages+1);
  for (i=0; i<=npackages; i++) freq[i]= 0;
  for (i=0; i<BINS; i++) {
    for (c=0, pkg= bins[i]; pkg; c++, pkg= pkg->next);
    fprintf(file,"bin %5d has %7d\n",i,c);
    freq[c]++;
  }
  for (i=npackages; i>0 && freq[i]==0; i--);
  while (i >= 0) {
    fprintf(file, "size %7d occurs %5d times\n", i, freq[i]);
    i--;
  }

  m_output(file, "<hash report>");

  free(freq);
}
