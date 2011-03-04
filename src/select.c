/*
 * dpkg - main program for package management
 * select.c - by-hand (rather than dselect-based) package selection
 *
 * Copyright © 1995,1996 Ian Jackson <ian@chiark.greenend.org.uk>
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

#include <fnmatch.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/pkg-array.h>
#include <dpkg/myopt.h>

#include "filesdb.h"
#include "main.h"

static void getsel1package(struct pkginfo *pkg) {
  int l;

  if (pkg->want == want_unknown) return;
  l= strlen(pkg->name); l >>= 3; l= 6-l; if (l<1) l=1;
  printf("%s%.*s%s\n",pkg->name,l,"\t\t\t\t\t\t",wantinfos[pkg->want].name);
}

void getselections(const char *const *argv) {
  struct pkg_array array;
  struct pkginfo *pkg;
  const char *thisarg;
  int i, found;

  modstatdb_init(admindir, msdbrw_readonly);

  pkg_array_init_from_db(&array);
  pkg_array_sort(&array, pkg_sorter_by_name);

  if (!*argv) {
    for (i = 0; i < array.n_pkgs; i++) {
      pkg = array.pkgs[i];
      if (pkg->status == stat_notinstalled) continue;
      getsel1package(pkg);
    }
  } else {
    while ((thisarg= *argv++)) {
      found= 0;
      for (i = 0; i < array.n_pkgs; i++) {
        pkg = array.pkgs[i];
        if (fnmatch(thisarg,pkg->name,0)) continue;
        getsel1package(pkg); found++;
      }
      if (!found)
        fprintf(stderr,_("No packages found matching %s.\n"),thisarg);
    }
  }

  m_output(stdout, _("<standard output>"));
  m_output(stderr, _("<standard error>"));

  pkg_array_destroy(&array);
}

void setselections(const char *const *argv) {
  const struct namevalue *nv;
  struct pkginfo *pkg;
  const char *e;
  int c, lno;
  struct varbuf namevb = VARBUF_INIT;
  struct varbuf selvb = VARBUF_INIT;

  if (*argv)
    badusage(_("--%s takes no arguments"), cipaction->olong);

  modstatdb_init(admindir, msdbrw_write | msdbrw_available);

  lno= 1;
  for (;;) {
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
    e = pkg_name_is_illegal(namevb.buf, NULL);
    if (e) ohshit(_("illegal package name at line %d: %.250s"),lno,e);

    nv = namevalue_find_by_name(wantinfos, selvb.buf);
    if (nv == NULL)
      ohshit(_("unknown wanted status at line %d: %.250s"), lno, selvb.buf);
    pkg = pkg_db_find(namevb.buf);
    pkg->want = nv->value;
    if (c == EOF) break;
    lno++;
  }
  if (ferror(stdin)) ohshite(_("read error on standard input"));
  modstatdb_shutdown();
  varbuf_destroy(&namevb);
  varbuf_destroy(&selvb);
}

void clearselections(const char *const *argv)
{
  struct pkgiterator *it;
  struct pkginfo *pkg;

  if (*argv)
    badusage(_("--%s takes no arguments"), cipaction->olong);

  modstatdb_init(admindir, msdbrw_write);

  it = pkg_db_iter_new();
  while ((pkg = pkg_db_iter_next(it))) {
    if (!pkg->installed.essential)
      pkg->want = want_deinstall;
  }
  pkg_db_iter_free(it);

  modstatdb_shutdown();
}

