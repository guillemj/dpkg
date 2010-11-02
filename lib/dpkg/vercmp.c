/*
 * libdpkg - Debian packaging suite library routines
 * vercmp.c - comparison of version numbers
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

#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/parsedump.h>

bool
epochsdiffer(const struct versionrevision *a,
             const struct versionrevision *b)
{
  return a->epoch != b->epoch;
}

/**
 * Give a weight to the character to order in the version comparison.
 *
 * @param c An ASCII character.
 */
static int
order(int c)
{
  if (c == '~')
    return -1;
  else if (cisdigit(c))
    return 0;
  else if (!c)
    return 0;
  else if (cisalpha(c))
    return c;
  else
    return c + 256;
}

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

int versioncompare(const struct versionrevision *version,
                   const struct versionrevision *refversion) {
  int r;

  if (version->epoch > refversion->epoch) return 1;
  if (version->epoch < refversion->epoch) return -1;
  r= verrevcmp(version->version,refversion->version);  if (r) return r;
  return verrevcmp(version->revision,refversion->revision);
}

bool
versionsatisfied3(const struct versionrevision *it,
                  const struct versionrevision *ref,
                  enum depverrel verrel)
{
  int r;
  if (verrel == dvr_none)
    return true;
  r= versioncompare(it,ref);
  switch (verrel) {
  case dvr_earlierequal:   return r <= 0;
  case dvr_laterequal:     return r >= 0;
  case dvr_earlierstrict:  return r < 0;
  case dvr_laterstrict:    return r > 0;
  case dvr_exact:          return r == 0;
  default:
    internerr("unknown depverrel '%d'", verrel);
  }
  return false;
}

bool
versionsatisfied(struct pkginfoperfile *it, struct deppossi *against)
{
  return versionsatisfied3(&it->version,&against->version,against->verrel);
}
