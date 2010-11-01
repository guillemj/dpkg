/*
 * dpkg - main program for package management
 * help.c - various helper routines
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

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <assert.h>
#include <errno.h>
#include <string.h>
#include <time.h>
#include <dirent.h>
#include <unistd.h>
#include <stdlib.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/path.h>
#include <dpkg/subproc.h>
#include <dpkg/command.h>
#include <dpkg/triglib.h>

#include "filesdb.h"
#include "main.h"

const char *const statusstrings[]= {
  [stat_notinstalled]    = N_("not installed"),
  [stat_configfiles]     = N_("not installed but configs remain"),
  [stat_halfinstalled]   = N_("broken due to failed removal or installation"),
  [stat_unpacked]        = N_("unpacked but not configured"),
  [stat_halfconfigured]  = N_("broken due to postinst failure"),
  [stat_triggersawaited] = N_("awaiting trigger processing by another package"),
  [stat_triggerspending] = N_("triggered"),
  [stat_installed]       = N_("installed")
};

struct filenamenode *namenodetouse(struct filenamenode *namenode, struct pkginfo *pkg) {
  struct filenamenode *r;
  
  if (!namenode->divert) {
    r = namenode;
    return r;
  }
  
  debug(dbg_eachfile,"namenodetouse namenode=`%s' pkg=%s",
        namenode->name,pkg->name);
  
  r=
    (namenode->divert->useinstead && namenode->divert->pkg != pkg)
      ? namenode->divert->useinstead : namenode;
  
  debug(dbg_eachfile,
        "namenodetouse ... useinstead=%s camefrom=%s pkg=%s return %s",
        namenode->divert->useinstead ? namenode->divert->useinstead->name : "<none>",
        namenode->divert->camefrom ? namenode->divert->camefrom->name : "<none>",
        namenode->divert->pkg ? namenode->divert->pkg->name : "<none>",
        r->name);

  return r;
}

/**
 * Verify that some programs can be found in the PATH.
 */
void checkpath(void) {
  static const char *const prog_list[] = {
    DEFAULTSHELL,
    RM,
    TAR,
    FIND,
    BACKEND,
    "ldconfig",
#if WITH_START_STOP_DAEMON
    "start-stop-daemon",
#endif    
    "update-rc.d",
    NULL
  };

  const char *const *prog;
  const char *path_list;
  struct varbuf filename = VARBUF_INIT;
  int warned= 0;

  path_list = getenv("PATH");
  if (!path_list)
    ohshit(_("error: PATH is not set."));

  for (prog = prog_list; *prog; prog++) {
    struct stat stab;
    const char *path, *path_end;
    size_t path_len;

    for (path = path_list; path; path = path_end ? path_end + 1 : NULL) {
      path_end = strchr(path, ':');
      path_len = path_end ? (size_t)(path_end - path) : strlen(path);

      varbufreset(&filename);
      varbufaddbuf(&filename, path, path_len);
      if (path_len)
        varbufaddc(&filename, '/');
      varbufaddstr(&filename, *prog);
      varbufaddc(&filename, '\0');

      if (stat(filename.buf, &stab) == 0 && (stab.st_mode & 0111))
        break;
    }
    if (!path) {
      warning(_("'%s' not found in PATH or not executable."), *prog);
      warned++;
    }
  }

  varbuf_destroy(&filename);

  if (warned)
    forcibleerr(fc_badpath,
                P_("%d expected program not found in PATH or not executable.\n"
                   "NB: root's PATH should usually contain "
                   "/usr/local/sbin, /usr/sbin and /sbin.",
                   "%d expected programs not found in PATH or not executable.\n"
                   "NB: root's PATH should usually contain "
                   "/usr/local/sbin, /usr/sbin and /sbin.", warned), warned);
}

bool
ignore_depends(struct pkginfo *pkg)
{
  struct pkg_list *id;
  for (id= ignoredependss; id; id= id->next)
    if (id->pkg == pkg)
      return true;
  return false;
}

bool
force_depends(struct deppossi *possi)
{
  return fc_depends ||
         ignore_depends(possi->ed) ||
         ignore_depends(possi->up->up);
}

bool
force_breaks(struct deppossi *possi)
{
  return fc_breaks ||
         ignore_depends(possi->ed) ||
         ignore_depends(possi->up->up);
}

bool
force_conflicts(struct deppossi *possi)
{
  return fc_conflicts;
}

