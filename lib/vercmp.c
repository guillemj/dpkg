/*
 * libdpkg - Debian packaging suite library routines
 * vercmp.c - comparison of version numbers
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

#include <ctype.h>
#include <string.h>

#include <dpkg.h>
#include <dpkg-db.h>
#include "parsedump.h"

int epochsdiffer(const struct versionrevision *a,
                 const struct versionrevision *b) {
  return a->epoch != b->epoch;
}

/* assume ascii; warning: evaluates x multiple times! */
#define order(x) ((x) == '~' ? -1 \
		: cisdigit((x)) ? 0 \
		: !(x) ? 0 \
		: cisalpha((x)) ? (x) \
		: (x) + 256)

static int verrevcmp(const char *val, const char *ref) {
  if (!val) val= "";
  if (!ref) ref= "";

  while (*val || *ref) {
    int first_diff= 0;

    while ( (*val && !cisdigit(*val)) || (*ref && !cisdigit(*ref)) ) {
      int vc= order(*val), rc= order(*ref);
      if (vc != rc) return vc - rc;
      val++; ref++;
    }

    while ( *val == '0' ) val++;
    while ( *ref == '0' ) ref++;
    while (cisdigit(*val) && cisdigit(*ref)) {
      if (!first_diff) first_diff= *val - *ref;
      val++; ref++;
    }
    if (cisdigit(*val)) return 1;
    if (cisdigit(*ref)) return -1;
    if (first_diff) return first_diff;
  }
  return 0;
}


#if 0
static int verrevcmp(const char *ival, const char *iref) {
  static char empty[] = "";
  int vc, rc;
  long vl, rl;
  char *vp, *rp;
  char *val, *ref;
  memcpy(&val,&ival,sizeof(char*));
  memcpy(&ref,&iref,sizeof(char*));

  if (!val) val= empty;
  if (!ref) ref= empty;
  for (;;) {
    vp= val;  while (*vp && !isdigit(*vp)) vp++;
    rp= ref;  while (*rp && !isdigit(*rp)) rp++;
    for (;;) {
      vc= val == vp ? 0 : *val++;
      rc= ref == rp ? 0 : *ref++;
      if (!rc && !vc) break;
      if (vc && !isalpha(vc)) vc += 256; /* assumes ASCII character set */
      if (rc && !isalpha(rc)) rc += 256;
      if (vc != rc) return vc - rc;
    }
    val= vp;
    ref= rp;
    vl=0;  if (isdigit(*vp)) vl= strtol(val,&val,10);
    rl=0;  if (isdigit(*rp)) rl= strtol(ref,&ref,10);
    if (vl != rl) return vl - rl;
    if (!*val && !*ref) return 0;
    if (!*val) return -1;
    if (!*ref) return +1;
  }
}
#endif

int versioncompare(const struct versionrevision *version,
                   const struct versionrevision *refversion) {
  int r;

  if (version->epoch > refversion->epoch) return 1;
  if (version->epoch < refversion->epoch) return -1;
  r= verrevcmp(version->version,refversion->version);  if (r) return r;
  return verrevcmp(version->revision,refversion->revision);
}

int versionsatisfied3(const struct versionrevision *it,
                      const struct versionrevision *ref,
                      enum depverrel verrel) {
  int r;
  if (verrel == dvr_none) return 1;
  r= versioncompare(it,ref);
  switch (verrel) {
  case dvr_earlierequal:   return r <= 0;
  case dvr_laterequal:     return r >= 0;
  case dvr_earlierstrict:  return r < 0;
  case dvr_laterstrict:    return r > 0;
  case dvr_exact:          return r == 0;
  default:                 internerr("unknown verrel");
  }
  return 0;
}

int versionsatisfied(struct pkginfoperfile *it, struct deppossi *against) {
  return versionsatisfied3(&it->version,&against->version,against->verrel);
}
