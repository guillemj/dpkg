/*
 * dpkg - main program for package management
 * dbmodify.c - routines for managing dpkg database updates
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2001 Wichert Akkerman <wichert@debian.org>
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

#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>

#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <ctype.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/file.h>
#include <dpkg/dir.h>
#include <dpkg/triglib.h>

static enum modstatdb_rw cstatus=-1, cflags=0;
static char *statusfile, *availablefile;
static char *importanttmpfile=NULL;
static FILE *importanttmp;
static int nextupdate;
static char *updatesdir;
static int updateslength;
static char *updatefnbuf, *updatefnrest;
static char *infodir;
static struct varbuf uvb;

static int ulist_select(const struct dirent *de) {
  const char *p;
  int l;
  for (p= de->d_name, l=0; *p; p++, l++)
    if (!cisdigit(*p)) return 0;
  if (l > IMPORTANTMAXLEN)
    ohshit(_("updates directory contains file `%.250s' whose name is too long "
           "(length=%d, max=%d)"), de->d_name, l, IMPORTANTMAXLEN);
  if (updateslength == -1) updateslength= l;
  else if (l != updateslength)
    ohshit(_("updates directory contains files with different length names "
           "(both %d and %d)"), l, updateslength);
  return 1;
}

static void cleanupdates(void) {
  struct dirent **cdlist;
  int cdn, i;

  parsedb(statusfile, pdb_lax_parser | pdb_weakclassification, NULL);

  *updatefnrest = '\0';
  updateslength= -1;
  cdn= scandir(updatefnbuf, &cdlist, &ulist_select, alphasort);
  if (cdn == -1) ohshite(_("cannot scan updates directory `%.255s'"),updatefnbuf);

  if (cdn) {
    for (i=0; i<cdn; i++) {
      strcpy(updatefnrest, cdlist[i]->d_name);
      parsedb(updatefnbuf, pdb_lax_parser | pdb_weakclassification,
              NULL);
      if (cstatus < msdbrw_write) free(cdlist[i]);
    }

    if (cstatus >= msdbrw_write) {
      writedb(statusfile,0,1);

      for (i=0; i<cdn; i++) {
        strcpy(updatefnrest, cdlist[i]->d_name);
        if (unlink(updatefnbuf))
          ohshite(_("failed to remove incorporated update file %.255s"),updatefnbuf);
        free(cdlist[i]);
      }

      dir_sync_path(updatesdir);
    }
  }
  free(cdlist);

  nextupdate= 0;
}

static void createimptmp(void) {
  int i;

  onerr_abort++;

  importanttmp= fopen(importanttmpfile,"w");
  if (!importanttmp)
    ohshite(_("unable to create `%.255s'"), importanttmpfile);
  setcloexec(fileno(importanttmp),importanttmpfile);
  for (i=0; i<512; i++) fputs("#padding\n",importanttmp);
  if (ferror(importanttmp))
    ohshite(_("unable to fill %.250s with padding"),importanttmpfile);
  if (fflush(importanttmp))
    ohshite(_("unable to flush %.250s after padding"), importanttmpfile);
  if (fseek(importanttmp,0,SEEK_SET))
    ohshite(_("unable to seek to start of %.250s after padding"),
	    importanttmpfile);

  onerr_abort--;
}

static const struct fni {
  const char *suffix;
  char **store;
} fnis[] = {
  {   STATUSFILE,                 &statusfile         },
  {   AVAILFILE,                  &availablefile      },
  {   UPDATESDIR,                 &updatesdir         },
  {   UPDATESDIR IMPORTANTTMP,    &importanttmpfile   },
  {   INFODIR,                    &infodir            },
  {   NULL, NULL                                      }
};

static int dblockfd = -1;

bool
modstatdb_is_locked(const char *admindir)
{
  char *lockfile;
  int lockfd;
  bool locked;

  m_asprintf(&lockfile, "%s/%s", admindir, LOCKFILE);

  if (dblockfd == -1) {
    lockfd = open(lockfile, O_RDONLY);
    if (lockfd == -1)
      ohshite(_("unable to open lock file %s for testing"), lockfile);
  } else {
    lockfd = dblockfd;
  }

  locked = file_is_locked(lockfd, lockfile);

  /* We only close the file if there was no lock open, otherwise we would
   * release the existing lock on close. */
  if (dblockfd == -1)
    close(lockfd);

  free(lockfile);

  return locked;
}