/**
 * Returns the path to the script inside the chroot.
 *
 * FIXME: None of the stuff here will work if admindir isn't inside
 * instdir as expected.
 */
static const char *
preexecscript(struct command *cmd)
{
  size_t instdirl;

  if (*instdir) {
    if (chroot(instdir)) ohshite(_("failed to chroot to `%.250s'"),instdir);
    if (chdir("/"))
      ohshite(_("failed to chdir to `%.255s'"), "/");
  }
  if (f_debug & dbg_scripts) {
    struct varbuf args = VARBUF_INIT;
    const char **argv = cmd->argv;

    while (*++argv) {
      varbufaddc(&args, ' ');
      varbufaddstr(&args, *argv);
    }
    varbufaddc(&args, '\0');
    debug(dbg_scripts, "fork/exec %s (%s )", cmd->filename, args.buf);
    varbuf_destroy(&args);
  }
  instdirl= strlen(instdir);
  if (!instdirl)
    return cmd->filename;
  assert(strlen(cmd->filename) >= instdirl);
  return cmd->filename + instdirl;
}  

void
post_postinst_tasks(struct pkginfo *pkg, enum pkgstatus new_status)
{
  pkg->trigpend_head = NULL;
  pkg->status = pkg->trigaw.head ? stat_triggersawaited : new_status;

  post_postinst_tasks_core(pkg);
}

void
post_postinst_tasks_core(struct pkginfo *pkg)
{
  modstatdb_note(pkg);

  if (!f_noact) {
    debug(dbg_triggersdetail, "post_postinst_tasks_core - trig_incorporate");
    trig_incorporate(msdbrw_write, admindir);
  }
}

static void
post_script_tasks(void)
{
  ensure_diversions();

  debug(dbg_triggersdetail,
        "post_script_tasks - ensure_diversions; trig_incorporate");
  trig_incorporate(msdbrw_write, admindir);
}

static void
cu_post_script_tasks(int argc, void **argv)
{
  post_script_tasks();
}

static void setexecute(const char *path, struct stat *stab) {
  if ((stab->st_mode & 0555) == 0555) return;
  if (!chmod(path,0755)) return;
  ohshite(_("unable to set execute permissions on `%.250s'"),path);
}

static int
do_script(struct pkginfo *pkg, struct pkginfoperfile *pif,
          struct command *cmd, struct stat *stab, int warn)
{
  int c1, r;

  setexecute(cmd->filename, stab);

  push_cleanup(cu_post_script_tasks, ehflag_bombout, NULL, 0, 0);

  c1 = subproc_fork();
  if (!c1) {
    if (setenv(MAINTSCRIPTPKGENVVAR, pkg->name, 1) ||
        setenv(MAINTSCRIPTARCHENVVAR, pif->architecture, 1) ||
        setenv(MAINTSCRIPTNAMEENVVAR, cmd->argv[0], 1) ||
        setenv(MAINTSCRIPTDPKGENVVAR, PACKAGE_VERSION, 1))
      ohshite(_("unable to setenv for maintainer script"));

    cmd->filename = cmd->argv[0] = preexecscript(cmd);
    command_exec(cmd);
  }
  subproc_signals_setup(cmd->name); /* This does a push_cleanup(). */
  r = subproc_wait_check(c1, cmd->name, warn);
  pop_cleanup(ehflag_normaltidy);

  pop_cleanup(ehflag_normaltidy);

  return r;
}

static int
vmaintainer_script_installed(struct pkginfo *pkg, const char *scriptname,
                             const char *desc, va_list args)
{
  struct command cmd;
  const char *scriptpath;
  struct stat stab;
  char buf[100];

  scriptpath= pkgadminfile(pkg,scriptname);
  sprintf(buf, _("installed %s script"), desc);

  command_init(&cmd, scriptpath, buf);
  command_add_arg(&cmd, scriptname);
  command_add_argv(&cmd, args);

  if (stat(scriptpath,&stab)) {
    command_destroy(&cmd);
    if (errno == ENOENT) {
      debug(dbg_scripts, "vmaintainer_script_installed nonexistent %s",
            scriptname);
      return 0;
    }
    ohshite(_("unable to stat %s `%.250s'"), buf, scriptpath);
  }
  do_script(pkg, &pkg->installed, &cmd, &stab, 0);

  command_destroy(&cmd);

  return 1;
}

/*
 * All ...'s in maintainer_script_* are const char *'s.
 */

