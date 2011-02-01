/*
 * dpkg - main program for package management
 * remove.c - functionality for removing packages
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

#include <errno.h>
#include <ctype.h>
#include <string.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/dir.h>
#include <dpkg/options.h>
#include <dpkg/triglib.h>

#include "infodb.h"
#include "filesdb.h"
#include "main.h"

/*
 * pkgdepcheck may be a virtual pkg.
 */
static void checkforremoval(struct pkginfo *pkgtoremove,
                            struct pkgset *pkgdepcheck,
                            int *rokp, struct varbuf *raemsgs) {
  struct deppossi *possi;
  struct pkginfo *depender;
  int before, ok;

  for (possi = pkgdepcheck->depended.installed; possi; possi = possi->rev_next) {
    if (possi->up->type != dep_depends && possi->up->type != dep_predepends) continue;
    depender= possi->up->up;
    debug(dbg_depcon, "checking depending package `%s'", depender->set->name);
    if (!(depender->status == stat_installed ||
          depender->status == stat_triggerspending ||
          depender->status == stat_triggersawaited))
      continue;
    if (ignore_depends(depender)) {
      debug(dbg_depcon, "ignoring depending package '%s'", depender->set->name);
      continue;
    }
    if (dependtry > 1) { if (findbreakcycle(pkgtoremove)) sincenothing= 0; }
    before= raemsgs->used;
    ok= dependencies_ok(depender,pkgtoremove,raemsgs);
    if (ok == 0 && depender->clientdata->istobe == itb_remove) ok= 1;
    if (ok == 1)
      /* Don't burble about reasons for deferral. */
      varbuf_trunc(raemsgs, before);
    if (ok < *rokp) *rokp= ok;
  }
}

void deferred_remove(struct pkginfo *pkg) {
  struct varbuf raemsgs = VARBUF_INIT;
  int rok;
  struct dependency *dep;

  debug(dbg_general, "deferred_remove package %s", pkg->set->name);

  if (pkg->status == stat_notinstalled) {
    warning(_("ignoring request to remove %.250s which isn't installed."),
            pkg->set->name);
    pkg->clientdata->istobe= itb_normal;
    return;
  } else if (!f_pending &&
             pkg->status == stat_configfiles &&
             cipaction->arg_int != act_purge) {
    warning(_("ignoring request to remove %.250s, only the config\n"
              " files of which are on the system. Use --purge to remove them too."),
            pkg->set->name);
    pkg->clientdata->istobe= itb_normal;
    return;
  }

  if (pkg->installed.essential && pkg->status != stat_configfiles)
    forcibleerr(fc_removeessential, _("This is an essential package -"
                " it should not be removed."));

  if (!f_pending)
    pkg->want = (cipaction->arg_int == act_purge) ? want_purge : want_deinstall;
  if (!f_noact) modstatdb_note(pkg);

  debug(dbg_general, "checking dependencies for remove `%s'", pkg->set->name);
  rok= 2;
  checkforremoval(pkg, pkg->set, &rok, &raemsgs);
  for (dep= pkg->installed.depends; dep; dep= dep->next) {
    if (dep->type != dep_provides) continue;
    debug(dbg_depcon,"checking virtual package `%s'",dep->list->ed->name);
    checkforremoval(pkg, dep->list->ed, &rok, &raemsgs);
  }

  if (rok == 1) {
    varbuf_destroy(&raemsgs);
    pkg->clientdata->istobe= itb_remove;
    add_to_queue(pkg);
    return;
  } else if (rok == 0) {
    sincenothing= 0;
    varbuf_end_str(&raemsgs);
    fprintf(stderr,
            _("dpkg: dependency problems prevent removal of %s:\n%s"),
            pkg->set->name, raemsgs.buf);
    ohshit(_("dependency problems - not removing"));
  } else if (raemsgs.used) {
    varbuf_end_str(&raemsgs);
    fprintf(stderr,
            _("dpkg: %s: dependency problems, but removing anyway as you requested:\n%s"),
            pkg->set->name, raemsgs.buf);
  }
  varbuf_destroy(&raemsgs);
  sincenothing= 0;

  if (pkg->eflag & eflag_reinstreq)
    forcibleerr(fc_removereinstreq,
                _("Package is in a very bad inconsistent state - you should\n"
                " reinstall it before attempting a removal."));

  ensure_allinstfiles_available();
  filesdbinit();

  if (f_noact) {
    printf(_("Would remove or purge %s ...\n"), pkg->set->name);
    pkg->status= stat_notinstalled;
    pkg->clientdata->istobe= itb_normal;
    return;
  }

  oldconffsetflags(pkg->installed.conffiles);

  printf(_("Removing %s ...\n"), pkg->set->name);
  log_action("remove", pkg);
  trig_activate_packageprocessing(pkg);
  if (pkg->status >= stat_halfconfigured) {
    static enum pkgstatus oldpkgstatus;

    oldpkgstatus= pkg->status;
    pkg->status= stat_halfconfigured;
    modstatdb_note(pkg);
    push_cleanup(cu_prermremove, ~ehflag_normaltidy, NULL, 0, 2,
                 (void *)pkg, (void *)&oldpkgstatus);
    maintainer_script_installed(pkg, PRERMFILE, "pre-removal",
                                "remove", NULL);

    /* Will turn into ‘half-installed’ soon ... */
    pkg->status = stat_unpacked;
  }

  removal_bulk(pkg);
}

