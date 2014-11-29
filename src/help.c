/*
 * dpkg - main program for package management
 * help.c - various helper routines
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2007-2012 Guillem Jover <guillem@debian.org>
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

#include <assert.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/path.h>
#include <dpkg/subproc.h>

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

struct filenamenode *
namenodetouse(struct filenamenode *namenode, struct pkginfo *pkg,
              struct pkgbin *pkgbin)
{
  struct filenamenode *r;

  if (!namenode->divert) {
    r = namenode;
    return r;
  }

  debug(dbg_eachfile, "namenodetouse namenode='%s' pkg=%s",
        namenode->name, pkgbin_name(pkg, pkgbin, pnaw_always));

  r=
    (namenode->divert->useinstead && namenode->divert->pkgset != pkg->set)
      ? namenode->divert->useinstead : namenode;

  debug(dbg_eachfile,
        "namenodetouse ... useinstead=%s camefrom=%s pkg=%s return %s",
        namenode->divert->useinstead ? namenode->divert->useinstead->name : "<none>",
        namenode->divert->camefrom ? namenode->divert->camefrom->name : "<none>",
        namenode->divert->pkgset ? namenode->divert->pkgset->name : "<none>",
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
#if BUILD_START_STOP_DAEMON
    "start-stop-daemon",
#endif
    NULL
  };

  const char *const *prog;
  const char *path_list;
  struct varbuf filename = VARBUF_INIT;
  int warned= 0;

  path_list = getenv("PATH");
  if (!path_list)
    ohshit(_("PATH is not set"));

  for (prog = prog_list; *prog; prog++) {
    struct stat stab;
    const char *path, *path_end;
    size_t path_len;

    for (path = path_list; path; path = path_end ? path_end + 1 : NULL) {
      path_end = strchr(path, ':');
      path_len = path_end ? (size_t)(path_end - path) : strlen(path);

      varbuf_reset(&filename);
      varbuf_add_buf(&filename, path, path_len);
      if (path_len)
        varbuf_add_char(&filename, '/');
      varbuf_add_str(&filename, *prog);
      varbuf_end_str(&filename);

      if (stat(filename.buf, &stab) == 0 && (stab.st_mode & 0111))
        break;
    }
    if (!path) {
      warning(_("'%s' not found in PATH or not executable"), *prog);
      warned++;
    }
  }

  varbuf_destroy(&filename);

  if (warned)
    forcibleerr(fc_badpath,
                P_("%d expected program not found in PATH or not executable\n%s",
                   "%d expected programs not found in PATH or not executable\n%s",
                   warned),
                warned, _("Note: root's PATH should usually contain "
                          "/usr/local/sbin, /usr/sbin and /sbin"));
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

static bool
ignore_depends_possi(struct deppossi *possi)
{
  struct deppossi_pkg_iterator *possi_iter;
  struct pkginfo *pkg;

  possi_iter = deppossi_pkg_iter_new(possi, wpb_installed);
  while ((pkg = deppossi_pkg_iter_next(possi_iter))) {
    if (ignore_depends(pkg)) {
      deppossi_pkg_iter_free(possi_iter);
      return true;
    }
  }
  deppossi_pkg_iter_free(possi_iter);

  return false;
}

bool
force_depends(struct deppossi *possi)
{
  return fc_depends ||
         ignore_depends_possi(possi) ||
         ignore_depends(possi->up->up);
}

bool
force_breaks(struct deppossi *possi)
{
  return fc_breaks ||
         ignore_depends_possi(possi) ||
         ignore_depends(possi->up->up);
}

bool
force_conflicts(struct deppossi *possi)
{
  return fc_conflicts;
}

void clear_istobes(void) {
  struct pkgiterator *it;
  struct pkginfo *pkg;

  it = pkg_db_iter_new();
  while ((pkg = pkg_db_iter_next_pkg(it)) != NULL) {
    ensure_package_clientdata(pkg);
    pkg->clientdata->istobe= itb_normal;
    pkg->clientdata->replacingfilesandsaid= 0;
  }
  pkg_db_iter_free(it);
}

/*
 * Returns true if the directory contains conffiles belonging to pkg,
 * false otherwise.
 */
