/*
 * dpkg - main program for package management
 * cleanup.c - cleanup functions, used when we need to unwind
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

#include <errno.h>
#include <ctype.h>
#include <string.h>
#include <time.h>
#include <utime.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/pkg.h>
#include <dpkg/options.h>

#include "filesdb.h"
#include "main.h"
#include "archives.h"

int cleanup_pkg_failed=0, cleanup_conflictor_failed=0;

/**
 * Something went wrong and we're undoing.
 *
 * We have the following possible situations for non-conffiles:
 *   <foo>.dpkg-tmp exists - in this case we want to remove
 *    <foo> if it exists and replace it with <foo>.dpkg-tmp.
 *    This undoes the backup operation.
 *   <foo>.dpkg-tmp does not exist - <foo> may be on the disk,
 *    as a new file which didn't fail, remove it if it is.
 *
 * In both cases, we also make sure we delete <foo>.dpkg-new in
 * case that's still hanging around.
 *
 * For conffiles, we simply delete <foo>.dpkg-new. For these,
 * <foo>.dpkg-tmp shouldn't exist, as we don't make a backup
 * at this stage. Just to be on the safe side, though, we don't
 * look for it.
 */
void cu_installnew(int argc, void **argv) {
  struct filenamenode *namenode = argv[0];
  struct stat stab;

  cleanup_pkg_failed++; cleanup_conflictor_failed++;

  debug(dbg_eachfile,"cu_installnew `%s' flags=%o",namenode->name,namenode->flags);

  setupfnamevbs(namenode->name);

  if (!(namenode->flags & fnnf_new_conff) && !lstat(fnametmpvb.buf,&stab)) {
    /* OK, <foo>.dpkg-tmp exists. Remove <foo> and
     * restore <foo>.dpkg-tmp ... */
    if (namenode->flags & fnnf_no_atomic_overwrite) {
      /* If we can't do an atomic overwrite we have to delete first any
       * link to the new version we may have created. */
      debug(dbg_eachfiledetail,"cu_installnew restoring nonatomic");
      if (secure_remove(fnamevb.buf) && errno != ENOENT && errno != ENOTDIR)
        ohshite(_("unable to remove newly-installed version of `%.250s' to allow"
                " reinstallation of backup copy"),namenode->name);
    } else {
      debug(dbg_eachfiledetail,"cu_installnew restoring atomic");
    }
    /* Either we can do an atomic restore, or we've made room: */
    if (rename(fnametmpvb.buf,fnamevb.buf))
      ohshite(_("unable to restore backup version of `%.250s'"),namenode->name);
    /* If <foo>.dpkg-tmp was still a hard link to <foo>, then the atomic
     * rename did nothing, so we make sure to remove the backup. */
    else if (unlink(fnametmpvb.buf) && errno != ENOENT)
      ohshite(_("unable to remove backup copy of '%.250s'"), namenode->name);
  } else if (namenode->flags & fnnf_placed_on_disk) {
    debug(dbg_eachfiledetail,"cu_installnew removing new file");
    if (secure_remove(fnamevb.buf) && errno != ENOENT && errno != ENOTDIR)
      ohshite(_("unable to remove newly-installed version of `%.250s'"),
	      namenode->name);
  } else {
    debug(dbg_eachfiledetail,"cu_installnew not restoring");
  }
  /* Whatever, we delete <foo>.dpkg-new now, if it still exists. */
  if (secure_remove(fnamenewvb.buf) && errno != ENOENT && errno != ENOTDIR)
    ohshite(_("unable to remove newly-extracted version of `%.250s'"),namenode->name);

  cleanup_pkg_failed--; cleanup_conflictor_failed--;
}

void cu_prermupgrade(int argc, void **argv) {
  struct pkginfo *pkg= (struct pkginfo*)argv[0];

  if (cleanup_pkg_failed++) return;
  maintainer_script_postinst(pkg, "abort-upgrade",
                             versiondescribe(&pkg->available.version,
                                             vdew_nonambig),
                             NULL);
  pkg_clear_eflags(pkg, eflag_reinstreq);
  post_postinst_tasks(pkg, stat_installed);
  cleanup_pkg_failed--;
}

/*
 * Also has conflictor in argv[1] and infavour in argv[2].
 * conflictor may be NULL if deconfigure was due to Breaks.
 */
void ok_prermdeconfigure(int argc, void **argv) {
  struct pkginfo *deconf= (struct pkginfo*)argv[0];

  if (cipaction->arg_int == act_install)
    add_to_queue(deconf);
}

/*
 * conflictor may be NULL.
 */
