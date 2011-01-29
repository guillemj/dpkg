/*
 * libdpkg - Debian packaging suite library routines
 * dpkg-db.h - declarations for in-core package database management
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2000,2001 Wichert Akkerman
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

#ifndef LIBDPKG_DPKG_DB_H
#define LIBDPKG_DPKG_DB_H

#include <sys/types.h>

#include <stdbool.h>
#include <stdio.h>

#include <dpkg/macros.h>
#include <dpkg/varbuf.h>

DPKG_BEGIN_DECLS

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
  dep_breaks,
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
  struct deppossi *next, *rev_next, *rev_prev;
  struct versionrevision version;
  enum depverrel verrel;
  bool cyclebreak;
};

struct arbitraryfield {
  struct arbitraryfield *next;
  const char *name;
  const char *value;
};

struct conffile {
  struct conffile *next;
  const char *name;
  const char *hash;
  bool obsolete;
};

struct filedetails {
  struct filedetails *next;
  const char *name;
  const char *msdosname;
  const char *size;
  const char *md5sum;
};

/**
 * Node describing a binary package file.
 *
 * This structure holds information contained on each binary package.
 *
 * Note: Usually referred in the code as ‘pif’ for historical reasons.
 */
struct pkgbin {
  struct dependency *depends;
  struct deppossi *depended;
  /* The ‘essential’ flag, true = yes, false = no (absent). */
  bool essential;
  const char *description;
  const char *maintainer;
  const char *source;
  const char *arch;
  const char *installedsize;
  const char *origin;
  const char *bugs;
  struct versionrevision version;
  struct conffile *conffiles;
  struct arbitraryfield *arbs;
};

/**
 * Node indicates that parent's Triggers-Pending mentions name.
 *
 * Note: These nodes do double duty: after they're removed from a package's
 * trigpend list, references may be preserved by the trigger cycle checker
 * (see trigproc.c).
 */
struct trigpend {
  struct trigpend *next;
  const char *name;
};

/**
 * Node indicates that aw's Triggers-Awaited mentions pend.
 */
struct trigaw {
  struct pkginfo *aw, *pend;
  struct trigaw *samepend_next;
  struct {
    struct trigaw *next, *prev;
  } sameaw;
};

/* Note: dselect and dpkg have different versions of this. */
struct perpackagestate;

/* pig */
struct pkginfo {
  struct pkginfo *next;
  const char *name;
  enum pkgwant {
    want_unknown, want_install, want_hold, want_deinstall, want_purge,
    /* Not allowed except as special sentinel value in some places. */
    want_sentinel,
  } want;
  /* The error flag bitmask. */
  enum pkgeflag {
    eflag_ok		= 0,
    eflag_reinstreq	= 1,
  } eflag;
  enum pkgstatus {
    stat_notinstalled,
    stat_configfiles,
    stat_halfinstalled,
    stat_unpacked,
    stat_halfconfigured,
    stat_triggersawaited,
    stat_triggerspending,
    stat_installed
  } status;
  enum pkgpriority {
    pri_required,
    pri_important,
    pri_standard,
    pri_optional,
    pri_extra,
    pri_other, pri_unknown, pri_unset=-1
  } priority;
  const char *otherpriority;
  const char *section;
  struct versionrevision configversion;
  struct filedetails *files;
  struct pkgbin installed;
  struct pkgbin available;
  struct perpackagestate *clientdata;

  struct {
    /* ->aw == this */
    struct trigaw *head, *tail;
  } trigaw;

  /* ->pend == this, non-NULL for us when Triggers-Pending. */
  struct trigaw *othertrigaw_head;
  struct trigpend *trigpend_head;
};

/*** from dbmodify.c ***/

enum modstatdb_rw {
  /* Those marked with \*s*\ are possible returns from modstatdb_init. */
  msdbrw_readonly/*s*/, msdbrw_needsuperuserlockonly/*s*/,
  msdbrw_writeifposs,
  msdbrw_write/*s*/, msdbrw_needsuperuser,

