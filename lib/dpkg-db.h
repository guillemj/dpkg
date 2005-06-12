/*
 * libdpkg - Debian packaging suite library routines
 * dpkg-db.h - declarations for in-core package database management
 *
 * Copyright (C) 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright (C) 2000,2001 Wichert Akkerman
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

#ifndef DPKG_DB_H
#define DPKG_DB_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct versionrevision {
  unsigned long epoch;
  const char *version;
  const char *revision;
};  

enum deptype {
  dep_suggests,
  dep_recommends,
  dep_depends,
  dep_predepends,
  dep_conflicts,
  dep_provides,
  dep_replaces,
  dep_enhances
};

enum depverrel {
  dvrf_earlier=      0001,
  dvrf_later=        0002,
  dvrf_strict=       0010,
  dvrf_orequal=      0020,
  dvrf_builtup=      0100,
  dvr_none=          0200,
  dvr_earlierequal=  dvrf_builtup | dvrf_earlier | dvrf_orequal,
  dvr_earlierstrict= dvrf_builtup | dvrf_earlier | dvrf_strict,
  dvr_laterequal=    dvrf_builtup | dvrf_later   | dvrf_orequal,
  dvr_laterstrict=   dvrf_builtup | dvrf_later   | dvrf_strict,
  dvr_exact=         0400
};

struct dependency {
  struct pkginfo *up;
  struct dependency *next;
  struct deppossi *list;
  enum deptype type;
};

struct deppossi {
  struct dependency *up;
  struct pkginfo *ed;
  struct deppossi *next, *nextrev, *backrev;
  struct versionrevision version;
  enum depverrel verrel;
  int cyclebreak;
};

struct arbitraryfield {
  struct arbitraryfield *next;
  char *name;
  char *value;
};

struct conffile {
  struct conffile *next;
  const char *name;
  const char *hash;
};

struct filedetails {
  struct filedetails *next;
  char *name;
  char *msdosname;
  char *size;
  char *md5sum;
};

struct pkginfoperfile { /* pif */
  int valid;
  struct dependency *depends;
  struct deppossi *depended;
  int essential; /* The `essential' flag, 1=yes, 0=no (absent) */
  char *description, *maintainer, *source, *architecture, *installedsize, *origin, *bugs;
  struct versionrevision version;
  struct conffile *conffiles;
  struct arbitraryfield *arbs;
};

struct perpackagestate; /* dselect and dpkg have different versions of this */

struct pkginfo { /* pig */
  struct pkginfo *next;
  const char *name;
  enum pkgwant {
    want_unknown, want_install, want_hold, want_deinstall, want_purge,
    want_sentinel /* Not allowed except as special sentinel value
                     in some places */
  } want;
  enum pkgeflag {
    eflagf_reinstreq    = 01,
    eflagf_obsoletehold = 02,
    eflagv_ok           = 0,
    eflagv_reinstreq    =    eflagf_reinstreq,
    eflagv_obsoletehold =                       eflagf_obsoletehold,
    eflagv_obsoleteboth =    eflagf_reinstreq | eflagf_obsoletehold
  } eflag; /* bitmask, but obsoletehold no longer used except when reading */
  enum pkgstatus {
    stat_notinstalled, stat_unpacked, stat_halfconfigured,
    stat_installed, stat_halfinstalled, stat_configfiles
  } status;
  enum pkgpriority {
    pri_required, pri_important, pri_standard, pri_recommended,
    pri_optional, pri_extra, pri_contrib,
    pri_other, pri_unknown, pri_unset=-1
  } priority;
  const char *otherpriority;
  const char *section;
  struct versionrevision configversion;
  struct filedetails *files;
  struct pkginfoperfile installed;
  struct pkginfoperfile available;
  struct perpackagestate *clientdata;
  enum { white, gray, black } color;  /* used during cycle detection */
};

/*** from lock.c ***/

void lockdatabase(const char *admindir);
void unlockdatabase(const char *admindir);

/*** from dbmodify.c ***/

enum modstatdb_rw {
  /* Those marked with \*s*\ are possible returns from modstatdb_init. */
  msdbrw_readonly/*s*/, msdbrw_needsuperuserlockonly/*s*/,
  msdbrw_writeifposs,
  msdbrw_write/*s*/, msdbrw_needsuperuser,
  /* Now some optional flags: */
  msdbrw_flagsmask= ~077,
  /* flags start at 0100 */
  msdbrw_noavail= 0100,
};

struct pipef {
  int fd;
  struct pipef *next;
};
extern struct pipef *status_pipes;

enum modstatdb_rw modstatdb_init(const char *admindir, enum modstatdb_rw reqrwflags);
void modstatdb_note(struct pkginfo *pkg);
void modstatdb_shutdown(void);

extern char *statusfile, *availablefile; /* initialised by modstatdb_init */

void log_message(const char *fmt, ...);

/*** from database.c ***/

