/*
 * dselect - Debian package maintenance user interface
 * method.cc - access method handling
 *
 * Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright (C) 2001,2002 Wichert Akkerman <wakkerma@debian.org>
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
extern "C" {
#include <config.h>
}

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
#include <assert.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>

extern "C" {
#include <dpkg.h>
#include <dpkg-db.h>
}
#include "dselect.h"
#include "method.h"

static const char *const methoddirectories[]= {
  LIBDIR "/" METHODSDIR,
  LOCALLIBDIR "/" METHODSDIR,
  0
};    

static char *methodlockfile= 0;
static int methlockfd= -1;

void sthfailed(const char * reasoning) {
  char buf[2048];

  curseson();
  clear();
  sprintf(buf,_("\n\n%s: %s\n"),DSELECT,reasoning);
  addstr(buf);
  attrset(A_BOLD);
  addstr(_("\nPress <enter> to continue."));
  attrset(A_NORMAL);
  refresh(); getch();
}

static void cu_unlockmethod(int, void**) {
  struct flock fl;

  assert(methodlockfile);
  assert(methlockfd);
  fl.l_type=F_UNLCK; fl.l_whence= SEEK_SET; fl.l_start=fl.l_len=0;
  if (fcntl(methlockfd,F_SETLK,&fl) == -1)
    sthfailed("unable to unlock access method area");
}

static enum urqresult ensureoptions(void) {
  const char *const *ccpp;
  dselect_option *newoptions;
  int nread;

  if (!options) {
    newoptions= 0;
    nread= 0;
    for (ccpp= methoddirectories; *ccpp; ccpp++)
      readmethods(*ccpp, &newoptions, &nread);
    if (!newoptions) {
      sthfailed("no access methods are available");
      return urqr_fail;
    }
    options= newoptions;
    noptions= nread;
  }
  return urqr_normal;
}

static enum urqresult lockmethod(void) {
  struct flock fl;

  if (!methodlockfile) {
    int l;
    l= strlen(admindir);
    methodlockfile= new char[l+sizeof(METHLOCKFILE)+2];
    strcpy(methodlockfile,admindir);
    strcpy(methodlockfile+l, "/" METHLOCKFILE);
  }
  if (methlockfd == -1) {
    methlockfd= open(methodlockfile, O_RDWR|O_CREAT|O_TRUNC, 0660);
    if (methlockfd == -1) {
      if ((errno == EPERM) || (errno == EACCES)) {
        sthfailed("requested operation requires superuser privilege");
        return urqr_fail;
      }
      sthfailed("unable to open/create access method lockfile");
      return urqr_fail;
    }
  }
  fl.l_type=F_WRLCK; fl.l_whence=SEEK_SET; fl.l_start=fl.l_len=0;
  if (fcntl(methlockfd,F_SETLK,&fl) == -1) {
    if (errno == EWOULDBLOCK || errno == EAGAIN) {
      sthfailed("the access method area is already locked");
      return urqr_fail;
      }
    sthfailed("unable to lock access method area");
    return urqr_fail;
  }
  push_cleanup(cu_unlockmethod,~0, 0,0, 0);
  return urqr_normal;
}

static int catchsignals[]= { SIGQUIT, SIGINT, 0 };
#define NCATCHSIGNALS ((signed)(sizeof(catchsignals)/sizeof(int))-1)
static struct sigaction uncatchsignal[NCATCHSIGNALS];

void cu_restoresignals(int, void**) {
  int i;
  for (i=0; i<NCATCHSIGNALS; i++)
    if (sigaction(catchsignals[i],&uncatchsignal[i],0))
      fprintf(stderr,_("error un-catching signal %d: %s\n"),
              catchsignals[i],strerror(errno));
}

urqresult falliblesubprocess(const char *exepath, const char *name,
                             const char *const *args) {
  pid_t c1, cr;
  int status, i, c;
  struct sigaction catchsig;
  
  cursesoff();

  memset(&catchsig,0,sizeof(catchsig));
  catchsig.sa_handler= SIG_IGN;
  sigemptyset(&catchsig.sa_mask);
  catchsig.sa_flags= 0;
  for (i=0; i<NCATCHSIGNALS; i++)
    if (sigaction(catchsignals[i],&catchsig,&uncatchsignal[i]))
      ohshite(_("unable to ignore signal %d before running %.250s"),
              catchsignals[i], name);
  push_cleanup(cu_restoresignals,~0, 0,0, 0);

  if (!(c1= m_fork())) {
    cu_restoresignals(0,0);
    execvp(exepath,(char* const*) args);
    ohshite(_("unable to run %.250s process `%.250s'"),name,exepath);
  }

  while ((cr= waitpid(c1,&status,0)) == -1)
    if (errno != EINTR) ohshite(_("unable to wait for %.250s"),name);
  if (cr != c1)
    ohshit(_("got wrong child's status - asked for %ld, got %ld"),(long)c1,(long)cr);

  pop_cleanup(ehflag_normaltidy);

  if (WIFEXITED(status) && !WEXITSTATUS(status)) {
    sleep(1);
    return urqr_normal;
  }
  fprintf(stderr,"\n%s ",name);
  if (WIFEXITED(status)) {
    i= WEXITSTATUS(status);
    fprintf(stderr,_("returned error exit status %d.\n"),i);
  } else if (WIFSIGNALED(status)) {
    i= WTERMSIG(status);
    if (i == SIGINT) {
      fprintf(stderr,_("was interrupted.\n"));
    } else {
      fprintf(stderr,_("was terminated by a signal: %s.\n"),strsignal(i));
    }
    if (WCOREDUMP(status))
      fprintf(stderr,_("(It left a coredump.)\n"));
  } else {
    fprintf(stderr,_("failed with an unknown wait return code %d.\n"),status);
  }
  fprintf(stderr,_("Press <enter> to continue.\n"));
  if (ferror(stderr))
    ohshite(_("write error on standard error"));
  do { c= fgetc(stdin); } while ((c == ERR && errno==EINTR) || ((c != '\n') && c != EOF));
  if ((c == ERR) || (c == EOF))
    ohshite(_("error reading acknowledgement of program failure message"));
  return urqr_fail;
}

static urqresult runscript(const char *exepath, const char *name) {
  urqresult ur;

  ur= ensureoptions();  if (ur != urqr_normal) return ur;
  ur=lockmethod();  if (ur != urqr_normal) return ur;
  getcurrentopt();

  if (coption) {
    strcpy(coption->meth->pathinmeth,exepath);
    const char *fallibleargs[] = {
      exepath,
      admindir,
      coption->meth->name,
      coption->name,
      0
      };
    ur= falliblesubprocess(coption->meth->path,name,fallibleargs);
  } else {
    sthfailed("no access method is selected/configured");
    ur= urqr_fail;
  }
  pop_cleanup(ehflag_normaltidy);

  return ur;
}

urqresult urq_update(void) {
  return runscript(METHODUPDATESCRIPT,_("update available list script"));
}

urqresult urq_install(void) {
  return runscript(METHODINSTALLSCRIPT,_("installation script"));
}

static urqresult rundpkgauto(const char *name, const char *dpkgmode) {
  const char *fallibleargs[] = {
    DPKG,
	"--admindir",
	admindir,
    "--pending",
    dpkgmode,
    0
  };
  cursesoff();
  printf("running dpkg --pending %s ...\n",dpkgmode);
  fflush(stdout);
  return falliblesubprocess(DPKG,name,fallibleargs);
}

urqresult urq_remove(void) {
  return rundpkgauto("dpkg --remove","--remove");
}

urqresult urq_config(void) {
  return rundpkgauto("dpkg --configure","--configure");
}

urqresult urq_setup(void) {
  quitaction qa;
  urqresult ur;

  ur= ensureoptions();  if (ur != urqr_normal) return ur;
  ur=lockmethod();  if (ur != urqr_normal) return ur;
  getcurrentopt();

  curseson();
  methodlist *l= new methodlist();
  qa= l->display();
  delete l;

  if (qa == qa_quitchecksave) {
    strcpy(coption->meth->pathinmeth,METHODSETUPSCRIPT);
    const char *fallibleargs[] = {
      METHODSETUPSCRIPT,
      admindir,
      coption->meth->name,
      coption->name,
      0
    };
    ur= falliblesubprocess(coption->meth->path,_("query/setup script"),fallibleargs);
    if (ur == urqr_normal) writecurrentopt();
  } else {
    ur= urqr_fail;
  }
  
  pop_cleanup(ehflag_normaltidy);
  return ur;
}
