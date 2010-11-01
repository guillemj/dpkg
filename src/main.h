/*
 * dpkg - main program for package management
 * main.h - external definitions for this program
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

#ifndef MAIN_H
#define MAIN_H

#include <dpkg/pkg-list.h>

/* These two are defined in filesdb.h. */
struct fileinlist;
struct filenamenode;

struct perpackagestate {
  enum istobes {
    itb_normal, itb_remove, itb_installnew, itb_deconfigure, itb_preinstall
  } istobe;

  /* Used during cycle detection. */
  enum {
    white,
    gray,
    black,
  } color;

  /*
   * filelistvalid  files  Meaning
   * -------------  -----  -------
   * false          NULL   Not read yet, must do so if want them.
   * false          !NULL  Read, but rewritten and now out of date. If want
   *                         info must throw away old and reread file.
   * true           !NULL  Read, all is OK.
   * true           NULL   Read OK, but, there were no files.
   */
  bool fileslistvalid;
  struct fileinlist *files;
  int replacingfilesandsaid;

  off_t listfile_phys_offs;

  /* Non-NULL iff in trigproc.c:deferred. */
  struct pkg_list *trigprocdeferred;
};

enum action {
	act_unset,

	act_unpack,
	act_configure,
	act_install,
	act_triggers,
	act_remove,
	act_purge,
	act_commandfd,

	act_status,
	act_listpackages,
	act_listfiles,
	act_searchfiles,
	act_controlpath,

	act_cmpversions,

	act_printarch,
	act_printinstarch,

	act_assertpredep,
	act_assertepoch,
	act_assertlongfilenames,
	act_assertmulticonrep,

	act_audit,
	act_unpackchk,
	act_predeppackage,

	act_getselections,
	act_setselections,
	act_clearselections,

	act_avail,
	act_printavail,
	act_avclear,
	act_avreplace,
	act_avmerge,
	act_forgetold,
};

enum conffopt {
  cfof_prompt        =     001,
  cfof_keep          =     002,
  cfof_install       =     004,
  cfof_backup        =   00100,
  cfof_newconff      =   00200,
  cfof_isnew         =   00400,
  cfof_isold         =   01000,
  cfof_userrmd       =   02000,
  cfo_keep           =   cfof_keep,
  cfo_prompt_keep    =   cfof_keep | cfof_prompt,
  cfo_prompt         =               cfof_prompt,
  cfo_prompt_install =               cfof_prompt | cfof_install,
  cfo_install        =                             cfof_install,
  cfo_newconff       =                             cfof_install | cfof_newconff,
  cfo_identical      =   cfof_keep
};

extern const char *const statusstrings[];

extern int f_pending, f_recursive, f_alsoselect, f_skipsame, f_noact;
extern int f_autodeconf, f_nodebsig;
extern int f_triggers;
extern unsigned long f_debug;
extern int fc_downgrade, fc_configureany, fc_hold, fc_removereinstreq, fc_overwrite;
extern int fc_removeessential, fc_conflicts, fc_depends, fc_dependsversion;
extern int fc_breaks, fc_badpath, fc_overwritediverted, fc_architecture;
extern int fc_nonroot, fc_overwritedir, fc_conff_new, fc_conff_miss;
extern int fc_conff_old, fc_conff_def;
extern int fc_conff_ask;
extern int fc_badverify;

extern bool abort_processing;
extern int errabort;
extern const char *admindir;
extern const char *instdir;
extern struct pkg_list *ignoredependss;
extern const char architecture[];

struct invoke_hook {
	struct invoke_hook *next;
	const char *command;
};

/* from archives.c */

void archivefiles(const char *const *argv);
void process_archive(const char *filename);
int wanttoinstall(struct pkginfo *pkg, const struct versionrevision *ver,
                  bool saywhy);
struct fileinlist *newconff_append(struct fileinlist ***newconffileslastp_io,
				   struct filenamenode *namenode);

/* from update.c */

void forgetold(const char *const *argv);
void updateavailable(const char *const *argv);

/* from enquiry.c */

void audit(const char *const *argv);
void unpackchk(const char *const *argv);
void assertepoch(const char *const *argv);
void assertpredep(const char *const *argv);
void assertlongfilenames(const char *const *argv);
void assertmulticonrep(const char *const *argv);
void predeppackage(const char *const *argv);
void printarch(const char *const *argv);
void printinstarch(const char *const *argv);
void cmpversions(const char *const *argv) DPKG_ATTR_NORET;