void
modstatdb_lock(const char *admindir)
{
  char *dblockfile = NULL;

  m_asprintf(&dblockfile, "%s/%s", admindir, LOCKFILE);

  if (dblockfd == -1) {
    dblockfd = open(dblockfile, O_RDWR | O_CREAT | O_TRUNC, 0660);
    if (dblockfd == -1) {
      if (errno == EPERM)
        ohshit(_("you do not have permission to lock the dpkg status database"));
      ohshite(_("unable to open/create status database lockfile"));
    }
  }

  file_lock(&dblockfd, FILE_LOCK_NOWAIT, dblockfile, _("dpkg status database"));

  free(dblockfile);
}

void
modstatdb_unlock(void)
{
  file_unlock();
}

enum modstatdb_rw
modstatdb_init(const char *admindir, enum modstatdb_rw readwritereq)
{
  const struct fni *fnip;

  for (fnip=fnis; fnip->suffix; fnip++) {
    free(*fnip->store);
    m_asprintf(fnip->store, "%s/%s", admindir, fnip->suffix);
  }

  cflags= readwritereq & msdbrw_flagsmask;
  readwritereq &= ~msdbrw_flagsmask;

  switch (readwritereq) {
  case msdbrw_needsuperuser:
  case msdbrw_needsuperuserlockonly:
    if (getuid() || geteuid())
      ohshit(_("requested operation requires superuser privilege"));
    /* Fall through. */
  case msdbrw_write: case msdbrw_writeifposs:
    if (access(admindir, W_OK)) {
      if (errno != EACCES)
        ohshite(_("unable to access dpkg status area"));
      else if (readwritereq == msdbrw_write)
        ohshit(_("operation requires read/write access to dpkg status area"));
      cstatus= msdbrw_readonly;
    } else {
      modstatdb_lock(admindir);
      cstatus= (readwritereq == msdbrw_needsuperuserlockonly ?
                msdbrw_needsuperuserlockonly :
                msdbrw_write);
    }
    break;
  case msdbrw_readonly:
    cstatus= msdbrw_readonly; break;
  default:
    internerr("unknown modstatdb_rw '%d'", readwritereq);
  }

  updatefnbuf = m_malloc(strlen(updatesdir) + IMPORTANTMAXLEN + 5);
  strcpy(updatefnbuf, updatesdir);
  updatefnrest= updatefnbuf+strlen(updatefnbuf);

  if (cstatus != msdbrw_needsuperuserlockonly) {
    cleanupdates();
    if (cflags & msdbrw_available)
    parsedb(availablefile,
            pdb_recordavailable | pdb_rejectstatus | pdb_lax_parser,
            NULL);
  }

  if (cstatus >= msdbrw_write) {
    createimptmp();
    varbuf_init(&uvb, 10240);
  }

  trig_fixup_awaiters(cstatus);
  trig_incorporate(cstatus, admindir);

  return cstatus;
}

void modstatdb_checkpoint(void) {
  int i;

  assert(cstatus >= msdbrw_write);
  writedb(statusfile,0,1);

  for (i=0; i<nextupdate; i++) {
    sprintf(updatefnrest, IMPORTANTFMT, i);
    /* Have we made a real mess? */
    assert(strlen(updatefnrest) <= IMPORTANTMAXLEN);
    if (unlink(updatefnbuf))
      ohshite(_("failed to remove my own update file %.255s"),updatefnbuf);
  }

  dir_sync_path(updatesdir);

  nextupdate= 0;
}

void modstatdb_shutdown(void) {
  const struct fni *fnip;
  switch (cstatus) {
  case msdbrw_write:
    modstatdb_checkpoint();
    if (cflags & msdbrw_available && !(cflags & msdbrw_available_readonly))
      writedb(availablefile, 1, 0);
    /* Tidy up a bit, but don't worry too much about failure. */
    fclose(importanttmp);
    unlink(importanttmpfile);
    varbuf_destroy(&uvb);
    /* Fall through. */
  case msdbrw_needsuperuserlockonly:
    modstatdb_unlock();
  default:
    break;
  }

  for (fnip=fnis; fnip->suffix; fnip++) {
    free(*fnip->store);
    *fnip->store= NULL;
  }
  free(updatefnbuf);
}