int
maintainer_script_installed(struct pkginfo *pkg, const char *scriptname,
                            const char *desc, ...)
{
  int r;
  va_list args;

  va_start(args, desc);
  r = vmaintainer_script_installed(pkg, scriptname, desc, args);
  va_end(args);
  if (r)
    post_script_tasks();

  return r;
}

int
maintainer_script_postinst(struct pkginfo *pkg, ...)
{
  int r;
  va_list args;

  va_start(args, pkg);
  r = vmaintainer_script_installed(pkg, POSTINSTFILE, "post-installation", args);
  va_end(args);
  if (r)
    ensure_diversions();

  return r;
}

int
maintainer_script_new(struct pkginfo *pkg,
                      const char *scriptname, const char *desc,
                      const char *cidir, char *cidirrest, ...)
{
  struct command cmd;
  struct stat stab;
  va_list args;
  char buf[100];
  
  strcpy(cidirrest, scriptname);
  sprintf(buf, _("new %s script"), desc);

  va_start(args, cidirrest);
  command_init(&cmd, cidir, buf);
  command_add_arg(&cmd, scriptname);
  command_add_argv(&cmd, args);
  va_end(args);

  if (stat(cidir,&stab)) {
    command_destroy(&cmd);
    if (errno == ENOENT) {
      debug(dbg_scripts,"maintainer_script_new nonexistent %s `%s'",scriptname,cidir);
      return 0;
    }
    ohshite(_("unable to stat %s `%.250s'"), buf, cidir);
  }
  do_script(pkg, &pkg->available, &cmd, &stab, 0);

  command_destroy(&cmd);
  post_script_tasks();

  return 1;
}

int maintainer_script_alternative(struct pkginfo *pkg,
                                  const char *scriptname, const char *desc,
                                  const char *cidir, char *cidirrest,
                                  const char *ifok, const char *iffallback) {
  struct command cmd;
  const char *oldscriptpath;
  struct stat stab;
  char buf[100];

  oldscriptpath= pkgadminfile(pkg,scriptname);
  sprintf(buf, _("old %s script"), desc);

  command_init(&cmd, oldscriptpath, buf);
  command_add_args(&cmd, scriptname, ifok,
                   versiondescribe(&pkg->available.version, vdew_nonambig),
                   NULL);

  if (stat(oldscriptpath,&stab)) {
    if (errno == ENOENT) {
      debug(dbg_scripts,"maintainer_script_alternative nonexistent %s `%s'",
            scriptname,oldscriptpath);
      command_destroy(&cmd);
      return 0;
    }
    warning(_("unable to stat %s '%.250s': %s"),
            cmd.name, oldscriptpath, strerror(errno));
  } else {
    if (!do_script(pkg, &pkg->installed, &cmd, &stab, PROCWARN)) {
      command_destroy(&cmd);
      post_script_tasks();
      return 1;
    }
  }
  fprintf(stderr, _("dpkg - trying script from the new package instead ...\n"));

  strcpy(cidirrest,scriptname);
  sprintf(buf, _("new %s script"), desc);

  command_destroy(&cmd);
  command_init(&cmd, cidir, buf);
  command_add_args(&cmd, scriptname, iffallback,
                   versiondescribe(&pkg->installed.version, vdew_nonambig),
                   NULL);

  if (stat(cidir,&stab)) {
    command_destroy(&cmd);
    if (errno == ENOENT)
      ohshit(_("there is no script in the new version of the package - giving up"));
    else
      ohshite(_("unable to stat %s `%.250s'"),buf,cidir);
  }

  do_script(pkg, &pkg->available, &cmd, &stab, 0);
  fprintf(stderr, _("dpkg: ... it looks like that went OK.\n"));

  command_destroy(&cmd);
  post_script_tasks();

  return 1;
}

void clear_istobes(void) {
  struct pkgiterator *it;
  struct pkginfo *pkg;

  it = pkg_db_iter_new();
  while ((pkg = pkg_db_iter_next(it)) != NULL) {
    ensure_package_clientdata(pkg);
    pkg->clientdata->istobe= itb_normal;
    pkg->clientdata->replacingfilesandsaid= 0;
  }
  pkg_db_iter_free(it);
}

void debug(int which, const char *fmt, ...) {
  va_list args;

  if (!(f_debug & which)) return;
  fprintf(stderr,"D0%05o: ",which);
  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  va_end(args);
  putc('\n',stderr);
}

/*
 * Returns true if the directory contains conffiles belonging to pkg,
 * false otherwise.
 */
