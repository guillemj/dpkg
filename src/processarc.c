/*
 * dpkg - main program for package management
 * processarc.c - the huge function process_archive
 *
 * Copyright © 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2006-2011 Guillem Jover <guillem@debian.org>
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
#include <ctype.h>
#include <string.h>
#include <time.h>
#include <utime.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/path.h>
#include <dpkg/buffer.h>
#include <dpkg/subproc.h>
#include <dpkg/dir.h>
#include <dpkg/tarfn.h>
#include <dpkg/myopt.h>
#include <dpkg/triglib.h>

#include "filesdb.h"
#include "main.h"
#include "archives.h"

static const char *
summarize_filename(const char *filename)
{
  const char *pfilename;
  char *pfilenamebuf;

  for (pfilename = filename;
       pfilename && strlen(pfilename) > 30 && strchr(pfilename, '/') != NULL;
       pfilename++)
    pfilename = strchr(pfilename, '/');

  if (pfilename && pfilename != filename) {
    pfilenamebuf = nfmalloc(strlen(pfilename) + 5);
    sprintf(pfilenamebuf, _(".../%s"), pfilename);
    pfilename = pfilenamebuf;
  } else {
    pfilename = filename;
  }

  return pfilename;
}

static bool
deb_reassemble(const char **filename, const char **pfilename)
{
  static char *reasmbuf = NULL;
  struct stat stab;
  int status;
  pid_t pid;

  if (!reasmbuf)
    m_asprintf(&reasmbuf, "%s/%s", admindir, REASSEMBLETMP);
  if (unlink(reasmbuf) && errno != ENOENT)
    ohshite(_("error ensuring `%.250s' doesn't exist"), reasmbuf);

  push_cleanup(cu_pathname, ~0, NULL, 0, 1, (void *)reasmbuf);

  pid = subproc_fork();
  if (!pid) {
    execlp(SPLITTER, SPLITTER, "-Qao", reasmbuf, *filename, NULL);
    ohshite(_("unable to execute %s (%s)"),
            _("split package reassembly"), SPLITTER);
  }
  status = subproc_wait(pid, SPLITTER);
  switch (WIFEXITED(status) ? WEXITSTATUS(status) : -1) {
  case 0:
    /* It was a part - is it complete? */
    if (!stat(reasmbuf, &stab)) {
      /* Yes. */
      *filename = reasmbuf;
      *pfilename = _("reassembled package file");
      break;
    } else if (errno == ENOENT) {
      /* No. That's it, we skip it. */
      return false;
    }
  case 1:
    /* No, it wasn't a part. */
    break;
  default:
    subproc_check(status, SPLITTER, 0);
  }

  return true;
}

static void
deb_verify(const char *filename)
{
  struct stat stab;
  pid_t pid;

  if (stat(DEBSIGVERIFY, &stab) < 0)
    return;

  printf(_("Authenticating %s ...\n"), filename);
  fflush(stdout);
  pid = subproc_fork();
  if (!pid) {
    execl(DEBSIGVERIFY, DEBSIGVERIFY, "-q", filename, NULL);
    ohshite(_("unable to execute %s (%s)"),
            _("package signature verification"), DEBSIGVERIFY);
  } else {
    int status;

    status = subproc_wait(pid, "debsig-verify");
    if (!(WIFEXITED(status) && WEXITSTATUS(status) == 0)) {
      if (!fc_badverify)
        ohshit(_("Verification on package %s failed!"), filename);
      else
        fprintf(stderr, _("Verification on package %s failed,\n"
                          "but installing anyway as you requested.\n"),
                filename);
    } else {
      printf(_("passed\n"));
    }
  }
}

#define MAXCONFLICTORS 20

static struct pkginfo *conflictor[MAXCONFLICTORS];
static int cflict_index = 0;

void
push_conflictor(struct pkginfo *pkg, struct pkginfo *pkg_fixbyrm)
{
  if (cflict_index >= MAXCONFLICTORS)
    ohshit(_("package %s has too many Conflicts/Replaces pairs"), pkg->name);

  conflictor[cflict_index++] = pkg_fixbyrm;
}

struct match_node {
  struct match_node *next;
  char *filetype;
  char *filename;
};

static struct match_node *
match_node_new(const char *name, const char *type, struct match_node *next)
{
  struct match_node *node;

  node = m_malloc(sizeof(*node));
  node->next = next;
  node->filename = m_strdup(name);
  node->filetype = m_strdup(type);

  return node;
}

static void
match_node_free(struct match_node *node)
{
  free(node->filetype);
  free(node->filename);
  free(node);
}