static void push_leftover(struct fileinlist **leftoverp,
                          struct filenamenode *namenode) {
  struct fileinlist *newentry;
  newentry= nfmalloc(sizeof(struct fileinlist));
  newentry->next= *leftoverp;
  newentry->namenode= namenode;
  *leftoverp= newentry;
}

static void
removal_bulk_remove_file(const char *filename, const char *filetype)
{
  /* We need the postrm and list files for --purge. */
  if (strcmp(filetype, LISTFILE) == 0 ||
      strcmp(filetype, POSTRMFILE) == 0)
    return;

  debug(dbg_stupidlyverbose, "removal_bulk info not postrm or list");

  if (unlink(filename))
    ohshite(_("unable to delete control info file `%.250s'"), filename);

  debug(dbg_scripts, "removal_bulk info unlinked %s", filename);
}

static void
removal_bulk_remove_files(struct pkginfo *pkg)
{
  int before;
  struct reversefilelistiter rlistit;
  struct fileinlist *leftover;
  struct filenamenode *namenode;
  static struct varbuf fnvb;
  struct stat stab;

    pkg->status= stat_halfinstalled;
    modstatdb_note(pkg);
    push_checkpoint(~ehflag_bombout, ehflag_normaltidy);

    reversefilelist_init(&rlistit,pkg->clientdata->files);
    leftover = NULL;
    while ((namenode= reversefilelist_next(&rlistit))) {
      struct filenamenode *usenode;

      debug(dbg_eachfile, "removal_bulk `%s' flags=%o",
            namenode->name, namenode->flags);
      if (namenode->flags & fnnf_old_conff) {
        push_leftover(&leftover,namenode);
        continue;
      }

      usenode = namenodetouse(namenode, pkg);
      trig_file_activate(usenode, pkg);

      varbuf_reset(&fnvb);
      varbuf_add_str(&fnvb, instdir);
      varbuf_add_str(&fnvb, usenode->name);
      before= fnvb.used;

      varbuf_add_str(&fnvb, DPKGTEMPEXT);
      varbuf_end_str(&fnvb);
      debug(dbg_eachfiledetail, "removal_bulk cleaning temp `%s'", fnvb.buf);

      ensure_pathname_nonexisting(fnvb.buf);

      varbuf_trunc(&fnvb, before);
      varbuf_add_str(&fnvb, DPKGNEWEXT);
      varbuf_end_str(&fnvb);
      debug(dbg_eachfiledetail, "removal_bulk cleaning new `%s'", fnvb.buf);
      ensure_pathname_nonexisting(fnvb.buf);

      varbuf_trunc(&fnvb, before);
      varbuf_end_str(&fnvb);
      if (!stat(fnvb.buf,&stab) && S_ISDIR(stab.st_mode)) {
        debug(dbg_eachfiledetail, "removal_bulk is a directory");
        /* Only delete a directory or a link to one if we're the only
         * package which uses it. Other files should only be listed
         * in this package (but we don't check). */
        if (dir_has_conffiles(namenode, pkg)) {
	  push_leftover(&leftover,namenode);
	  continue;
	}
        if (dir_is_used_by_pkg(namenode, pkg, leftover)) {
          push_leftover(&leftover, namenode);
          continue;
        }
        if (dir_is_used_by_others(namenode, pkg))
          continue;
      }
      debug(dbg_eachfiledetail, "removal_bulk removing `%s'", fnvb.buf);
      if (!rmdir(fnvb.buf) || errno == ENOENT || errno == ELOOP) continue;
      if (errno == ENOTEMPTY || errno == EEXIST) {
	debug(dbg_eachfiledetail, "removal_bulk `%s' was not empty, will try again later",
	      fnvb.buf);
        push_leftover(&leftover,namenode);
        continue;
      } else if (errno == EBUSY || errno == EPERM) {
        warning(_("while removing %.250s, unable to remove directory '%.250s': "
                  "%s - directory may be a mount point?"),
                pkg->set->name, namenode->name, strerror(errno));
        push_leftover(&leftover,namenode);
        continue;
      } else if (errno == EINVAL && strcmp(usenode->name, "/.") == 0) {
        debug(dbg_eachfiledetail, "removal_bulk '%s' root directory, cannot remove",
              fnvb.buf);
        push_leftover(&leftover, namenode);
        continue;
      }
      if (errno != ENOTDIR) ohshite(_("cannot remove `%.250s'"),fnvb.buf);
      debug(dbg_eachfiledetail, "removal_bulk unlinking `%s'", fnvb.buf);
      if (secure_unlink(fnvb.buf))
        ohshite(_("unable to securely remove '%.250s'"), fnvb.buf);
    }
    write_filelist_except(pkg, &pkg->installed, leftover, 0);
    maintainer_script_installed(pkg, POSTRMFILE, "post-removal",
                                "remove", NULL);

    trig_parse_ci(pkgadminfile(pkg, &pkg->installed, TRIGGERSCIFILE),
                  trig_cicb_interest_delete, NULL, pkg);
    trig_file_interests_save();

    debug(dbg_general, "removal_bulk cleaning info directory");
    pkg_infodb_foreach(pkg, &pkg->installed, removal_bulk_remove_file);
    dir_sync_path(pkgadmindir());

    pkg->status= stat_configfiles;
    pkg->installed.essential = false;
    modstatdb_note(pkg);
    push_checkpoint(~ehflag_bombout, ehflag_normaltidy);
}