/* from select.c */

void getselections(const char *const *argv);
void setselections(const char *const *argv);
void clearselections(const char *const *argv);

/* from packages.c, remove.c and configure.c */

void add_to_queue(struct pkginfo *pkg);
void process_queue(void);
void packages(const char *const *argv);
void removal_bulk(struct pkginfo *pkg);
int conffderef(struct pkginfo *pkg, struct varbuf *result, const char *in);
int dependencies_ok(struct pkginfo *pkg, struct pkginfo *removing,
                    struct varbuf *aemsgs);
int breakses_ok(struct pkginfo *pkg, struct varbuf *aemsgs);

void deferred_remove(struct pkginfo *pkg);
void deferred_configure(struct pkginfo *pkg);

extern int sincenothing, dependtry;

/* from cleanup.c (most of these are declared in archives.h) */

void cu_prermremove(int argc, void **argv);

/* from errors.c */

void print_error_perpackage(const char *emsg, const char *arg);
void forcibleerr(int forceflag, const char *format, ...) DPKG_ATTR_PRINTF(2);
int reportbroken_retexitstatus(void);
bool skip_due_to_hold(struct pkginfo *pkg);

/* from help.c */

struct stat;

bool ignore_depends(struct pkginfo *pkg);
bool force_breaks(struct deppossi *possi);
bool force_depends(struct deppossi *possi);
bool force_conff_new(struct deppossi *possi);
bool force_conff_miss(struct deppossi *possi);
bool force_conflicts(struct deppossi *possi);
void oldconffsetflags(const struct conffile *searchconff);
void ensure_pathname_nonexisting(const char *pathname);
int secure_unlink(const char *pathname);
int secure_unlink_statted(const char *pathname, const struct stat *stab);
void checkpath(void);

struct filenamenode *namenodetouse(struct filenamenode*, struct pkginfo*);

int maintainer_script_installed(struct pkginfo *pkg, const char *scriptname,
                                const char *desc, ...) DPKG_ATTR_SENTINEL;
int maintainer_script_new(struct pkginfo *pkg,
                          const char *scriptname, const char *desc,
                          const char *cidir, char *cidirrest, ...)
                          DPKG_ATTR_SENTINEL;
int maintainer_script_alternative(struct pkginfo *pkg,
                                  const char *scriptname, const char *desc,
                                  const char *cidir, char *cidirrest,
                                  const char *ifok, const char *iffallback);

/* Callers wanting to run the postinst use these two as they want to postpone
 * trigger incorporation until after updating the package status. The effect
 * is that a package can trigger itself. */
int maintainer_script_postinst(struct pkginfo *pkg, ...) DPKG_ATTR_SENTINEL;
void post_postinst_tasks_core(struct pkginfo *pkg);

void post_postinst_tasks(struct pkginfo *pkg, enum pkgstatus new_status);

void clear_istobes(void);
bool isdirectoryinuse(struct filenamenode *namenode, struct pkginfo *pkg);
bool hasdirectoryconffiles(struct filenamenode *namenode, struct pkginfo *pkg);

enum debugflags {
  dbg_general=           00001,
  dbg_scripts=           00002,
  dbg_eachfile=          00010,
  dbg_eachfiledetail=    00100,
  dbg_conff=             00020,
  dbg_conffdetail=       00200,
  dbg_depcon=            00040,
  dbg_depcondetail=      00400,
  dbg_veryverbose=       01000,
  dbg_stupidlyverbose=   02000,
  dbg_triggers =        010000,
  dbg_triggersdetail =  020000,
  dbg_triggersstupid =  040000,
};

void debug(int which, const char *fmt, ...) DPKG_ATTR_PRINTF(2);
void log_action(const char *action, struct pkginfo *pkg);

/* from trigproc.c */

void trigproc_install_hooks(void);
void trigproc_run_deferred(void);
void trigproc_reset_cycle(void);

void trigproc(struct pkginfo *pkg);

void trig_activate_packageprocessing(struct pkginfo *pkg);

/* from depcon.c */

bool depisok(struct dependency *dep, struct varbuf *whynot,
             struct pkginfo **fixbyrm, bool allowunconfigd);
struct cyclesofarlink;
bool findbreakcycle(struct pkginfo *pkg);
void describedepcon(struct varbuf *addto, struct dependency *dep);

#endif /* MAIN_H */