  /* Now some optional flags: */
  msdbrw_flagsmask= ~077,
  /* Flags start at 0100. */
  msdbrw_noavail= 0100,
};

bool modstatdb_is_locked(const char *admindir);
void modstatdb_lock(const char *admindir);
void modstatdb_unlock(void);
enum modstatdb_rw modstatdb_init(const char *admindir, enum modstatdb_rw reqrwflags);
void modstatdb_note(struct pkginfo *pkg);
void modstatdb_note_ifwrite(struct pkginfo *pkg);
void modstatdb_checkpoint(void);
void modstatdb_shutdown(void);

const char *pkgadmindir_init(const char *default_dir);
const char *pkgadmindir(void);
const char *pkgadminfile(struct pkginfo *pkg, const char *whichfile);

/*** from database.c ***/

void pkg_blank(struct pkginfo *pp);
void pkgbin_blank(struct pkgbin *pifp);
void blankversion(struct versionrevision*);
bool pkg_is_informative(struct pkginfo *pkg, struct pkgbin *info);

struct pkginfo *pkg_db_find(const char *name);
int pkg_db_count(void);
void pkg_db_reset(void);

struct pkgiterator *pkg_db_iter_new(void);
struct pkginfo *pkg_db_iter_next(struct pkgiterator *iter);
void pkg_db_iter_free(struct pkgiterator *iter);

void hashreport(FILE*);

/*** from parse.c ***/

enum parsedbflags {
  /* Store in ‘available’ in-core structures, not ‘status’. */
  pdb_recordavailable = 001,
  /* Throw up an error if ‘Status’ encountered. */
  pdb_rejectstatus = 002,
  /* Ignore priority/section info if we already have any. */
  pdb_weakclassification = 004,
  /* Ignore files info if we already have them. */
  pdb_ignorefiles = 010,
  /* Ignore packages with older versions already read. */
  pdb_ignoreolder = 020,
  /* Perform laxer parsing, used to transition to stricter parsing. */
  pdb_lax_parser = 040,
};

const char *pkg_name_is_illegal(const char *p, const char **ep);
int parsedb(const char *filename, enum parsedbflags, struct pkginfo **donep);
void copy_dependency_links(struct pkginfo *pkg,
                           struct dependency **updateme,
                           struct dependency *newdepends,
                           bool available);

/*** from parsehelp.c ***/

#include <dpkg/namevalue.h>

extern const struct namevalue booleaninfos[];
extern const struct namevalue priorityinfos[];
extern const struct namevalue statusinfos[];
extern const struct namevalue eflaginfos[];
extern const struct namevalue wantinfos[];

bool informativeversion(const struct versionrevision *version);

enum versiondisplayepochwhen { vdew_never, vdew_nonambig, vdew_always };
void varbufversion(struct varbuf*, const struct versionrevision*,
                   enum versiondisplayepochwhen);
const char *parseversion(struct versionrevision *rversion, const char*);
const char *versiondescribe(const struct versionrevision*,
                            enum versiondisplayepochwhen);

/*** from dump.c ***/

void writerecord(FILE*, const char*,
                 const struct pkginfo *, const struct pkgbin *);

void writedb(const char *filename, bool available, bool mustsync);

/* Note: The varbufs must have been initialized and will not be
 * NUL-terminated. */
void varbufrecord(struct varbuf *, const struct pkginfo *,
                  const struct pkgbin *);
void varbufdependency(struct varbuf *vb, struct dependency *dep);

/*** from vercmp.c ***/

bool versionsatisfied(struct pkgbin *it, struct deppossi *against);
bool versionsatisfied3(const struct versionrevision *it,
                       const struct versionrevision *ref,
                       enum depverrel verrel);
int versioncompare(const struct versionrevision *version,
                   const struct versionrevision *refversion);
bool epochsdiffer(const struct versionrevision *a,
                  const struct versionrevision *b);

/*** from nfmalloc.c ***/
void *nfmalloc(size_t);
char *nfstrsave(const char*);
char *nfstrnsave(const char*, size_t);
void nffreeall(void);

DPKG_END_DECLS

#endif /* LIBDPKG_DPKG_DB_H */
