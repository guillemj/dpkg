/*
 * dpkg - main program for package management
 * archives.h - functions common to archives.c and unpack.c
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

#ifndef ARCHIVES_H
#define ARCHIVES_H

#include <stdbool.h>

#include <dpkg/tarfn.h>

struct tarcontext {
  int backendpipe;
  struct pkginfo *pkg;
  struct fileinlist **newfilesp;
  /** Are all “Multi-arch: same” instances about to be in sync? */
  bool pkgset_getting_in_sync;
};

struct pkg_deconf_list {
  struct pkg_deconf_list *next;
  struct pkginfo *pkg;
  struct pkginfo *pkg_removal;
};

extern int fnameidlu;
extern struct varbuf fnamevb;
extern struct varbuf fnametmpvb;
extern struct varbuf fnamenewvb;
extern struct pkg_deconf_list *deconfigure;

void clear_deconfigure_queue(void);
void enqueue_deconfigure(struct pkginfo *pkg, struct pkginfo *pkg_removal);
void enqueue_conflictor(struct pkginfo *pkg, struct pkginfo *pkg_fixbyrm);

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

int secure_remove(const char *filename);

int tarobject(void *ctx, struct tar_entry *ti);
int tarfileread(void *ud, char *buf, int len);
void tar_deferred_extract(struct fileinlist *files, struct pkginfo *pkg);

bool filesavespackage(struct fileinlist *, struct pkginfo *,
                      struct pkginfo *pkgbeinginstalled);

void check_conflict(struct dependency *dep, struct pkginfo *pkg,
                    const char *pfilename);
void check_breaks(struct dependency *dep, struct pkginfo *pkg,
                  const char *pfilename);

struct fileinlist *addfiletolist(struct tarcontext *tc,
				 struct filenamenode *namenode);

extern int cleanup_pkg_failed, cleanup_conflictor_failed;

#endif /* ARCHIVES_H */
