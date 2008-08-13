/*
 * dpkg - main program for package management
 * dbmodify.c - routines for managing dpkg database updates
 *
 * Copyright (C) 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright (C) 2001 Wichert Akkerman <wichert@debian.org>
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
#include <config.h>

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <unistd.h>
#include <dirent.h>
#include <limits.h>
#include <ctype.h>
#include <time.h>
#include <assert.h>

#include <dpkg.h>
#include <dpkg-db.h>

char *statusfile=NULL, *availablefile=NULL;
char *triggersdir, *triggersfilefile, *triggersnewfilefile;

static enum modstatdb_rw cstatus=-1, cflags=0;
static char *importanttmpfile=NULL;
static FILE *importanttmp;
static int nextupdate;
static int updateslength;
static char *updatefnbuf, *updatefnrest;
static const char *admindir;
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

  parsedb(statusfile, pdb_weakclassification, NULL,NULL,NULL);

  *updatefnrest= 0;
  updateslength= -1;
  cdn= scandir(updatefnbuf, &cdlist, &ulist_select, alphasort);
  if (cdn == -1) ohshite(_("cannot scan updates directory `%.255s'"),updatefnbuf);

  if (cdn) {
    
    for (i=0; i<cdn; i++) {
      strcpy(updatefnrest, cdlist[i]->d_name);
      parsedb(updatefnbuf, pdb_weakclassification, NULL,NULL,NULL);
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
  {   UPDATESDIR IMPORTANTTMP,    &importanttmpfile   },
  {   TRIGGERSDIR,                &triggersdir        },
  {   TRIGGERSDIR "/File",        &triggersfilefile   },
  {   TRIGGERSDIR "/File.new",    &triggersnewfilefile},
  {   NULL, NULL                                      }
};

enum modstatdb_rw modstatdb_init(const char *adir, enum modstatdb_rw readwritereq) {
  const struct fni *fnip;
  
  admindir= adir;

  for (fnip=fnis; fnip->suffix; fnip++) {
    free(*fnip->store);
    *fnip->store= m_malloc(strlen(adir)+strlen(fnip->suffix)+2);
    sprintf(*fnip->store, "%s/%s", adir, fnip->suffix);
  }

  cflags= readwritereq & msdbrw_flagsmask;
  readwritereq &= ~msdbrw_flagsmask;

  switch (readwritereq) {
  case msdbrw_needsuperuser:
  case msdbrw_needsuperuserlockonly:
    if (getuid() || geteuid())
      ohshit(_("requested operation requires superuser privilege"));
    /* fall through */
  case msdbrw_write: case msdbrw_writeifposs:
    if (access(adir,W_OK)) {
      if (errno != EACCES)
        ohshite(_("unable to access dpkg status area"));
      else if (readwritereq == msdbrw_write)
        ohshit(_("operation requires read/write access to dpkg status area"));
      cstatus= msdbrw_readonly;
    } else {
      lockdatabase(adir);
      cstatus= (readwritereq == msdbrw_needsuperuserlockonly ?
                msdbrw_needsuperuserlockonly :
                msdbrw_write);
    }
    break;
  case msdbrw_readonly:
    cstatus= msdbrw_readonly; break;
  default:
    internerr("unknown readwritereq");
  }

  updatefnbuf= m_malloc(strlen(adir)+sizeof(UPDATESDIR)+IMPORTANTMAXLEN+5);
  strcpy(updatefnbuf,adir);
  strcat(updatefnbuf,"/" UPDATESDIR);
  updatefnrest= updatefnbuf+strlen(updatefnbuf);

  if (cstatus != msdbrw_needsuperuserlockonly) {
    cleanupdates();
    if(!(cflags & msdbrw_noavail))
    parsedb(availablefile,
            pdb_recordavailable|pdb_rejectstatus,
            NULL,NULL,NULL);
  }

  if (cstatus >= msdbrw_write) {
    createimptmp();
    uvb.used= 0;
    uvb.size= 10240;
    uvb.buf= m_malloc(uvb.size);
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
    assert(strlen(updatefnrest)<=IMPORTANTMAXLEN); /* or we've made a real mess */
    if (unlink(updatefnbuf))
      ohshite(_("failed to remove my own update file %.255s"),updatefnbuf);
  }
  nextupdate= 0;
}

void modstatdb_shutdown(void) {
  const struct fni *fnip;
  switch (cstatus) {
  case msdbrw_write:
    modstatdb_checkpoint();
    writedb(availablefile,1,0);
    /* tidy up a bit, but don't worry too much about failure */
    fclose(importanttmp);
    strcpy(updatefnrest, IMPORTANTTMP); unlink(updatefnbuf);
    varbuffree(&uvb);
    /* fall through */
  case msdbrw_needsuperuserlockonly:
    unlockdatabase();
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

  varbufreset(&uvb);
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

  /* Have we made a real mess? */
  assert(strlen(updatefnrest) <= IMPORTANTMAXLEN);

  nextupdate++;

  if (nextupdate > MAXUPDATES) {
    modstatdb_checkpoint();
    nextupdate = 0;
  }

  createimptmp();
}

/* Note: If anyone wants to set some triggers-pending, they must also
 * set status appropriately, or we will undo it. That is, it is legal
 * to call this when pkg->status and pkg->trigpend_head disagree and
 * in that case pkg->status takes precedence and pkg->trigpend_head
 * will be adjusted.
 */
void modstatdb_note(struct pkginfo *pkg) {
  struct trigaw *ta;

  onerr_abort++;

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
     * We do this last because we want to maximise our chances of
     * successfully recording the status of the package we were
     * pointed at by our caller, although there is some risk of
     * leaving us in a slightly odd situation which is cleared up
     * by the trigger handling logic in deppossi_ok_found.
     */
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

const char *pkgadminfile(struct pkginfo *pkg, const char *whichfile) {
  static struct varbuf vb;
  varbufreset(&vb);
  varbufaddstr(&vb,admindir);
  varbufaddstr(&vb,"/" INFODIR);
  varbufaddstr(&vb,pkg->name);
  varbufaddc(&vb,'.');
  varbufaddstr(&vb,whichfile);
  varbufaddc(&vb,0);
  return vb.buf;
}

