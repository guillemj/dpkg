/*
 * libdpkg - Debian packaging suite library routines
 * vercmp.c - comparison of version numbers
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

#include <ctype.h>
#include <string.h>

#include "config.h"
#include "dpkg.h"
#include "dpkg-db.h"
#include "parsedump.h"

int epochsdiffer(const struct versionrevision *a,
                 const struct versionrevision *b) {
  return a->epoch != b->epoch;
}

static int verrevcmp(const char *val, const char *ref) {
  int vc, rc;
  long vl, rl;
  const char *vp, *rp;

  if (!val) val= "";
  if (!ref) ref= "";
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
    vl=0;  if (isdigit(*vp)) vl= strtol(val,(char**)&val,10);
    rl=0;  if (isdigit(*rp)) rl= strtol(ref,(char**)&ref,10);
    if (vl != rl) return vl - rl;
    if (!*val && !*ref) return 0;
    if (!*val) return -1;
    if (!*ref) return +1;
  }
}

int versioncompare(const struct versionrevision *version,
                   const struct versionrevision *refversion) {
  int r;

  if (version->epoch > refversion->epoch) return 1;
  if (version->epoch < refversion->epoch) return 1;
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
}

int versionsatisfied(struct pkginfoperfile *it, struct deppossi *against) {
  return versionsatisfied3(&it->version,&against->version,against->verrel);
}