bool
dir_has_conffiles(struct filenamenode *file, struct pkginfo *pkg)
{
  struct conffile *conff;
  size_t namelen;

  debug(dbg_veryverbose, "dir_has_conffiles '%s' (from %s)", file->name,
        pkg_name(pkg, pnaw_always));
  namelen = strlen(file->name);
  for (conff= pkg->installed.conffiles; conff; conff= conff->next) {
      if (conff->obsolete)
        continue;
      if (strncmp(file->name, conff->name, namelen) == 0 &&
          strlen(conff->name) > namelen && conff->name[namelen] == '/') {
	debug(dbg_veryverbose, "directory %s has conffile %s from %s",
	      file->name, conff->name, pkg_name(pkg, pnaw_always));
	return true;
      }
  }
  debug(dbg_veryverbose, "dir_has_conffiles no");
  return false;
}

/*
 * Returns true if the file is used by packages other than pkg,
 * false otherwise.
 */
bool
dir_is_used_by_others(struct filenamenode *file, struct pkginfo *pkg)
{
  struct filepackages_iterator *iter;
  struct pkginfo *other_pkg;

  debug(dbg_veryverbose, "dir_is_used_by_others '%s' (except %s)", file->name,
        pkg ? pkg_name(pkg, pnaw_always) : "<none>");

  iter = filepackages_iter_new(file);
  while ((other_pkg = filepackages_iter_next(iter))) {
    debug(dbg_veryverbose, "dir_is_used_by_others considering %s ...",
          pkg_name(other_pkg, pnaw_always));
    if (other_pkg == pkg)
      continue;

    filepackages_iter_free(iter);
    debug(dbg_veryverbose, "dir_is_used_by_others yes");
    return true;
  }
  filepackages_iter_free(iter);

  debug(dbg_veryverbose, "dir_is_used_by_others no");
  return false;
}

/*
 * Returns true if the file is used by pkg, false otherwise.
 */
bool
dir_is_used_by_pkg(struct filenamenode *file, struct pkginfo *pkg,
                   struct fileinlist *list)
{
  struct fileinlist *node;
  size_t namelen;

  debug(dbg_veryverbose, "dir_is_used_by_pkg '%s' (by %s)",
        file->name, pkg ? pkg_name(pkg, pnaw_always) : "<none>");

  namelen = strlen(file->name);

  for (node = list; node; node = node->next) {
    debug(dbg_veryverbose, "dir_is_used_by_pkg considering %s ...",
          node->namenode->name);

    if (strncmp(file->name, node->namenode->name, namelen) == 0 &&
        strlen(node->namenode->name) > namelen &&
        node->namenode->name[namelen] == '/') {
      debug(dbg_veryverbose, "dir_is_used_by_pkg yes");
      return true;
    }
  }

  debug(dbg_veryverbose, "dir_is_used_by_pkg no");

  return false;
}

/**
 * Mark a conffile as obsolete.
 *
 * @param pkg		The package owning the conffile.
 * @param namenode	The namenode for the obsolete conffile.
 */
void
conffile_mark_obsolete(struct pkginfo *pkg, struct filenamenode *namenode)
{
  struct conffile *conff;

  for (conff = pkg->installed.conffiles; conff; conff = conff->next) {
    if (strcmp(conff->name, namenode->name) == 0) {
      debug(dbg_conff, "marking %s conffile %s as obsolete",
            pkg_name(pkg, pnaw_always), conff->name);
      conff->obsolete = true;
      return;
    }
  }
}

void oldconffsetflags(const struct conffile *searchconff) {
  struct filenamenode *namenode;

  while (searchconff) {
    namenode= findnamenode(searchconff->name, 0); /* XXX */
    namenode->flags |= fnnf_old_conff;
    if (!namenode->oldhash)
      namenode->oldhash= searchconff->hash;
    debug(dbg_conffdetail, "oldconffsetflags '%s' namenode %p flags %o",
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
  pid_t pid;
  const char *u;

  u = path_skip_slash_dotslash(pathname);
  assert(*u);

  debug(dbg_eachfile, "ensure_pathname_nonexisting '%s'", pathname);
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
  pid = subproc_fork();
  if (pid == 0) {
    execlp(RM, "rm", "-rf", "--", pathname, NULL);
    ohshite(_("unable to execute %s (%s)"), _("rm command for cleanup"), RM);
  }
  debug(dbg_eachfile, "ensure_pathname_nonexisting running rm -rf '%s'",
        pathname);
  subproc_wait_check(pid, "rm cleanup", 0);
}

void
log_action(const char *action, struct pkginfo *pkg, struct pkgbin *pkgbin)
{
  log_message("%s %s %s %s", action, pkgbin_name(pkg, pkgbin, pnaw_always),
	      versiondescribe(&pkg->installed.version, vdew_nonambig),
	      versiondescribe(&pkg->available.version, vdew_nonambig));
  statusfd_send("processing: %s: %s", action,
                pkgbin_name(pkg, pkgbin, pnaw_nonambig));
}