static void removal_bulk_remove_leftover_dirs(struct pkginfo *pkg) {
  struct reversefilelistiter rlistit;
  struct fileinlist *leftover;
  struct filenamenode *namenode;
  static struct varbuf fnvb;
  struct stat stab;

  /* We may have modified this previously. */
  ensure_packagefiles_available(pkg);

  modstatdb_note(pkg);
  push_checkpoint(~ehflag_bombout, ehflag_normaltidy);

  reversefilelist_init(&rlistit,pkg->clientdata->files);
  leftover = NULL;
  while ((namenode= reversefilelist_next(&rlistit))) {
    struct filenamenode *usenode;

    debug(dbg_eachfile, "removal_bulk `%s' flags=%o",
          namenode->name, namenode->flags);
    if (namenode->flags & fnnf_old_conff) {
      /* This can only happen if removal_bulk_remove_configfiles() got
       * interrupted half way. */
      debug(dbg_eachfiledetail, "removal_bulk expecting only left over dirs, "
                                "ignoring conffile '%s'", namenode->name);
      continue;
    }

    usenode = namenodetouse(namenode, pkg);
    trig_file_activate(usenode, pkg);

    varbuf_reset(&fnvb);
    varbuf_add_str(&fnvb, instdir);
    varbuf_add_str(&fnvb, usenode->name);
    varbuf_end_str(&fnvb);

    if (!stat(fnvb.buf,&stab) && S_ISDIR(stab.st_mode)) {
      debug(dbg_eachfiledetail, "removal_bulk is a directory");
      /* Only delete a directory or a link to one if we're the only
       * package which uses it. Other files should only be listed
       * in this package (but we don't check). */
      if (dir_is_used_by_pkg(namenode, pkg, leftover)) {
        push_leftover(&leftover, namenode);
        continue;
      }
      if (dir_is_used_by_others(namenode, pkg))
        continue;
    }

    debug(dbg_eachfiledetail, "removal_bulk removing `%s'", fnvb.buf);
    if (!rmdir(fnvb.buf) || errno == ENOENT || errno == ELOOP) continue;
    if (errno == ENOTEMPTY || errno == EEXIST) {
      warning(_("while removing %.250s, directory '%.250s' not empty so not removed."),
              pkg->set->name, namenode->name);
      push_leftover(&leftover,namenode);
      continue;
    } else if (errno == EBUSY || errno == EPERM) {
      warning(_("while removing %.250s, unable to remove directory '%.250s': "
                "%s - directory may be a mount point?"),
              pkg->set->name, namenode->name, strerror(errno));
      push_leftover(&leftover,namenode);
      continue;
    } else if (errno == EINVAL && strcmp(usenode->name, "/.") == 0) {
      debug(dbg_eachfiledetail, "removal_bulk '%s' root directory, cannot remove",
            fnvb.buf);
      push_leftover(&leftover, namenode);
      continue;
    }
    if (errno != ENOTDIR) ohshite(_("cannot remove `%.250s'"),fnvb.buf);

    if (lstat(fnvb.buf, &stab) == 0 && S_ISLNK(stab.st_mode)) {
      debug(dbg_eachfiledetail, "removal_bulk is a symlink to a directory");

      if (unlink(fnvb.buf))
        ohshite(_("cannot remove '%.250s'"), fnvb.buf);

      continue;
    }

    push_leftover(&leftover,namenode);
    continue;
  }
  write_filelist_except(pkg, &pkg->installed, leftover, 0);

  modstatdb_note(pkg);
  push_checkpoint(~ehflag_bombout, ehflag_normaltidy);
}

