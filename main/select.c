/*
 * dpkg - main program for package management
 * select.c - by-hand (rather than dselect-based) package selection
 *
 * Copyright (C) 1995,1996 Ian Jackson <ian@chiark.greenend.org.uk>
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

#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <fnmatch.h>
#include <ctype.h>

#include <dpkg.h>
#include <dpkg-db.h>

#include "filesdb.h"
#include "main.h"

static void getsel1package(struct pkginfo *pkg) {
  int l;

  if (pkg->want == want_unknown) return;
  l= strlen(pkg->name); l >>= 3; l= 6-l; if (l<1) l=1;
  printf("%s%.*s%s\n",pkg->name,l,"\t\t\t\t\t\t",wantinfos[pkg->want].name);
}         

void getselections(const char *const *argv) {
  struct pkgiterator *it;
  struct pkginfo *pkg;
  struct pkginfo **pkgl;
  const char *thisarg;
  int np, i, head, found;

  modstatdb_init(admindir,msdbrw_readonly);

  np= countpackages();
  pkgl= m_malloc(sizeof(struct pkginfo*)*np);
  it= iterpkgstart(); i=0;
  while ((pkg= iterpkgnext(it))) {
    assert(i<np);
    pkgl[i++]= pkg;
  }
  iterpkgend(it);
  assert(i==np);

  qsort(pkgl,np,sizeof(struct pkginfo*),pkglistqsortcmp);
  head=0;
  
  if (!*argv) {
    for (i=0; i<np; i++) {
      pkg= pkgl[i];
      if (pkg->status == stat_notinstalled) continue;
      getsel1package(pkg);
    }
  } else {
    while ((thisarg= *argv++)) {
      found= 0;
      for (i=0; i<np; i++) {
        pkg= pkgl[i];
        if (fnmatch(thisarg,pkg->name,0)) continue;
        getsel1package(pkg); found++;
      }
      if (!found)
        fprintf(stderr,_("No packages found matching %s.\n"),thisarg);
    }
  }
  if (ferror(stdout)) werr("stdout");
  if (ferror(stderr)) werr("stderr");
}

void setselections(const char *const *argv) {
  const struct namevalue *nvp;
  struct pkginfo *pkg;
  const char *e;
  int c, lno;
  struct varbuf namevb;
  struct varbuf selvb;

  if (*argv) badusage(_("--set-selections does not take any argument"));

  modstatdb_init(admindir,msdbrw_write);

  varbufinit(&namevb);
  varbufinit(&selvb);
  lno= 1;
  for (;;) {
    varbufreset(&namevb);
    varbufreset(&selvb);
    do { c= getchar(); if (c == '\n') lno++; } while (c != EOF && isspace(c));
    if (c == EOF) break;
    if (c == '#') {
      do { c= getchar(); if (c == '\n') lno++; } while (c != EOF && c != '\n');
      continue;
    }
    while (!isspace(c)) {
      varbufaddc(&namevb,c);
      c= getchar();
      if (c == EOF) ohshit(_("unexpected eof in package name at line %d"),lno);
      if (c == '\n') ohshit(_("unexpected end of line in package name at line %d"),lno);
    }
    while (c != EOF && isspace(c)) {
      c= getchar();
      if (c == EOF) ohshit(_("unexpected eof after package name at line %d"),lno);
      if (c == '\n') ohshit(_("unexpected end of line after package name at line %d"),lno);
    }
    while (c != EOF && !isspace(c)) {
      varbufaddc(&selvb,c);
      c= getchar();
    }
    while (c != EOF && c != '\n') {
      c= getchar();
      if (!isspace(c))
        ohshit(_("unexpected data after package and selection at line %d"),lno);
    }
    varbufaddc(&namevb,0);
    varbufaddc(&selvb,0);
    e= illegal_packagename(namevb.buf,0);
    if (e) ohshit(_("illegal package name at line %d: %.250s"),lno,e);
    for (nvp=wantinfos; nvp->name && strcmp(nvp->name,selvb.buf); nvp++);
    if (!nvp->name) ohshit(_("unknown wanted status at line %d: %.250s"),lno,selvb.buf);
    pkg= findpackage(namevb.buf);
    pkg->want= nvp->value;
    if (c == EOF) break;
    lno++;
  }
  if (ferror(stdin)) ohshite(_("read error on standard input"));
  modstatdb_shutdown();
  varbufreset(&namevb);
  varbufreset(&selvb);
}
