/*
 * dpkg - main program for package management
 * select.c - by-hand (rather than dselect-based) package selection
 *
 * Copyright © 1995,1996 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2006,2008-2014 Guillem Jover <guillem@debian.org>
 * Copyright © 2011 Linaro Limited
 * Copyright © 2011 Raphaël Hertzog <hertzog@debian.org>
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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include <config.h>
#include <compat.h>

#include <fnmatch.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/pkg-array.h>
#include <dpkg/pkg-show.h>
#include <dpkg/pkg-spec.h>
#include <dpkg/options.h>

#include "filesdb.h"
#include "infodb.h"
#include "main.h"

static void getsel1package(struct pkginfo *pkg) {
  const char *pkgname;
  int l;

  if (pkg->want == PKG_WANT_UNKNOWN)
    return;
  pkgname = pkg_name(pkg, pnaw_nonambig);
  l = strlen(pkgname);
  l >>= 3;
  l = 6 - l;
  if (l < 1)
    l = 1;
  printf("%s%.*s%s\n", pkgname, l, "\t\t\t\t\t\t", pkg_want_name(pkg));
}

int
getselections(const char *const *argv)
{
  struct pkg_array array;
  struct pkginfo *pkg;
  const char *thisarg;
  int i, found;

  modstatdb_open(msdbrw_readonly);

  pkg_array_init_from_db(&array);
  pkg_array_sort(&array, pkg_sorter_by_nonambig_name_arch);

  if (!*argv) {
    for (i = 0; i < array.n_pkgs; i++) {
      pkg = array.pkgs[i];
      if (pkg->status == stat_notinstalled) continue;
      getsel1package(pkg);
    }
  } else {
    while ((thisarg= *argv++)) {
      struct pkg_spec pkgspec;

      found= 0;
      pkg_spec_init(&pkgspec, PKG_SPEC_PATTERNS | PKG_SPEC_ARCH_WILDCARD);
      pkg_spec_parse(&pkgspec, thisarg);

      for (i = 0; i < array.n_pkgs; i++) {
        pkg = array.pkgs[i];
        if (!pkg_spec_match_pkg(&pkgspec, pkg, &pkg->installed))
          continue;
        getsel1package(pkg); found++;
      }
      if (!found)
        notice(_("no packages found matching %s"), thisarg);

      pkg_spec_destroy(&pkgspec);
    }
  }

  m_output(stdout, _("<standard output>"));
  m_output(stderr, _("<standard error>"));

  pkg_array_destroy(&array);

  return 0;
}

int
setselections(const char *const *argv)
{
  const struct namevalue *nv;
  struct pkginfo *pkg;
  int c, lno;
  struct varbuf namevb = VARBUF_INIT;
  struct varbuf selvb = VARBUF_INIT;
  bool db_possibly_outdated = false;

  if (*argv)
    badusage(_("--%s takes no arguments"), cipaction->olong);

  modstatdb_open(msdbrw_write | msdbrw_available_readonly);
  pkg_infodb_upgrade();

  lno= 1;
  for (;;) {
    struct dpkg_error err;

    do { c= getchar(); if (c == '\n') lno++; } while (c != EOF && isspace(c));
    if (c == EOF) break;
    if (c == '#') {
      do { c= getchar(); if (c == '\n') lno++; } while (c != EOF && c != '\n');
      continue;
    }

    varbuf_reset(&namevb);
    while (!isspace(c)) {
      varbuf_add_char(&namevb, c);
      c= getchar();
      if (c == EOF) ohshit(_("unexpected eof in package name at line %d"),lno);
      if (c == '\n') ohshit(_("unexpected end of line in package name at line %d"),lno);
    }
    varbuf_end_str(&namevb);

    while (c != EOF && isspace(c)) {
      c= getchar();
      if (c == EOF) ohshit(_("unexpected eof after package name at line %d"),lno);
      if (c == '\n') ohshit(_("unexpected end of line after package name at line %d"),lno);
    }

    varbuf_reset(&selvb);
    while (c != EOF && !isspace(c)) {
      varbuf_add_char(&selvb, c);
      c= getchar();
    }
    varbuf_end_str(&selvb);

    while (c != EOF && c != '\n') {
      c= getchar();
      if (!isspace(c))
        ohshit(_("unexpected data after package and selection at line %d"),lno);
    }
    pkg = pkg_spec_parse_pkg(namevb.buf, &err);
    if (pkg == NULL)
      ohshit(_("illegal package name at line %d: %.250s"), lno, err.str);

    if (!pkg_is_informative(pkg, &pkg->installed) &&
        !pkg_is_informative(pkg, &pkg->available)) {
      db_possibly_outdated = true;
      warning(_("package not in database at line %d: %.250s"), lno, namevb.buf);
      continue;
    }

    nv = namevalue_find_by_name(wantinfos, selvb.buf);
    if (nv == NULL)
      ohshit(_("unknown wanted status at line %d: %.250s"), lno, selvb.buf);

    pkg_set_want(pkg, nv->value);
    if (c == EOF) break;
    lno++;
  }
  if (ferror(stdin)) ohshite(_("read error on standard input"));
  modstatdb_shutdown();
  varbuf_destroy(&namevb);
  varbuf_destroy(&selvb);

  if (db_possibly_outdated)
    warning(_("found unknown packages; this might mean the available database\n"
              "is outdated, and needs to be updated through a frontend method"));

  return 0;
}

int
clearselections(const char *const *argv)
{
  struct pkgiterator *it;
  struct pkginfo *pkg;

  if (*argv)
    badusage(_("--%s takes no arguments"), cipaction->olong);

  modstatdb_open(msdbrw_write);
  pkg_infodb_upgrade();

  it = pkg_db_iter_new();
  while ((pkg = pkg_db_iter_next_pkg(it))) {
    if (!pkg->installed.essential)
      pkg_set_want(pkg, PKG_WANT_DEINSTALL);
  }
  pkg_db_iter_free(it);

  modstatdb_shutdown();

  return 0;
}