static void removal_bulk_remove_configfiles(struct pkginfo *pkg) {
  static const char *const removeconffexts[] = { REMOVECONFFEXTS, NULL };
  int r, removevbbase;
  int conffnameused, conffbasenamelen;
  char *conffbasename;
  struct conffile *conff, **lconffp;
  struct fileinlist *searchfile;
  DIR *dsd;
  struct dirent *de;
  char *p;
  const char *const *ext;

    printf(_("Purging configuration files for %s ...\n"), pkg->set->name);
    log_action("purge", pkg);
    trig_activate_packageprocessing(pkg);

    /* We may have modified this above. */
    ensure_packagefiles_available(pkg);

    /* We're about to remove the configuration, so remove the note
     * about which version it was ... */
    blankversion(&pkg->configversion);
    modstatdb_note(pkg);

    /* Remove from our list any conffiles that aren't ours any more or
     * are involved in diversions, except if we are the package doing the
     * diverting. */
    for (lconffp = &pkg->installed.conffiles; (conff = *lconffp) != NULL; ) {
      for (searchfile= pkg->clientdata->files;
           searchfile && strcmp(searchfile->namenode->name,conff->name);
           searchfile= searchfile->next);
      if (!searchfile) {
        debug(dbg_conff,"removal_bulk conffile not ours any more `%s'",conff->name);
        *lconffp= conff->next;
      } else if (searchfile->namenode->divert &&
                 (searchfile->namenode->divert->camefrom ||
                  (searchfile->namenode->divert->useinstead &&
                   searchfile->namenode->divert->pkgset != pkg->set))) {
        debug(dbg_conff, "removal_bulk conffile '%s' ignored due to diversion",
              conff->name);
        *lconffp= conff->next;
      } else {
        debug(dbg_conffdetail,"removal_bulk set to new conffile `%s'",conff->name);
        conff->hash = NEWCONFFILEFLAG;
        lconffp= &conff->next;
      }
    }
    modstatdb_note(pkg);

    for (conff= pkg->installed.conffiles; conff; conff= conff->next) {
    static struct varbuf fnvb, removevb;
      if (conff->obsolete) {
	debug(dbg_conffdetail, "removal_bulk conffile obsolete %s",
	      conff->name);
      }
      varbuf_reset(&fnvb);
      r= conffderef(pkg, &fnvb, conff->name);
      debug(dbg_conffdetail, "removal_bulk conffile `%s' (= `%s')",
            conff->name, r == -1 ? "<r==-1>" : fnvb.buf);
      if (r == -1) continue;
      conffnameused = fnvb.used;
      if (unlink(fnvb.buf) && errno != ENOENT && errno != ENOTDIR)
        ohshite(_("cannot remove old config file `%.250s' (= `%.250s')"),
                conff->name, fnvb.buf);
      p= strrchr(fnvb.buf,'/'); if (!p) continue;
      *p = '\0';
      varbuf_reset(&removevb);
      varbuf_add_str(&removevb, fnvb.buf);
      varbuf_add_char(&removevb, '/');
      removevbbase= removevb.used;
      varbuf_end_str(&removevb);
      dsd= opendir(removevb.buf);
      if (!dsd) {
        int e=errno;
        debug(dbg_conffdetail, "removal_bulk conffile no dsd %s %s",
              fnvb.buf, strerror(e)); errno= e;
        if (errno == ENOENT || errno == ENOTDIR) continue;
        ohshite(_("cannot read config file dir `%.250s' (from `%.250s')"),
                fnvb.buf, conff->name);
      }
      debug(dbg_conffdetail, "removal_bulk conffile cleaning dsd %s", fnvb.buf);
      push_cleanup(cu_closedir, ~0, NULL, 0, 1, (void *)dsd);
      *p= '/';
      conffbasenamelen= strlen(++p);
      conffbasename= fnvb.buf+conffnameused-conffbasenamelen;
      while ((de = readdir(dsd)) != NULL) {
        debug(dbg_stupidlyverbose, "removal_bulk conffile dsd entry=`%s'"
              " conffbasename=`%s' conffnameused=%d conffbasenamelen=%d",
              de->d_name, conffbasename, conffnameused, conffbasenamelen);
        if (!strncmp(de->d_name,conffbasename,conffbasenamelen)) {
          debug(dbg_stupidlyverbose, "removal_bulk conffile dsd entry starts right");
          for (ext= removeconffexts; *ext; ext++)
            if (!strcmp(*ext,de->d_name+conffbasenamelen)) goto yes_remove;
          p= de->d_name+conffbasenamelen;
          if (*p++ == '~') {
            while (*p && cisdigit(*p)) p++;
            if (*p == '~' && !*++p) goto yes_remove;
          }
        }
        debug(dbg_stupidlyverbose, "removal_bulk conffile dsd entry starts wrong");
        if (de->d_name[0] == '#' &&
            !strncmp(de->d_name+1,conffbasename,conffbasenamelen) &&
            !strcmp(de->d_name+1+conffbasenamelen,"#"))
          goto yes_remove;
        debug(dbg_stupidlyverbose, "removal_bulk conffile dsd entry not it");
        continue;
      yes_remove:
        varbuf_trunc(&removevb, removevbbase);
        varbuf_add_str(&removevb, de->d_name);
        varbuf_end_str(&removevb);
        debug(dbg_conffdetail, "removal_bulk conffile dsd entry removing `%s'",
              removevb.buf);
        if (unlink(removevb.buf) && errno != ENOENT && errno != ENOTDIR)
          ohshite(_("cannot remove old backup config file `%.250s' (of `%.250s')"),
                  removevb.buf, conff->name);
      }
      pop_cleanup(ehflag_normaltidy); /* closedir */
    }

    /* Remove the conffiles from the file list file. */
    write_filelist_except(pkg, &pkg->installed, pkg->clientdata->files,
                          fnnf_old_conff);

    pkg->installed.conffiles = NULL;
    modstatdb_note(pkg);

    maintainer_script_installed(pkg, POSTRMFILE, "post-removal",
                                "purge", NULL);
}

