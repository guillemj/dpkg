/*
 * dpkg - main program for package management
 * archives.h - functions common to archives.c and processarc.c
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

#ifndef ARCHIVES_H
#define ARCHIVES_H

struct tarcontext {
  int backendpipe;
  struct pkginfo *pkg;
  struct fileinlist **newfilesp;
};

extern int fnameidlu;
extern struct varbuf fnamevb;
extern struct varbuf fnametmpvb;
extern struct varbuf fnamenewvb;
extern struct packageinlist *deconfigure;

extern struct pkginfo *conflictor[];
extern int cflict_index;

void cu_pathname(int argc, void **argv);
void cu_cidir(int argc, void **argv);
void cu_fileslist(int argc, void **argv);
void cu_backendpipe(int argc, void **argv);

void cu_installnew(int argc, void **argv);

void cu_prermupgrade(int argc, void **argv);
void cu_prerminfavour(int argc, void **argv);
void cu_preinstverynew(int argc, void **argv);
void cu_preinstnew(int argc, void **argv);
void cu_preinstupgrade(int argc, void **argv);
void cu_postrmupgrade(int argc, void **argv);

void cu_prermdeconfigure(int argc, void **argv);
void ok_prermdeconfigure(int argc, void **argv);

void setupfnamevbs(const char *filename);
int unlinkorrmdir(const char *filename);

int tarobject(struct TarInfo *ti);
int tarfileread(void *ud, char *buf, int len);

int filesavespackage(struct fileinlist*, struct pkginfo*,
                     struct pkginfo *pkgbeinginstalled);

void check_conflict(struct dependency *dep, struct pkginfo *pkg,
                    const char *pfilename);

extern int cleanup_pkg_failed, cleanup_conflictor_failed;

#endif /* ARCHIVES_H */