static void
modstatdb_note_core(struct pkginfo *pkg)
{
  assert(cstatus >= msdbrw_write);

  varbuf_reset(&uvb);
  varbufrecord(&uvb, pkg, &pkg->installed);

  if (fwrite(uvb.buf, 1, uvb.used, importanttmp) != uvb.used)
    ohshite(_("unable to write updated status of `%.250s'"), pkg->name);
  if (fflush(importanttmp))
    ohshite(_("unable to flush updated status of `%.250s'"), pkg->name);
  if (ftruncate(fileno(importanttmp), uvb.used))
    ohshite(_("unable to truncate for updated status of `%.250s'"), pkg->name);
  if (fsync(fileno(importanttmp)))
    ohshite(_("unable to fsync updated status of `%.250s'"), pkg->name);
  if (fclose(importanttmp))
    ohshite(_("unable to close updated status of `%.250s'"), pkg->name);
  sprintf(updatefnrest, IMPORTANTFMT, nextupdate);
  if (rename(importanttmpfile, updatefnbuf))
    ohshite(_("unable to install updated status of `%.250s'"), pkg->name);

  dir_sync_path(updatesdir);

  /* Have we made a real mess? */
  assert(strlen(updatefnrest) <= IMPORTANTMAXLEN);

  nextupdate++;

  if (nextupdate > MAXUPDATES) {
    modstatdb_checkpoint();
    nextupdate = 0;
  }

  createimptmp();
}

/*
 * Note: If anyone wants to set some triggers-pending, they must also
 * set status appropriately, or we will undo it. That is, it is legal
 * to call this when pkg->status and pkg->trigpend_head disagree and
 * in that case pkg->status takes precedence and pkg->trigpend_head
 * will be adjusted.
 */
void modstatdb_note(struct pkginfo *pkg) {
  struct trigaw *ta;

  onerr_abort++;

  /* Clear pending triggers here so that only code that sets the status
   * to interesting (for triggers) values has to care about triggers. */
  if (pkg->status != stat_triggerspending &&
      pkg->status != stat_triggersawaited)
    pkg->trigpend_head = NULL;

  if (pkg->status <= stat_configfiles) {
    for (ta = pkg->trigaw.head; ta; ta = ta->sameaw.next)
      ta->aw = NULL;
    pkg->trigaw.head = pkg->trigaw.tail = NULL;
  }

  log_message("status %s %s %s", statusinfos[pkg->status].name, pkg->name,
	      versiondescribe(&pkg->installed.version, vdew_nonambig));
  statusfd_send("status: %s: %s", pkg->name, statusinfos[pkg->status].name);

  if (cstatus >= msdbrw_write)
    modstatdb_note_core(pkg);

  if (!pkg->trigpend_head && pkg->othertrigaw_head) {
    /* Automatically remove us from other packages' Triggers-Awaited.
     * We do this last because we want to maximize our chances of
     * successfully recording the status of the package we were
     * pointed at by our caller, although there is some risk of
     * leaving us in a slightly odd situation which is cleared up
     * by the trigger handling logic in deppossi_ok_found. */
    trig_clear_awaiters(pkg);
  }

  onerr_abort--;
}

void
modstatdb_note_ifwrite(struct pkginfo *pkg)
{
  if (cstatus >= msdbrw_write)
    modstatdb_note(pkg);
}

const char *
pkgadmindir_init(const char *default_dir)
{
  const char *env;

  env = getenv("DPKG_ADMINDIR");
  if (env)
    return env;
  else
    return default_dir;
}

const char *
pkgadmindir(void)
{
  return infodir;
}

const char *pkgadminfile(struct pkginfo *pkg, const char *whichfile) {
  static struct varbuf vb;
  varbuf_reset(&vb);
  varbuf_add_str(&vb, infodir);
  varbuf_add_str(&vb, pkg->name);
  varbuf_add_char(&vb, '.');
  varbuf_add_str(&vb, whichfile);
  varbuf_end_str(&vb);
  return vb.buf;
}