void process_archive(const char *filename) {
  static const struct tar_operations tf = {
    .read = tarfileread,
    .extract_file = tarobject,
    .link = tarobject,
    .symlink = tarobject,
    .mkdir = tarobject,
    .mknod = tarobject,
  };

  /* These need to be static so that we can pass their addresses to
   * push_cleanup as arguments to the cu_xxx routines; if an error occurs
   * we unwind the stack before processing the cleanup list, and these
   * variables had better still exist ... */
  static int p1[2];
  static char *cidir = NULL;
  static struct fileinlist *newconffiles, *newfileslist;
  static enum pkgstatus oldversionstatus;
  static struct varbuf infofnvb, fnvb, depprobwhy;
  static struct tarcontext tc;

  int r, i, infodirlen, infodirbaseused;
  pid_t pid;
  struct pkgiterator *it;
  struct pkginfo *pkg, *otherpkg, *divpkg;
  char *cidirrest, *p;
  char conffilenamebuf[MAXCONFFILENAME];
  char *psize;
  const char *pfilename, *newinfofilename;
  struct fileinlist *newconff, **newconffileslastp;
  struct fileinlist *cfile;
  struct reversefilelistiter rlistit;
  struct conffile *searchconff, **iconffileslastp, *newiconff;
  struct dependency *dsearch, *newdeplist, **newdeplistlastp;
  struct dependency *newdep, *dep, *providecheck;
  struct deppossi *psearch, **newpossilastp, *possi, *newpossi, *pdep;
  FILE *conff;
  DIR *dsd;
  struct filenamenode *namenode;
  struct dirent *de;
  struct stat stab, oldfs;
  struct pkg_deconf_list *deconpil, *deconpiltemp;
  struct match_node *match_head = NULL, *match_node = NULL;

  cleanup_pkg_failed= cleanup_conflictor_failed= 0;

  pfilename = summarize_filename(filename);

  if (stat(filename,&stab)) ohshite(_("cannot access archive"));

  /* We can't ‘tentatively-reassemble’ packages. */
  if (!f_noact) {
    if (!deb_reassemble(&filename, &pfilename))
      return;
  }

  /* Verify the package. */
  if (!f_nodebsig)
    deb_verify(filename);

  if (f_noact) {
    char *tmpdir;

    tmpdir = mkdtemp(path_make_temp_template("dpkg"));
    if (!tmpdir)
      ohshite(_("unable to create temporary directory"));

    cidir = m_realloc(cidir, strlen(tmpdir) + MAXCONTROLFILENAME + 10);
    strcpy(cidir, tmpdir);
    strcat(cidir,"/");

    cidirrest = cidir + strlen(cidir);

    free(tmpdir);
  } else {
    /* We want it to be on the same filesystem so that we can
     * use rename(2) to install the postinst &c. */
    if (!cidir)
      cidir = m_malloc(strlen(admindir) + sizeof(CONTROLDIRTMP) +
                       MAXCONTROLFILENAME + 10);
    strcpy(cidir,admindir);
    strcat(cidir, "/" CONTROLDIRTMP);

    cidirrest = cidir + strlen(cidir);

    assert(*cidir && cidirrest[-1] == '/');
    cidirrest[-1] = '\0';
    ensure_pathname_nonexisting(cidir);
    cidirrest[-1] = '/';
  }

  push_cleanup(cu_cidir, ~0, NULL, 0, 2, (void *)cidir, (void *)cidirrest);
  pid = subproc_fork();
  if (pid == 0) {
    cidirrest[-1] = '\0';
    execlp(BACKEND, BACKEND, "--control", filename, cidir, NULL);
    ohshite(_("unable to execute %s (%s)"),
            _("package control information extraction"), BACKEND);
  }
  subproc_wait_check(pid, BACKEND " --control", 0);

  /* We want to guarantee the extracted files are on the disk, so that the
   * subsequent renames to the info database do not end up with old or zero
   * length files in case of a system crash. As neither dpkg-deb nor tar do
   * explicit fsync()s, we have to do them here.
   * XXX: This could be avoided by switching to an internal tar extractor. */
  dir_sync_contents(cidir);

  strcpy(cidirrest,CONTROLFILE);

  parsedb(cidir, pdb_recordavailable | pdb_rejectstatus | pdb_ignorefiles,
          &pkg);
  if (!pkg->files) {
    pkg->files= nfmalloc(sizeof(struct filedetails));
    pkg->files->next = NULL;
    pkg->files->name = pkg->files->msdosname = pkg->files->md5sum = NULL;
  }
  /* Always nfmalloc. Otherwise, we may overwrite some other field (like
   * md5sum). */
  psize = nfmalloc(30);
  sprintf(psize, "%lu", (unsigned long)stab.st_size);
  pkg->files->size = psize;

  if (cipaction->arg_int == act_avail) {
    printf(_("Recorded info about %s from %s.\n"),pkg->name,pfilename);
    pop_cleanup(ehflag_normaltidy);
    return;
  }

  if (strcmp(pkg->available.arch, "all") &&
      strcmp(pkg->available.arch, native_arch))
    forcibleerr(fc_architecture,
                _("package architecture (%s) does not match system (%s)"),
                pkg->available.arch, native_arch);

  for (deconpil= deconfigure;
       deconpil;
       deconpil= deconpiltemp) {
    deconpiltemp= deconpil->next;
    free(deconpil);
  }
  deconfigure = NULL;
  clear_istobes();

  if (!wanttoinstall(pkg)) {
      pop_cleanup(ehflag_normaltidy);
      return;
  }

  /* Check if anything is installed that we conflict with, or not installed
   * that we need. */
  pkg->clientdata->istobe= itb_installnew;

  for (dsearch= pkg->available.depends; dsearch; dsearch= dsearch->next) {
    switch (dsearch->type) {
    case dep_conflicts:
      /* Look for things we conflict with. */
      check_conflict(dsearch, pkg, pfilename);
      break;
    case dep_breaks:
      /* Look for things we break. */
      check_breaks(dsearch, pkg, pfilename);
      break;
    case dep_provides:
      /* Look for things that conflict with what we provide. */
      for (psearch = dsearch->list->ed->installed.depended;
           psearch;
           psearch = psearch->rev_next) {
        if (psearch->up->type != dep_conflicts)
          continue;
        check_conflict(psearch->up, pkg, pfilename);
      }
      break;
    case dep_suggests:
    case dep_recommends:
    case dep_depends:
    case dep_replaces:
    case dep_enhances:
      /* Ignore these here. */
      break;
    case dep_predepends:
      if (!depisok(dsearch, &depprobwhy, NULL, true)) {
        varbuf_end_str(&depprobwhy);
        fprintf(stderr, _("dpkg: regarding %s containing %s, pre-dependency problem:\n%s"),
                pfilename, pkg->name, depprobwhy.buf);
        if (!force_depends(dsearch->list))
          ohshit(_("pre-dependency problem - not installing %.250s"),pkg->name);
        warning(_("ignoring pre-dependency problem!"));
      }
    }
  }
  /* Look for things that conflict with us. */
  for (psearch = pkg->installed.depended; psearch; psearch = psearch->rev_next) {
    if (psearch->up->type != dep_conflicts) continue;
    check_conflict(psearch->up, pkg, pfilename);
  }

  ensure_allinstfiles_available();
  filesdbinit();
  trig_file_interests_ensure();

  if (pkg->status != stat_notinstalled && pkg->status != stat_configfiles) {
    printf(_("Preparing to replace %s %s (using %s) ...\n"),
           pkg->name,
           versiondescribe(&pkg->installed.version,vdew_nonambig),
           pfilename);
    log_action("upgrade", pkg);
  } else {
    printf(_("Unpacking %s (from %s) ...\n"),pkg->name,pfilename);
    log_action("install", pkg);
  }

  if (f_noact) {
    pop_cleanup(ehflag_normaltidy);
    return;
  }

  /*
   * OK, we're going ahead.
   */

  trig_activate_packageprocessing(pkg);
  strcpy(cidirrest, TRIGGERSCIFILE);
  trig_parse_ci(cidir, NULL, trig_cicb_statuschange_activate, pkg);

  /* Read the conffiles, and copy the hashes across. */
  newconffiles = NULL;
  newconffileslastp = &newconffiles;
  push_cleanup(cu_fileslist, ~0, NULL, 0, 0);
  strcpy(cidirrest,CONFFILESFILE);
  conff= fopen(cidir,"r");
  if (conff) {
    push_cleanup(cu_closefile, ehflag_bombout, NULL, 0, 1, (void *)conff);
    while (fgets(conffilenamebuf,MAXCONFFILENAME-2,conff)) {
      struct filepackages_iterator *iter;

      p= conffilenamebuf + strlen(conffilenamebuf);
      assert(p != conffilenamebuf);
      if (p[-1] != '\n')
        ohshit(_("name of conffile (starting `%.250s') is too long (>%d characters)"),
               conffilenamebuf, MAXCONFFILENAME);
      while (p > conffilenamebuf && isspace(p[-1])) --p;
      if (p == conffilenamebuf) continue;
      *p = '\0';
      namenode= findnamenode(conffilenamebuf, 0);
      namenode->oldhash= NEWCONFFILEFLAG;
      newconff= newconff_append(&newconffileslastp, namenode);

      /* Let's see if any packages have this file. If they do we
       * check to see if they listed it as a conffile, and if they did
       * we copy the hash across. Since (for plain file conffiles,
       * which is the only kind we are supposed to have) there will
       * only be one package which ‘has’ the file, this will usually
       * mean we only look in the package which we're installing now.
       * The ‘conffiles’ data in the status file is ignored when a
       * package isn't also listed in the file ownership database as
       * having that file. If several packages are listed as owning
       * the file we pick one at random. */
      searchconff = NULL;

      iter = filepackages_iter_new(newconff->namenode);
      while ((otherpkg = filepackages_iter_next(iter))) {
        debug(dbg_conffdetail,
              "process_archive conffile `%s' in package %s - conff ?",
              newconff->namenode->name, otherpkg->name);
        for (searchconff = otherpkg->installed.conffiles;
             searchconff && strcmp(newconff->namenode->name, searchconff->name);
             searchconff = searchconff->next)
          debug(dbg_conffdetail,
                "process_archive conffile `%s' in package %s - conff ? not `%s'",
                newconff->namenode->name, otherpkg->name, searchconff->name);
        if (searchconff) {
          debug(dbg_conff,
                "process_archive conffile `%s' package=%s %s hash=%s",
                newconff->namenode->name, otherpkg->name,
                otherpkg == pkg ? "same" : "different!",
                searchconff->hash);
          if (otherpkg == pkg)
            break;
        }
      }
      filepackages_iter_free(iter);

      if (searchconff) {
        newconff->namenode->oldhash= searchconff->hash;
	/* We don't copy ‘obsolete’; it's not obsolete in the new package. */
      } else {
        debug(dbg_conff,"process_archive conffile `%s' no package, no hash",
              newconff->namenode->name);
      }
      newconff->namenode->flags |= fnnf_new_conff;
    }
    if (ferror(conff)) ohshite(_("read error in %.250s"),cidir);
    pop_cleanup(ehflag_normaltidy); /* conff = fopen() */
    if (fclose(conff)) ohshite(_("error closing %.250s"),cidir);
  } else {
    if (errno != ENOENT) ohshite(_("error trying to open %.250s"),cidir);
  }

  /* All the old conffiles are marked with a flag, so that we don't delete
   * them if they seem to disappear completely. */
  oldconffsetflags(pkg->installed.conffiles);
  for (i = 0 ; i < cflict_index ; i++) {
    oldconffsetflags(conflictor[i]->installed.conffiles);
  }

  oldversionstatus= pkg->status;

  assert(oldversionstatus <= stat_installed);
  debug(dbg_general,"process_archive oldversionstatus=%s",
        statusstrings[oldversionstatus]);

  if (oldversionstatus == stat_halfconfigured ||
      oldversionstatus == stat_triggersawaited ||
      oldversionstatus == stat_triggerspending ||
      oldversionstatus == stat_installed) {
    pkg->eflag |= eflag_reinstreq;
    pkg->status= stat_halfconfigured;
    modstatdb_note(pkg);
    push_cleanup(cu_prermupgrade, ~ehflag_normaltidy, NULL, 0, 1, (void *)pkg);
    maintainer_script_alternative(pkg, PRERMFILE, "pre-removal", cidir, cidirrest,
                                  "upgrade", "failed-upgrade");
    pkg->status= stat_unpacked;
    oldversionstatus= stat_unpacked;
    modstatdb_note(pkg);
  }

  for (deconpil= deconfigure; deconpil; deconpil= deconpil->next) {
    struct pkginfo *removing = deconpil->pkg_removal;

    if (removing)
      printf(_("De-configuring %s, to allow removal of %s ...\n"),
             deconpil->pkg->name, removing->name);
    else
      printf(_("De-configuring %s ...\n"), deconpil->pkg->name);

    trig_activate_packageprocessing(deconpil->pkg);
    deconpil->pkg->status= stat_halfconfigured;
    modstatdb_note(deconpil->pkg);

    /* This means that we *either* go and run postinst abort-deconfigure,
     * *or* queue the package for later configure processing, depending
     * on which error cleanup route gets taken. */
    push_cleanup(cu_prermdeconfigure, ~ehflag_normaltidy,
                 ok_prermdeconfigure, ehflag_normaltidy,
                 3, (void*)deconpil->pkg, (void*)removing, (void*)pkg);

    if (removing) {
      maintainer_script_installed(deconpil->pkg, PRERMFILE, "pre-removal",
                                  "deconfigure", "in-favour", pkg->name,
                                  versiondescribe(&pkg->available.version,
                                                  vdew_nonambig),
                                  "removing", removing->name,
                                  versiondescribe(&removing->installed.version,
                                                  vdew_nonambig),
                                  NULL);
    } else {
      maintainer_script_installed(deconpil->pkg, PRERMFILE, "pre-removal",
                                  "deconfigure", "in-favour", pkg->name,
                                  versiondescribe(&pkg->available.version,
                                                  vdew_nonambig),
                                  NULL);
    }
  }

  for (i = 0 ; i < cflict_index; i++) {
    if (!(conflictor[i]->status == stat_halfconfigured ||
          conflictor[i]->status == stat_triggersawaited ||
          conflictor[i]->status == stat_triggerspending ||
          conflictor[i]->status == stat_installed)) continue;
    trig_activate_packageprocessing(conflictor[i]);
    conflictor[i]->status= stat_halfconfigured;
    modstatdb_note(conflictor[i]);
    push_cleanup(cu_prerminfavour, ~ehflag_normaltidy, NULL, 0,
                 2,(void*)conflictor[i],(void*)pkg);
    maintainer_script_installed(conflictor[i], PRERMFILE, "pre-removal",
                                "remove", "in-favour", pkg->name,
                                versiondescribe(&pkg->available.version,
                                                vdew_nonambig),
                                NULL);
    conflictor[i]->status= stat_halfinstalled;
    modstatdb_note(conflictor[i]);
  }

  pkg->eflag |= eflag_reinstreq;
  if (pkg->status == stat_notinstalled)
    pkg->installed.version= pkg->available.version;
  pkg->status= stat_halfinstalled;
  modstatdb_note(pkg);
  if (oldversionstatus == stat_notinstalled) {
    push_cleanup(cu_preinstverynew, ~ehflag_normaltidy, NULL, 0,
                 3,(void*)pkg,(void*)cidir,(void*)cidirrest);
    maintainer_script_new(pkg, PREINSTFILE, "pre-installation", cidir, cidirrest,
                          "install", NULL);
  } else if (oldversionstatus == stat_configfiles) {
    push_cleanup(cu_preinstnew, ~ehflag_normaltidy, NULL, 0,
                 3,(void*)pkg,(void*)cidir,(void*)cidirrest);
    maintainer_script_new(pkg, PREINSTFILE, "pre-installation", cidir, cidirrest,
                          "install", versiondescribe(&pkg->installed.version,
                                                     vdew_nonambig),
                          NULL);
  } else {
    push_cleanup(cu_preinstupgrade, ~ehflag_normaltidy, NULL, 0,
                 4,(void*)pkg,(void*)cidir,(void*)cidirrest,(void*)&oldversionstatus);
    maintainer_script_new(pkg, PREINSTFILE, "pre-installation", cidir, cidirrest,
                          "upgrade", versiondescribe(&pkg->installed.version,
                                                     vdew_nonambig),
                          NULL);
    printf(_("Unpacking replacement %.250s ...\n"),pkg->name);
  }

  /*
   * Now we unpack the archive, backing things up as we go.
   * For each file, we check to see if it already exists.
   * There are several possibilities:
   *
   * + We are trying to install a non-directory ...
   *  - It doesn't exist. In this case we simply extract it.
   *  - It is a plain file, device, symlink, &c. We do an ‘atomic
   *    overwrite’ using link() and rename(), but leave a backup copy.
   *    Later, when we delete the backup, we remove it from any other
   *    packages' lists.
   *  - It is a directory. In this case it depends on whether we're
   *    trying to install a symlink or something else.
   *   = If we're not trying to install a symlink we move the directory
   *     aside and extract the node. Later, when we recursively remove
   *     the backed-up directory, we remove it from any other packages'
   *     lists.
   *   = If we are trying to install a symlink we do nothing - ie,
   *     dpkg will never replace a directory tree with a symlink. This
   *     is to avoid embarrassing effects such as replacing a directory
   *     tree with a link to a link to the original directory tree.
   * + We are trying to install a directory ...
   *  - It doesn't exist. We create it with the appropriate modes.
   *  - It exists as a directory or a symlink to one. We do nothing.
   *  - It is a plain file or a symlink (other than to a directory).
   *    We move it aside and create the directory. Later, when we
   *    delete the backup, we remove it from any other packages' lists.
   *
   *                   Install non-dir   Install symlink   Install dir
   *  Exists not               X               X                X
   *  File/node/symlink       LXR             LXR              BXR
   *  Directory               BXR              -                -
   *
   *    X: extract file/node/link/directory
   *   LX: atomic overwrite leaving backup
   *    B: ordinary backup
   *    R: later remove from other packages' lists
   *    -: do nothing
   *
   * After we've done this we go through the remaining things in the
   * lists of packages we're trying to remove (including the old
   * version of the current package). This happens in reverse order,
   * so that we process files before the directories (or symlinks-to-
   * directories) containing them.
   *
   * + If the thing is a conffile then we leave it alone for the purge
   *   operation.
   * + Otherwise, there are several possibilities too:
   *  - The listed thing does not exist. We ignore it.
   *  - The listed thing is a directory or a symlink to a directory.
   *    We delete it only if it isn't listed in any other package.
   *  - The listed thing is not a directory, but was part of the package
   *    that was upgraded, we check to make sure the files aren't the
   *    same ones from the old package by checking dev/inode
   *  - The listed thing is not a directory or a symlink to one (ie,
   *    it's a plain file, device, pipe, &c, or a symlink to one, or a
   *    dangling symlink). We delete it.
   *
   * The removed packages' list becomes empty (of course, the new
   * version of the package we're installing will have a new list,
   * which replaces the old version's list).
   *
   * If at any stage we remove a file from a package's list, and the
   * package isn't one we're already processing, and the package's
   * list becomes empty as a result, we ‘vanish’ the package. This
   * means that we run its postrm with the ‘disappear’ argument, and
   * put the package in the ‘not-installed’ state. If it had any
   * conffiles, their hashes and ownership will have been transferred
   * already, so we just ignore those and forget about them from the
   * point of view of the disappearing package.
   *
   * NOTE THAT THE OLD POSTRM IS RUN AFTER THE NEW PREINST, since the
   * files get replaced ‘as we go’.
   */

  m_pipe(p1);
  push_cleanup(cu_closepipe, ehflag_bombout, NULL, 0, 1, (void *)&p1[0]);
  pid = subproc_fork();
  if (pid == 0) {
    m_dup2(p1[1],1); close(p1[0]); close(p1[1]);
    execlp(BACKEND, BACKEND, "--fsys-tarfile", filename, NULL);
    ohshite(_("unable to execute %s (%s)"),
            _("package filesystem archive extraction"), BACKEND);
  }
  close(p1[1]);
  p1[1] = -1;

  newfileslist = NULL;
  tc.newfilesp = &newfileslist;
  push_cleanup(cu_fileslist, ~0, NULL, 0, 0);
  tc.pkg= pkg;
  tc.backendpipe= p1[0];

  r = tar_extractor(&tc, &tf);
  if (r) {
    if (errno) {
      ohshite(_("error reading dpkg-deb tar output"));
    } else {
      ohshit(_("corrupted filesystem tarfile - corrupted package archive"));
    }
  }
  fd_null_copy(p1[0], -1, _("dpkg-deb: zap possible trailing zeros"));
  close(p1[0]);
  p1[0] = -1;
  subproc_wait_check(pid, BACKEND " --fsys-tarfile", PROCPIPE);

  tar_deferred_extract(newfileslist, pkg);

  if (oldversionstatus == stat_halfinstalled || oldversionstatus == stat_unpacked) {
    /* Packages that were in ‘installed’ and ‘postinstfailed’ have been
     * reduced to ‘unpacked’ by now, by the running of the prerm script. */
    pkg->status= stat_halfinstalled;
    modstatdb_note(pkg);
    push_cleanup(cu_postrmupgrade, ~ehflag_normaltidy, NULL, 0, 1, (void *)pkg);
    maintainer_script_alternative(pkg, POSTRMFILE, "post-removal", cidir, cidirrest,
                                  "upgrade", "failed-upgrade");
  }

  /* If anything goes wrong while tidying up it's a bit late to do
   * anything about it. However, we don't install the new status
   * info yet, so that a future dpkg installation will put everything
   * right (we hope).
   *
   * If something does go wrong later the ‘conflictor’ package will be
   * left in the ‘removal_failed’ state. Removing or installing it
   * will be impossible if it was required because of the conflict with
   * the package we're installing now and (presumably) the dependency
   * by other packages. This means that the files it contains in
   * common with this package will hang around until we successfully
   * get this package installed, after which point we can trust the
   * conflicting package's file list, which will have been updated to
   * remove any files in this package. */
  push_checkpoint(~ehflag_bombout, ehflag_normaltidy);

  /* Now we delete all the files that were in the old version of
   * the package only, except (old or new) conffiles, which we leave
   * alone. */
  reversefilelist_init(&rlistit,pkg->clientdata->files);
  while ((namenode= reversefilelist_next(&rlistit))) {
    struct filenamenode *usenode;

    if ((namenode->flags & fnnf_new_conff) ||
        (namenode->flags & fnnf_new_inarchive))
      continue;

    usenode = namenodetouse(namenode, pkg);
    trig_file_activate(usenode, pkg);

    varbuf_trunc(&fnamevb, fnameidlu);
    varbuf_add_str(&fnamevb, usenode->name);
    varbuf_end_str(&fnamevb);

    if (!stat(namenode->name,&stab) && S_ISDIR(stab.st_mode)) {
      debug(dbg_eachfiledetail, "process_archive: %s is a directory",
	    namenode->name);
      if (isdirectoryinuse(namenode,pkg)) continue;
    }

    if (lstat(fnamevb.buf, &oldfs)) {
      if (!(errno == ENOENT || errno == ELOOP || errno == ENOTDIR))
	warning(_("could not stat old file '%.250s' so not deleting it: %s"),
	        fnamevb.buf, strerror(errno));
      continue;
    }
    if (S_ISDIR(oldfs.st_mode)) {
      if (rmdir(fnamevb.buf)) {
	warning(_("unable to delete old directory '%.250s': %s"),
	        namenode->name, strerror(errno));
      } else if ((namenode->flags & fnnf_old_conff)) {
	warning(_("old conffile '%.250s' was an empty directory "
	          "(and has now been deleted)"), namenode->name);
      }
    } else {
      struct fileinlist *sameas = NULL;
      static struct stat empty_stat;
      struct varbuf cfilename = VARBUF_INIT;

      /*
       * Ok, it's an old file, but is it really not in the new package?
       * It might be known by a different name because of symlinks.
       *
       * We need to check to make sure, so we stat the file, then compare
       * it to the new list. If we find a dev/inode match, we assume they
       * are the same file, and leave it alone. NOTE: we don't check in
       * other packages for sanity reasons (we don't want to stat _all_
       * the files on the system).
       *
       * We run down the list of _new_ files in this package. This keeps
       * the process a little leaner. We are only worried about new ones
       * since ones that stayed the same don't really apply here.
       */

      /* If we can't stat the old or new file, or it's a directory,
       * we leave it up to the normal code. */
      debug(dbg_eachfile, "process_archive: checking %s for same files on "
	    "upgrade/downgrade", fnamevb.buf);

      for (cfile= newfileslist; cfile; cfile= cfile->next) {
	/* If the file has been filtered then treat it as if it didn't exist
	 * on the file system. */
	if (cfile->namenode->flags & fnnf_filtered)
	  continue;
	if (!cfile->namenode->filestat) {
	  struct stat tmp_stat;

	  varbuf_reset(&cfilename);
	  varbuf_add_str(&cfilename, instdir);
	  varbuf_add_char(&cfilename, '/');
	  varbuf_add_str(&cfilename, cfile->namenode->name);
	  varbuf_end_str(&cfilename);

	  if (lstat(cfilename.buf, &tmp_stat) == 0) {
	    cfile->namenode->filestat = nfmalloc(sizeof(struct stat));
	    memcpy(cfile->namenode->filestat, &tmp_stat, sizeof(struct stat));
	  } else {
	    if (!(errno == ENOENT || errno == ELOOP || errno == ENOTDIR))
	      ohshite(_("unable to stat other new file `%.250s'"),
		      cfile->namenode->name);
	    cfile->namenode->filestat = &empty_stat;
	    continue;
	  }
	}
	if (cfile->namenode->filestat == &empty_stat)
	  continue;
	if (oldfs.st_dev == cfile->namenode->filestat->st_dev &&
	    oldfs.st_ino == cfile->namenode->filestat->st_ino) {
	  if (sameas)
	    warning(_("old file '%.250s' is the same as several new files! "
	              "(both '%.250s' and '%.250s')"), fnamevb.buf,
		    sameas->namenode->name, cfile->namenode->name);
	  sameas= cfile;
	  debug(dbg_eachfile, "process_archive: not removing %s,"
		" since it matches %s", fnamevb.buf, cfile->namenode->name);
	}
      }

      varbuf_destroy(&cfilename);

      if ((namenode->flags & fnnf_old_conff)) {
	if (sameas) {
	  if (sameas->namenode->flags & fnnf_new_conff) {
	    if (!strcmp(sameas->namenode->oldhash, NEWCONFFILEFLAG)) {
	      sameas->namenode->oldhash= namenode->oldhash;
	      debug(dbg_eachfile, "process_archive: old conff %s"
		    " is same as new conff %s, copying hash",
		    namenode->name, sameas->namenode->name);
	    } else {
	      debug(dbg_eachfile, "process_archive: old conff %s"
		    " is same as new conff %s but latter already has hash",
		    namenode->name, sameas->namenode->name);
	    }
	  }
	} else {
	  debug(dbg_eachfile, "process_archive: old conff %s"
		" is disappearing", namenode->name);
	  namenode->flags |= fnnf_obs_conff;
	  newconff_append(&newconffileslastp, namenode);
	  addfiletolist(&tc, namenode);
	}
	continue;
      }

      if (sameas)
	continue;

      if (secure_unlink_statted(fnamevb.buf, &oldfs)) {
        warning(_("unable to securely remove old file '%.250s': %s"),
                namenode->name, strerror(errno));
      }

    } /* !S_ISDIR */
  }

  /* OK, now we can write the updated files-in-this package list,
   * since we've done away (hopefully) with all the old junk. */
  write_filelist_except(pkg,newfileslist,0);

  /* Trigger interests may have changed.
   * Firstly we go through the old list of interests deleting them.
   * Then we go through the new list adding them. */
  strcpy(cidirrest, TRIGGERSCIFILE);
  trig_parse_ci(pkgadminfile(pkg, TRIGGERSCIFILE),
                trig_cicb_interest_delete, NULL, pkg);
  trig_parse_ci(cidir, trig_cicb_interest_add, NULL, pkg);
  trig_file_interests_save();

  /* We also install the new maintainer scripts, and any other
   * cruft that may have come along with the package. First
   * we go through the existing scripts replacing or removing
   * them as appropriate; then we go through the new scripts
   * (any that are left) and install them. */
  debug(dbg_general, "process_archive updating info directory");
  varbuf_reset(&infofnvb);
  varbuf_add_str(&infofnvb, pkgadmindir());
  infodirlen= infofnvb.used;
  varbuf_end_str(&infofnvb);
  dsd= opendir(infofnvb.buf);
  if (!dsd) ohshite(_("cannot read info directory"));
  push_cleanup(cu_closedir, ~0, NULL, 0, 1, (void *)dsd);
  while ((de = readdir(dsd)) != NULL) {
    debug(dbg_veryverbose, "process_archive info file `%s'", de->d_name);
    /* Ignore dotfiles, including ‘.’ and ‘..’. */
    if (de->d_name[0] == '.')
      continue;
    /* Ignore anything odd. */
    p = strrchr(de->d_name, '.');
    if (!p)
      continue;
    if (strlen(pkg->name) != (size_t)(p-de->d_name) ||
        strncmp(de->d_name,pkg->name,p-de->d_name)) continue;

    debug(dbg_stupidlyverbose, "process_archive info this pkg");
    /* Right, do we have one? */

    /* Skip past the full stop. */
    p++;
    /* We do the list separately. */
    if (!strcmp(p, LISTFILE))
      continue;
    if (strlen(p) > MAXCONTROLFILENAME)
      ohshit(_("old version of package has overly-long info file name starting `%.250s'"),
             de->d_name);
    varbuf_trunc(&infofnvb, infodirlen);
    varbuf_add_str(&infofnvb, de->d_name);
    varbuf_end_str(&infofnvb);

    /* We keep files to rename in a list as doing the rename immediately
     * might influence the current readdir(), the just renamed file might
     * be returned a second time as it's actually a new file from the
     * point of view of the filesystem. */
    match_head = match_node_new(infofnvb.buf, p, match_head);
  }
  pop_cleanup(ehflag_normaltidy); /* closedir */

  while ((match_node = match_head)) {
    strcpy(cidirrest, match_node->filetype);

    if (!rename(cidir, match_node->filename)) {
      debug(dbg_scripts, "process_archive info installed %s as %s",
            cidir, match_node->filename);
    } else if (errno == ENOENT) {
      /* Right, no new version. */
      if (unlink(match_node->filename))
        ohshite(_("unable to remove obsolete info file `%.250s'"),
                match_node->filename);
      debug(dbg_scripts, "process_archive info unlinked %s",
            match_node->filename);
    } else {
      ohshite(_("unable to install (supposed) new info file `%.250s'"),
              cidir);
    }
    match_head = match_node->next;
    match_node_free(match_node);
  }

  /* The directory itself. */
  *cidirrest = '\0';
  dsd= opendir(cidir);
  if (!dsd) ohshite(_("unable to open temp control directory"));
  push_cleanup(cu_closedir, ~0, NULL, 0, 1, (void *)dsd);
  while ((de= readdir(dsd))) {
    if (strchr(de->d_name,'.')) {
      debug(dbg_scripts,"process_archive tmp.ci script/file `%s' contains dot",
            de->d_name);
      continue;
    }
    if (strlen(de->d_name) > MAXCONTROLFILENAME)
      ohshit(_("package contains overly-long control info file name (starting `%.50s')"),
             de->d_name);
    strcpy(cidirrest,de->d_name);
    /* First we check it's not a directory. */
    if (!rmdir(cidir))
      ohshit(_("package control info contained directory `%.250s'"),cidir);
    else if (errno != ENOTDIR)
      ohshite(_("package control info rmdir of `%.250s' didn't say not a dir"),de->d_name);
    /* Ignore the control file. */
    if (!strcmp(de->d_name,CONTROLFILE)) {
      debug(dbg_scripts,"process_archive tmp.ci script/file `%s' is control",cidir);
      continue;
    }
    if (!strcmp(de->d_name,LISTFILE)) {
      warning(_("package %s contained list as info file"), pkg->name);
      continue;
    }
    /* Right, install it */
    newinfofilename= pkgadminfile(pkg,de->d_name);
    if (rename(cidir,newinfofilename))
      ohshite(_("unable to install new info file `%.250s' as `%.250s'"),
              cidir,newinfofilename);
    debug(dbg_scripts,"process_archive tmp.ci script/file `%s' installed as `%s'",
          cidir, newinfofilename);
  }
  pop_cleanup(ehflag_normaltidy); /* closedir */

  dir_sync_path(pkgadmindir());

  /*
   * Update the status database.
   *
   * This involves copying each field across from the ‘available’
   * to the ‘installed’ half of the pkg structure.
   * For some of the fields we have to do a complicated construction
   * operation; for others we can just copy the value.
   * We tackle the fields in the order they appear, so that
   * we don't miss any out :-).
   * At least we don't have to copy any strings that are referred
   * to, because these are never modified and never freed.
   */

  /* The dependencies are the most difficult. We have to build
   * a whole new forward dependency tree. At least the reverse
   * links (linking our deppossi's into the reverse chains)
   * can be done by copy_dependency_links. */
  newdeplist = NULL;
  newdeplistlastp = &newdeplist;
  for (dep= pkg->available.depends; dep; dep= dep->next) {
    newdep= nfmalloc(sizeof(struct dependency));
    newdep->up= pkg;
    newdep->next = NULL;
    newdep->list = NULL;
    newpossilastp = &newdep->list;
    for (possi= dep->list; possi; possi= possi->next) {
      newpossi= nfmalloc(sizeof(struct deppossi));
      newpossi->up= newdep;
      newpossi->ed= possi->ed;
      newpossi->next = NULL;
      newpossi->rev_next = newpossi->rev_prev = NULL;
      newpossi->verrel= possi->verrel;
      if (possi->verrel != dvr_none)
        newpossi->version= possi->version;
      else
        blankversion(&newpossi->version);
      newpossi->cyclebreak = false;
      *newpossilastp= newpossi;
      newpossilastp= &newpossi->next;
    }
    newdep->type= dep->type;
    *newdeplistlastp= newdep;
    newdeplistlastp= &newdep->next;
  }
  /* Right, now we've replicated the forward tree, we
   * get copy_dependency_links to remove all the old dependency
   * structures from the reverse links and add the new dependency
   * structures in instead. It also copies the new dependency
   * structure pointer for this package into the right field. */
  copy_dependency_links(pkg,&pkg->installed.depends,newdeplist,0);

  /* The ‘depended’ pointer in the structure doesn't represent anything
   * that is actually specified by this package - it's there so we
   * can find out what other packages refer to this one. So,
   * we don't copy it. We go straight on to copy the text fields. */
  pkg->installed.essential= pkg->available.essential;
  pkg->installed.description= pkg->available.description;
  pkg->installed.maintainer= pkg->available.maintainer;
  pkg->installed.source= pkg->available.source;
  pkg->installed.arch = pkg->available.arch;
  pkg->installed.installedsize= pkg->available.installedsize;
  pkg->installed.version= pkg->available.version;
  pkg->installed.origin = pkg->available.origin;
  pkg->installed.bugs = pkg->available.bugs;

  /* We have to generate our own conffiles structure. */
  pkg->installed.conffiles = NULL;
  iconffileslastp = &pkg->installed.conffiles;
  for (cfile= newconffiles; cfile; cfile= cfile->next) {
    newiconff= nfmalloc(sizeof(struct conffile));
    newiconff->next = NULL;
    newiconff->name= nfstrsave(cfile->namenode->name);
    newiconff->hash= nfstrsave(cfile->namenode->oldhash);
    newiconff->obsolete= !!(cfile->namenode->flags & fnnf_obs_conff);
    *iconffileslastp= newiconff;
    iconffileslastp= &newiconff->next;
  }

  /* We can just copy the arbitrary fields list, because it is
   * never even rearranged. Phew! */
  pkg->installed.arbs= pkg->available.arbs;

  /* Check for disappearing packages:
   * We go through all the packages on the system looking for ones
   * whose files are entirely part of the one we've just unpacked
   * (and which actually *have* some files!).
   *
   * Any that we find are removed - we run the postrm with ‘disappear’
   * as an argument, and remove their info/... files and status info.
   * Conffiles are ignored (the new package had better do something
   * with them!). */
  it = pkg_db_iter_new();
  while ((otherpkg = pkg_db_iter_next(it)) != NULL) {
    ensure_package_clientdata(otherpkg);
    if (otherpkg == pkg ||
        otherpkg->status == stat_notinstalled ||
        otherpkg->status == stat_configfiles ||
	otherpkg->clientdata->istobe == itb_remove ||
        !otherpkg->clientdata->files) continue;
    debug(dbg_veryverbose, "process_archive checking disappearance %s",otherpkg->name);
    assert(otherpkg->clientdata->istobe == itb_normal ||
           otherpkg->clientdata->istobe == itb_deconfigure);
    for (cfile= otherpkg->clientdata->files;
         cfile && !strcmp(cfile->namenode->name,"/.");
         cfile= cfile->next);
    if (!cfile) {
      debug(dbg_stupidlyverbose, "process_archive no non-root, no disappear");
      continue;
    }
    for (cfile= otherpkg->clientdata->files;
         cfile && !filesavespackage(cfile,otherpkg,pkg);
         cfile= cfile->next);
    if (cfile) continue;

    /* So dependency things will give right answers ... */
    otherpkg->clientdata->istobe= itb_remove;
    debug(dbg_veryverbose, "process_archive disappear checking dependencies");
    for (pdep= otherpkg->installed.depended;
         pdep;
         pdep = pdep->rev_next) {
      if (pdep->up->type != dep_depends && pdep->up->type != dep_predepends &&
          pdep->up->type != dep_recommends) continue;
      if (depisok(pdep->up, &depprobwhy, NULL, false))
        continue;
      varbuf_end_str(&depprobwhy);
      debug(dbg_veryverbose,"process_archive cannot disappear: %s",depprobwhy.buf);
      break;
    }
    if (!pdep) {
      /* If we haven't found a reason not to yet, let's look some more. */
      for (providecheck= otherpkg->installed.depends;
           providecheck;
           providecheck= providecheck->next) {
        if (providecheck->type != dep_provides) continue;
        for (pdep= providecheck->list->ed->installed.depended;
             pdep;
             pdep = pdep->rev_next) {
          if (pdep->up->type != dep_depends && pdep->up->type != dep_predepends &&
              pdep->up->type != dep_recommends)
            continue;
          if (depisok(pdep->up, &depprobwhy, NULL, false))
            continue;
          varbuf_end_str(&depprobwhy);
          debug(dbg_veryverbose,"process_archive cannot disappear (provides %s): %s",
                providecheck->list->ed->name, depprobwhy.buf);
          goto break_from_both_loops_at_once;
        }
      }
    break_from_both_loops_at_once:;
    }
    otherpkg->clientdata->istobe= itb_normal;
    if (pdep) continue;

    printf(_("(Noting disappearance of %s, which has been completely replaced.)\n"),
           otherpkg->name);
    log_action("disappear", otherpkg);
    debug(dbg_general, "process_archive disappearing %s",otherpkg->name);
    /* No, we're disappearing it. This is the wrong time to go and
     * run maintainer scripts and things, as we can't back out. But
     * what can we do ?  It has to be run this late. */
    trig_activate_packageprocessing(otherpkg);
    maintainer_script_installed(otherpkg, POSTRMFILE,
                                "post-removal script (for disappearance)",
                                "disappear", pkg->name,
                                versiondescribe(&pkg->available.version,
                                                vdew_nonambig),
                                NULL);

    /* OK, now we delete all the stuff in the ‘info’ directory .. */
    varbuf_reset(&fnvb);
    varbuf_add_str(&fnvb, pkgadmindir());
    infodirbaseused= fnvb.used;
    varbuf_end_str(&fnvb);
    dsd= opendir(fnvb.buf); if (!dsd) ohshite(_("cannot read info directory"));
    push_cleanup(cu_closedir, ~0, NULL, 0, 1, (void *)dsd);

    debug(dbg_general, "process_archive disappear cleaning info directory");

    while ((de = readdir(dsd)) != NULL) {
      debug(dbg_veryverbose, "process_archive info file `%s'", de->d_name);
      if (de->d_name[0] == '.') continue;
      p= strrchr(de->d_name,'.'); if (!p) continue;
      if (strlen(otherpkg->name) != (size_t)(p-de->d_name) ||
          strncmp(de->d_name,otherpkg->name,p-de->d_name)) continue;
      debug(dbg_stupidlyverbose, "process_archive info this pkg");
      varbuf_trunc(&fnvb, infodirbaseused);
      varbuf_add_str(&fnvb, de->d_name);
      varbuf_end_str(&fnvb);
      if (unlink(fnvb.buf))
        ohshite(_("unable to delete disappearing control info file `%.250s'"),fnvb.buf);
      debug(dbg_scripts, "process_archive info unlinked %s",fnvb.buf);
    }
    pop_cleanup(ehflag_normaltidy); /* closedir */

    dir_sync_path(pkgadmindir());

    otherpkg->status= stat_notinstalled;
    otherpkg->want = want_unknown;
    otherpkg->eflag = eflag_ok;

    blankversion(&otherpkg->configversion);
    pkgbin_blank(&otherpkg->installed);

    otherpkg->clientdata->fileslistvalid = false;

    modstatdb_note(otherpkg);

  } /* while (otherpkg= ... */
  pkg_db_iter_free(it);

  /* Delete files from any other packages' lists.
   * We have to do this before we claim this package is in any
   * sane kind of state, as otherwise we might delete by mistake
   * a file that we overwrote, when we remove the package which
   * had the version we overwrote. To prevent this we make
   * sure that we don't claim this package is OK until we
   * have claimed ‘ownership’ of all its files. */
  for (cfile= newfileslist; cfile; cfile= cfile->next) {
    struct filepackages_iterator *iter;

    if (!(cfile->namenode->flags & fnnf_elide_other_lists)) continue;
    if (cfile->namenode->divert && cfile->namenode->divert->useinstead) {
      divpkg= cfile->namenode->divert->pkg;
      if (divpkg == pkg) {
        debug(dbg_eachfile,
              "process_archive not overwriting any `%s' (overriding, `%s')",
              cfile->namenode->name, cfile->namenode->divert->useinstead->name);
        continue;
      } else {
        debug(dbg_eachfile,
              "process_archive looking for overwriting `%s' (overridden by %s)",
              cfile->namenode->name, divpkg ? divpkg->name : "<local>");
      }
    } else {
      divpkg = NULL;
      debug(dbg_eachfile, "process_archive looking for overwriting `%s'",
            cfile->namenode->name);
    }
    iter = filepackages_iter_new(cfile->namenode);
    while ((otherpkg = filepackages_iter_next(iter))) {
      debug(dbg_eachfiledetail, "process_archive ... found in %s", otherpkg->name);
      /* If !fileslistvalid then it's one of the disappeared packages above
       * and we don't bother with it here, clearly. */
      if (otherpkg == pkg || !otherpkg->clientdata->fileslistvalid)
        continue;
      if (otherpkg == divpkg) {
        debug(dbg_eachfiledetail, "process_archive ... diverted, skipping");
        continue;
      }

      /* Found one. We delete remove the list entry for this file,
       * (and any others in the same package) and then mark the package
       * as requiring a reread. */
      write_filelist_except(otherpkg, otherpkg->clientdata->files, 1);
      ensure_package_clientdata(otherpkg);
      debug(dbg_veryverbose, "process_archive overwrote from %s", otherpkg->name);
    }
    filepackages_iter_free(iter);
  }

  /* Right, the package we've unpacked is now in a reasonable state.
   * The only thing that we have left to do with it is remove
   * backup files, and we can leave the user to fix that if and when
   * it happens (we leave the reinstall required flag, of course). */
  pkg->status= stat_unpacked;
  modstatdb_note(pkg);

  /* Now we delete all the backup files that we made when
   * extracting the archive - except for files listed as conffiles
   * in the new package.
   * This time we count it as an error if something goes wrong.
   *
   * Note that we don't ever delete things that were in the old
   * package as a conffile and don't appear at all in the new.
   * They stay recorded as obsolete conffiles and will eventually
   * (if not taken over by another package) be forgotten. */
  for (cfile= newfileslist; cfile; cfile= cfile->next) {
    if (cfile->namenode->flags & fnnf_new_conff) continue;
    varbuf_trunc(&fnametmpvb, fnameidlu);
    varbuf_add_str(&fnametmpvb, namenodetouse(cfile->namenode, pkg)->name);
    varbuf_add_str(&fnametmpvb, DPKGTEMPEXT);
    varbuf_end_str(&fnametmpvb);
    ensure_pathname_nonexisting(fnametmpvb.buf);
  }

  /* OK, we're now fully done with the main package.
   * This is quite a nice state, so we don't unwind past here. */
  pkg->eflag = eflag_ok;
  modstatdb_note(pkg);
  push_checkpoint(~ehflag_bombout, ehflag_normaltidy);

  /* Only the removal of the conflictor left to do.
   * The files list for the conflictor is still a little inconsistent in-core,
   * as we have not yet updated the filename->packages mappings; however,
   * the package->filenames mapping is. */
  for (i = 0 ; i < cflict_index ; i++) {
    /* We need to have the most up-to-date info about which files are
     * what ... */
    ensure_allinstfiles_available();
    removal_bulk(conflictor[i]);
  }

  if (cipaction->arg_int == act_install)
    add_to_queue(pkg);
}