bool
hasdirectoryconffiles(struct filenamenode *file, struct pkginfo *pkg)
{
  struct conffile *conff;
  size_t namelen;

  debug(dbg_veryverbose, "hasdirectoryconffiles `%s' (from %s)", file->name,
	pkg->name);
  namelen = strlen(file->name);
  for (conff= pkg->installed.conffiles; conff; conff= conff->next) {
      if (!strncmp(file->name,conff->name,namelen)) {
	debug(dbg_veryverbose, "directory %s has conffile %s from %s",
	      file->name, conff->name, pkg->name);
	return true;
      }
  }
  debug(dbg_veryverbose, "hasdirectoryconffiles no");
  return false;
}

/*
 * Returns true if the file is used by packages other than pkg,
 * false otherwise.
 */
bool
isdirectoryinuse(struct filenamenode *file, struct pkginfo *pkg)
{
  struct filepackages_iterator *iter;
  struct pkginfo *other_pkg;
    
  debug(dbg_veryverbose, "isdirectoryinuse `%s' (except %s)", file->name,
        pkg ? pkg->name : "<none>");

  iter = filepackages_iter_new(file);
  while ((other_pkg = filepackages_iter_next(iter))) {
    debug(dbg_veryverbose, "isdirectoryinuse considering %s ...",
          other_pkg->name);
    if (other_pkg == pkg)
      continue;
    return true;
  }
  filepackages_iter_free(iter);

  debug(dbg_veryverbose, "isdirectoryinuse no");
  return false;
}

void oldconffsetflags(const struct conffile *searchconff) {
  struct filenamenode *namenode;
  
  while (searchconff) {
    namenode= findnamenode(searchconff->name, 0); /* XXX */
    namenode->flags |= fnnf_old_conff;
    if (!namenode->oldhash)
      namenode->oldhash= searchconff->hash;
    debug(dbg_conffdetail, "oldconffsetflags `%s' namenode %p flags %o",
          searchconff->name, namenode, namenode->flags);
    searchconff= searchconff->next;
  }
}

/*
 * If the pathname to remove is:
 *
 * 1. a sticky or set-id file, or
 * 2. an unknown object (i.e., not a file, link, directory, fifo or socket)
 *
 * we change its mode so that a malicious user cannot use it, even if it's
 * linked to another file.
 */
int
secure_unlink(const char *pathname)
{
  struct stat stab;

  if (lstat(pathname,&stab)) return -1;

  return secure_unlink_statted(pathname, &stab);
}

int
secure_unlink_statted(const char *pathname, const struct stat *stab)
{
  if (S_ISREG(stab->st_mode) ? (stab->st_mode & 07000) :
      !(S_ISLNK(stab->st_mode) || S_ISDIR(stab->st_mode) ||
	S_ISFIFO(stab->st_mode) || S_ISSOCK(stab->st_mode))) {
    if (chmod(pathname, 0600))
      return -1;
  }
  if (unlink(pathname)) return -1;
  return 0;
}

void ensure_pathname_nonexisting(const char *pathname) {
  int c1;
  const char *u;

  u = path_skip_slash_dotslash(pathname);
  assert(*u);

  debug(dbg_eachfile,"ensure_pathname_nonexisting `%s'",pathname);
  if (!rmdir(pathname))
    return; /* Deleted it OK, it was a directory. */
  if (errno == ENOENT || errno == ELOOP) return;
  if (errno == ENOTDIR) {
    /* Either it's a file, or one of the path components is. If one
     * of the path components is this will fail again ... */
    if (secure_unlink(pathname) == 0)
      return; /* OK, it was. */
    if (errno == ENOTDIR) return;
  }
  if (errno != ENOTEMPTY && errno != EEXIST) { /* Huh? */
    ohshite(_("unable to securely remove '%.255s'"), pathname);
  }
  c1 = subproc_fork();
  if (!c1) {
    execlp(RM, "rm", "-rf", "--", pathname, NULL);
    ohshite(_("unable to execute %s (%s)"), _("rm command for cleanup"), RM);
  }
  debug(dbg_eachfile,"ensure_pathname_nonexisting running rm -rf");
  subproc_wait_check(c1, "rm cleanup", 0);
}

void log_action(const char *action, struct pkginfo *pkg) {
  log_message("%s %s %s %s", action, pkg->name,
	      versiondescribe(&pkg->installed.version, vdew_nonambig),
	      versiondescribe(&pkg->available.version, vdew_nonambig));
  statusfd_send("processing: %s: %s", action, pkg->name);
}
