/*
 * dpkg - main program for package management
 * main.h - external definitions for this program
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

#ifndef MAIN_H
#define MAIN_H

struct fileinlist; /* these two are defined in filesdb.h */
struct filenamenode;

struct perpackagestate {
  enum istobes {
    itb_normal, itb_remove, itb_installnew, itb_deconfigure, itb_preinstall
  } istobe;

  /*   filelistvalid   files         meaning
   *       0             0           not read yet, must do so if want them
   *       0            !=0          read, but rewritten and now out of
   *                               date.  If want info must throw away old
   *                               and reread file.
   *       1            !=0          read, all is OK
   *       1             0           read OK, but, there were no files
   */
  int fileslistvalid;
  struct fileinlist *files;
  int replacingfilesandsaid;
};

struct packageinlist {
  struct packageinlist *next;
  struct pkginfo *pkg;
};

enum action { act_unset, act_install, act_unpack, act_avail, act_configure,
              act_remove, act_purge, act_listpackages, act_avreplace, act_avmerge,
              act_unpackchk, act_status, act_searchfiles, act_audit, act_listfiles,
              act_assertpredep, act_printarch, act_predeppackage, act_cmpversions,
              act_printinstarch, act_compareversions, act_printavail, act_avclear,
              act_forgetold, act_getselections, act_setselections,
              act_assertepoch, act_assertlongfilenames, act_assertmulticonrep,
	      act_commandfd };

enum conffopt {
  cfof_prompt        =     001,
  cfof_keep          =     002,
  cfof_install       =     004,
  cfof_backup        =    0100,
  cfof_newconff      =    0200,
  cfof_isnew         =    0400,
  cfom_main          =     007,
  cfo_keep           =   cfof_keep,
  cfo_prompt_keep    =   cfof_keep | cfof_prompt,
  cfo_prompt         =               cfof_prompt,
  cfo_prompt_install =               cfof_prompt | cfof_install,
  cfo_install        =                             cfof_install,
  cfo_newconff       =                             cfof_install | cfof_newconff,
  cfo_identical      =   cfof_keep
};

extern int conffoptcells[2][2];
extern const char *const statusstrings[];

extern const struct cmdinfo *cipaction;
extern int f_pending, f_recursive, f_alsoselect, f_skipsame, f_noact;
extern int f_autodeconf, f_largemem, f_nodebsig;
extern unsigned long f_debug;
extern int fc_downgrade, fc_configureany, fc_hold, fc_removereinstreq, fc_overwrite;
extern int fc_removeessential, fc_conflicts, fc_depends, fc_dependsversion;
extern int fc_autoselect, fc_badpath, fc_overwritediverted, fc_architecture;
extern int fc_nonroot, fc_overwritedir, fc_conff_new, fc_conff_miss;
extern int fc_conff_old, fc_conff_def;
extern int fc_badverify;

extern int errabort;
extern const char *admindir;
extern const char *instdir;
extern struct packageinlist *ignoredependss;
extern const char architecture[];

/* from filesdb.c */

void filesdbinit(void);

/* from archives.c */

void archivefiles(const char *const *argv);
void process_archive(const char *filename);
int wanttoinstall(struct pkginfo *pkg, const struct versionrevision *ver, int saywhy);

/* from update.c */

void forgetold(const char *const *argv);
void updateavailable(const char *const *argv);

/* from enquiry.c */

void listpackages(const char *const *argv);
void audit(const char *const *argv);
void unpackchk(const char *const *argv);
void showpackages(const char *const *argv);
void searchfiles(const char *const *argv);
void enqperpackage(const char *const *argv);
void assertepoch(const char *const *argv);
void assertpredep(const char *const *argv);
void assertlongfilenames(const char *const *argv);
void assertmulticonrep(const char *const *argv);
void predeppackage(const char *const *argv);
void printarch(const char *const *argv);
void printinstarch(const char *const *argv);
void cmpversions(const char *const *argv) NONRETURNING;

/* Intended for use as a comparison function for qsort when
 * sorting an array of pointers to struct pkginfo:
 */
int pkglistqsortcmp(const void *a, const void *b);

/* from select.c */

void getselections(const char *const *argv);
void setselections(const char *const *argv);

/* from packages.c, remove.c and configure.c */

void add_to_queue(struct pkginfo *pkg);
void process_queue(void);
void packages(const char *const *argv);
void removal_bulk(struct pkginfo *pkg);
int conffderef(struct pkginfo *pkg, struct varbuf *result, const char *in);
int dependencies_ok(struct pkginfo *pkg, struct pkginfo *removing,
                    struct varbuf *aemsgs);

void deferred_remove(struct pkginfo *pkg);
void deferred_configure(struct pkginfo *pkg);

extern int queuelen, sincenothing, dependtry;

/* from cleanup.c (most of these are declared in archives.h) */

void cu_prermremove(int argc, void **argv);

/* from errors.c */

extern int nerrs;
void print_error_perpackage(const char *emsg, const char *arg);
void forcibleerr(int forceflag, const char *format, ...) PRINTFFORMAT(2,3);
int reportbroken_retexitstatus(void);
int skip_due_to_hold(struct pkginfo *pkg);

/* from help.c */

void cu_closefile(int argc, void **argv);
void cu_closepipe(int argc, void **argv);
void cu_closedir(int argc, void **argv);
void cu_closefd(int argc, void **argv);

int ignore_depends(struct pkginfo *pkg);
int force_depends(struct deppossi *possi);
int force_conff_new(struct deppossi *possi);
int force_conff_miss(struct deppossi *possi);
int force_conflicts(struct deppossi *possi);
void ensure_package_clientdata(struct pkginfo *pkg);
const char *pkgadminfile(struct pkginfo *pkg, const char *whichfile);
void oldconffsetflags(const struct conffile *searchconff);
void ensure_pathname_nonexisting(const char *pathname);
int chmodsafe_unlink(const char *pathname); /* chmod 600, then unlink */
void checkpath(void);
struct filenamenode *namenodetouse(struct filenamenode*, struct pkginfo*);

/* all ...'s are const char*'s ... */
int maintainer_script_installed(struct pkginfo *pkg, const char *scriptname,
                                const char *description, ...);
int maintainer_script_new(const char *pkgname,
			  const char *scriptname, const char *description,
                          const char *cidir, char *cidirrest, ...);
int maintainer_script_alternative(struct pkginfo *pkg,
                                  const char *scriptname, const char *description,
                                  const char *cidir, char *cidirrest,
                                  const char *ifok, const char *iffallback);
void clear_istobes(void);
int isdirectoryinuse(struct filenamenode *namenode, struct pkginfo *pkg);

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
};
  
void debug(int which, const char *fmt, ...) PRINTFFORMAT(2,3);
void check_libver(void);
void log_action(const char *action, struct pkginfo *pkg);

/* from depcon.c */

int depisok(struct dependency *dep, struct varbuf *whynot,
            struct pkginfo **fixbyrm, int allowunconfigd);
struct cyclesofarlink;
int findbreakcycle(struct pkginfo *pkg);
void describedepcon(struct varbuf *addto, struct dependency *dep);

#endif /* MAIN_H */