struct pkginfo *findpackage(const char *name);
void blankpackage(struct pkginfo *pp);
void blankpackageperfile(struct pkginfoperfile *pifp);
void blankversion(struct versionrevision*);
int informative(struct pkginfo *pkg, struct pkginfoperfile *info);
int countpackages(void);
void resetpackages(void);

struct pkgiterator *iterpkgstart(void);
struct pkginfo *iterpkgnext(struct pkgiterator*);
void iterpkgend(struct pkgiterator*);

void hashreport(FILE*);

/*** from parse.c ***/

enum parsedbflags {
  pdb_recordavailable   =001, /* Store in `available' in-core structures, not `status' */
  pdb_rejectstatus      =002, /* Throw up an error if `Status' encountered             */
  pdb_weakclassification=004, /* Ignore priority/section info if we already have any   */
  pdb_ignorefiles       =010  /* Ignore files info if we already have them             */
};

const char *illegal_packagename(const char *p, const char **ep);
int parsedb(const char *filename, enum parsedbflags, struct pkginfo **donep,
            FILE *warnto, int *warncount);
void copy_dependency_links(struct pkginfo *pkg,
                           struct dependency **updateme,
                           struct dependency *newdepends,
                           int available);

/*** from parsehelp.c ***/

struct namevalue {
  const char *name;
  int value, length;
};

extern const struct namevalue booleaninfos[];
extern const struct namevalue priorityinfos[];
extern const struct namevalue statusinfos[];
extern const struct namevalue eflaginfos[];
extern const struct namevalue wantinfos[];

const char *skip_slash_dotslash(const char *p);

int informativeversion(const struct versionrevision *version);

enum versiondisplayepochwhen { vdew_never, vdew_nonambig, vdew_always };
void varbufversion(struct varbuf*, const struct versionrevision*,
                   enum versiondisplayepochwhen);
const char *parseversion(struct versionrevision *rversion, const char*);
const char *versiondescribe(const struct versionrevision*,
                            enum versiondisplayepochwhen);

/*** from varbuf.c ***/

struct varbuf;

extern void varbufaddc(struct varbuf *v, int c);
extern void varbufdupc(struct varbuf *v, int c, ssize_t s);
int varbufprintf(struct varbuf *v, const char *fmt, ...) PRINTFFORMAT(2,3);
int varbufvprintf(struct varbuf *v, const char *fmt, va_list va);
void varbufinit(struct varbuf *v);
void varbufreset(struct varbuf *v);
void varbufextend(struct varbuf *v);
void varbuffree(struct varbuf *v);
#define varbufaddstr(v, s)      varbufaddbuf(v, s, strlen(s))
extern void varbufaddbuf(struct varbuf *v, const void *s, const int l);

/* varbufinit must be called exactly once before the use of each varbuf
 * (including before any call to varbuffree).
 *
 * However, varbufs allocated `static' are properly initialised anyway and
 * do not need varbufinit; multiple consecutive calls to varbufinit before
 * any use are allowed.
 *
 * varbuffree must be called after a varbuf is finished with, if anything
 * other than varbufinit has been done.  After this you are allowed but
 * not required to call varbufinit again if you want to start using the
 * varbuf again.
 *
 * Callers using C++ need not worry about any of this.
 */
struct varbuf {
  size_t used, size;
  char *buf;

#ifdef __cplusplus
  void init() { varbufinit(this); }
  void free() { varbuffree(this); }
  varbuf() { varbufinit(this); }
  ~varbuf() { varbuffree(this); }
  void operator()(int c) { varbufaddc(this,c); }
  void operator()(const char *s) { varbufaddstr(this,s); }
  void terminate(void/*to shut 2.6.3 up*/) { varbufaddc(this,0); used--; }
  void reset() { used=0; }
  const char *string() { terminate(); return buf; }
#endif
};

/*** from dump.c ***/

void writerecord(FILE*, const char*,
                 const struct pkginfo*, const struct pkginfoperfile*);

void writedb(const char *filename, int available, int mustsync);

void varbufrecord(struct varbuf*, const struct pkginfo*, const struct pkginfoperfile*);
void varbufdependency(struct varbuf *vb, struct dependency *dep);
  /* NB THE VARBUF MUST HAVE BEEN INITIALISED AND WILL NOT BE NULL-TERMINATED */

/*** from vercmp.c ***/

int versionsatisfied(struct pkginfoperfile *it, struct deppossi *against);
int versionsatisfied3(const struct versionrevision *it,
                      const struct versionrevision *ref,
                      enum depverrel verrel);
int versioncompare(const struct versionrevision *version,
                   const struct versionrevision *refversion);
int epochsdiffer(const struct versionrevision *a,
                 const struct versionrevision *b);

/*** from nfmalloc.c ***/
extern void *nfmalloc(size_t);
char *nfstrsave(const char*);
char *nfstrnsave(const char*, int);
void nffreeall(void);

/*** from showpkg.c ***/

struct lstitem;

struct lstitem* parseformat(const char* fmt);
void freeformat(struct lstitem* head);
void show1package(const struct lstitem* head, struct pkginfo *pkg);
#endif /* DPKG_DB_H */