/*
 * This is used both by deferred_remove() in this file, and at the end of
 * process_archive() in archives.c if it needs to finish removing a
 * conflicting package.
 */
void removal_bulk(struct pkginfo *pkg) {
  bool foundpostrm;

  debug(dbg_general, "removal_bulk package %s", pkg->set->name);

  if (pkg->status == stat_halfinstalled || pkg->status == stat_unpacked) {
    removal_bulk_remove_files(pkg);
  }

  foundpostrm = pkg_infodb_has_file(pkg, &pkg->installed, POSTRMFILE);

  debug(dbg_general, "removal_bulk purging? foundpostrm=%d",foundpostrm);

  if (!foundpostrm && !pkg->installed.conffiles) {
    /* If there are no config files and no postrm script then we
     * go straight into ‘purge’.  */
    debug(dbg_general, "removal_bulk no postrm, no conffiles, purging");
    pkg->want= want_purge;

    blankversion(&pkg->configversion);
  } else if (pkg->want == want_purge) {

    removal_bulk_remove_configfiles(pkg);

  }

  /* I.e., either of the two branches above. */
  if (pkg->want == want_purge) {
    const char *filename;

    /* Retry empty directories, and warn on any leftovers that aren't. */
    removal_bulk_remove_leftover_dirs(pkg);

    filename = pkgadminfile(pkg, &pkg->installed, LISTFILE);
    debug(dbg_general, "removal_bulk purge done, removing list `%s'",
          filename);
    if (unlink(filename) && errno != ENOENT)
      ohshite(_("cannot remove old files list"));

    filename = pkgadminfile(pkg, &pkg->installed, POSTRMFILE);
    debug(dbg_general, "removal_bulk purge done, removing postrm `%s'",
          filename);
    if (unlink(filename) && errno != ENOENT)
      ohshite(_("can't remove old postrm script"));

    pkg->status= stat_notinstalled;
    pkg->want = want_unknown;

    /* This will mess up reverse links, but if we follow them
     * we won't go back because pkg->status is stat_notinstalled. */
    pkgbin_blank(&pkg->installed);
  }

  pkg->eflag = eflag_ok;
  modstatdb_note(pkg);

  debug(dbg_general, "removal done");
}