void cu_prermdeconfigure(int argc, void **argv) {
  struct pkginfo *deconf= (struct pkginfo*)argv[0];
  struct pkginfo *conflictor = (struct pkginfo *)argv[1];
  struct pkginfo *infavour= (struct pkginfo*)argv[2];

  if (conflictor) {
    maintainer_script_postinst(deconf, "abort-deconfigure",
                               "in-favour",
                               pkgbin_name(infavour, &infavour->available,
                                           pnaw_nonambig),
                               versiondescribe(&infavour->available.version,
                                               vdew_nonambig),
                               "removing",
                               pkg_name(conflictor, pnaw_nonambig),
                               versiondescribe(&conflictor->installed.version,
                                               vdew_nonambig),
                               NULL);
  } else {
    maintainer_script_postinst(deconf, "abort-deconfigure",
                               "in-favour",
                               pkgbin_name(infavour, &infavour->available,
                                           pnaw_nonambig),
                               versiondescribe(&infavour->available.version,
                                               vdew_nonambig),
                               NULL);
  }

  post_postinst_tasks(deconf, stat_installed);
}

void cu_prerminfavour(int argc, void **argv) {
  struct pkginfo *conflictor= (struct pkginfo*)argv[0];
  struct pkginfo *infavour= (struct pkginfo*)argv[1];

  if (cleanup_conflictor_failed++) return;
  maintainer_script_postinst(conflictor, "abort-remove",
                             "in-favour",
                             pkgbin_name(infavour, &infavour->available,
                                         pnaw_nonambig),
                             versiondescribe(&infavour->available.version,
                                             vdew_nonambig),
                             NULL);
  pkg_clear_eflags(conflictor, eflag_reinstreq);
  post_postinst_tasks(conflictor, stat_installed);
  cleanup_conflictor_failed--;
}

void cu_preinstverynew(int argc, void **argv) {
  struct pkginfo *pkg= (struct pkginfo*)argv[0];
  char *cidir= (char*)argv[1];
  char *cidirrest= (char*)argv[2];

  if (cleanup_pkg_failed++) return;
  maintainer_script_new(pkg, POSTRMFILE, "post-removal", cidir, cidirrest,
                        "abort-install", NULL);
  pkg_set_status(pkg, stat_notinstalled);
  pkg_clear_eflags(pkg, eflag_reinstreq);
  pkgbin_blank(&pkg->installed);
  modstatdb_note(pkg);
  cleanup_pkg_failed--;
}

void cu_preinstnew(int argc, void **argv) {
  struct pkginfo *pkg= (struct pkginfo*)argv[0];
  char *cidir= (char*)argv[1];
  char *cidirrest= (char*)argv[2];

  if (cleanup_pkg_failed++) return;
  maintainer_script_new(pkg, POSTRMFILE, "post-removal", cidir, cidirrest,
                        "abort-install", versiondescribe(&pkg->installed.version,
                                                         vdew_nonambig),
                        NULL);
  pkg_set_status(pkg, stat_configfiles);
  pkg_clear_eflags(pkg, eflag_reinstreq);
  modstatdb_note(pkg);
  cleanup_pkg_failed--;
}

void cu_preinstupgrade(int argc, void **argv) {
  struct pkginfo *pkg= (struct pkginfo*)argv[0];
  char *cidir= (char*)argv[1];
  char *cidirrest= (char*)argv[2];
  enum pkgstatus *oldstatusp= (enum pkgstatus*)argv[3];

  if (cleanup_pkg_failed++) return;
  maintainer_script_new(pkg, POSTRMFILE, "post-removal", cidir, cidirrest,
                        "abort-upgrade",
                        versiondescribe(&pkg->installed.version,
                                        vdew_nonambig),
                        NULL);
  pkg_set_status(pkg, *oldstatusp);
  pkg_clear_eflags(pkg, eflag_reinstreq);
  modstatdb_note(pkg);
  cleanup_pkg_failed--;
}

void cu_postrmupgrade(int argc, void **argv) {
  struct pkginfo *pkg= (struct pkginfo*)argv[0];

  if (cleanup_pkg_failed++) return;
  maintainer_script_installed(pkg,PREINSTFILE,"pre-installation",
                              "abort-upgrade", versiondescribe(&pkg->available.version,
                                                               vdew_nonambig),
                              NULL);
  cleanup_pkg_failed--;
}

void cu_prermremove(int argc, void **argv) {
  struct pkginfo *pkg= (struct pkginfo*)argv[0];
  enum pkgstatus *oldpkgstatus= (enum pkgstatus*)argv[1];

  if (cleanup_pkg_failed++) return;
  maintainer_script_postinst(pkg, "abort-remove", NULL);
  pkg_clear_eflags(pkg, eflag_reinstreq);
  post_postinst_tasks(pkg, *oldpkgstatus);
  cleanup_pkg_failed--;
}
