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

#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

/**
 * Give a weight to the character to order in the version comparison.
 *
 * @param c An ASCII character.
 */
static int
order(int c)
{
  if (cisdigit(c))
    return 0;
  else if (cisalpha(c))
    return c;
  else if (c == '~')
    return -1;
  else if (c)
    return c + 256;
  else
    return 0;
}

static int
verrevcmp(const char *a, const char *b)
{
  if (a == NULL)
    a = "";
  if (b == NULL)
    b = "";

  while (*a || *b) {
    int first_diff= 0;

    while ((*a && !cisdigit(*a)) || (*b && !cisdigit(*b))) {
      int ac = order(*a);
      int bc = order(*b);

      if (ac != bc)
        return ac - bc;

      a++;
      b++;
    }
    while (*a == '0')
      a++;
    while (*b == '0')
      b++;
    while (cisdigit(*a) && cisdigit(*b)) {
      if (!first_diff)
        first_diff = *a - *b;
      a++;
      b++;
    }

    if (cisdigit(*a))
      return 1;
    if (cisdigit(*b))
      return -1;
    if (first_diff) return first_diff;
  }
  return 0;
}

int
dpkg_version_compare(const struct dpkg_version *a,
                     const struct dpkg_version *b)
{
  int r;

  if (a->epoch > b->epoch)
    return 1;
  if (a->epoch < b->epoch)
    return -1;

  r = verrevcmp(a->version, b->version);
  if (r)
    return r;

  return verrevcmp(a->revision, b->revision);
}

bool
dpkg_version_relate(const struct dpkg_version *a,
                    enum dpkg_relation rel,
                    const struct dpkg_version *b)
{
  int r;

  if (rel == dpkg_relation_none)
    return true;

  r = dpkg_version_compare(a, b);

  switch (rel) {
  case dpkg_relation_eq:
    return r == 0;
  case dpkg_relation_lt:
    return r < 0;
  case dpkg_relation_le:
    return r <= 0;
  case dpkg_relation_gt:
    return r > 0;
  case dpkg_relation_ge:
    return r >= 0;
  default:
    internerr("unknown dpkg_relation %d", rel);
  }
  return false;
}
