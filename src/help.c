/*
 * dpkg - main program for package management
 * help.c - various helper routines
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
#include <config.h>

#include <errno.h>
#include <unistd.h>
#include <dirent.h>
#include <assert.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <time.h>

#include <dpkg.h>
#include <dpkg-db.h>

#include "filesdb.h"
#include "main.h"

const char *const statusstrings[]= {
  N_("not installed"),
  N_("unpacked but not configured"),
  N_("broken due to postinst failure"),
  N_("installed"),
  N_("broken due to failed removal"),
  N_("not installed but configs remain")
};

struct filenamenode *namenodetouse(struct filenamenode *namenode, struct pkginfo *pkg) {
  struct filenamenode *r;
  
  if (!namenode->divert) return namenode;
  
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

void checkpath(void) {
/* Verify that some programs can be found in the PATH. */
  static const char *const checklist[]= { "ldconfig", 
#ifdef WITH_START_STOP_DAEMON
    "start-stop-daemon",
#endif    
    "install-info", "update-rc.d", 0
  };

  struct stat stab;
  const char *const *clp;
  const char *path, *s, *p;
  char* buf;
  int warned= 0;
  long l;

  path= getenv("PATH");
  if (!path) ohshit(_("dpkg - error: PATH is not set.\n"));
  buf=(char*)m_malloc(strlen(path)+2+strlen("start-stop-daemon"));
  
  for (clp=checklist; *clp; clp++) {
    s= path;
    while (s) {
      p= strchr(s,':');
      l= p ? p-s : (long)strlen(s);
      memcpy(buf,s,l);
      if (l) buf[l++]= '/';
      strcpy(buf+l,*clp);
      if (stat(buf,&stab) == 0 && (stab.st_mode & 0111)) break;
      s= p; if (s) s++;
    }
    if (!s) {
      fprintf(stderr,_("dpkg: `%s' not found on PATH.\n"),*clp);
      warned++;
    }
  }

  free(buf);
  if (warned)
    forcibleerr(fc_badpath,_("%d expected program(s) not found on PATH.\nNB: root's "
                "PATH should usually contain /usr/local/sbin, /usr/sbin and /sbin."),
                warned);
}

void ensure_package_clientdata(struct pkginfo *pkg) {
  if (pkg->clientdata) return;
  pkg->clientdata= nfmalloc(sizeof(struct perpackagestate));
  pkg->clientdata->istobe= itb_normal;
  pkg->clientdata->fileslistvalid= 0;
  pkg->clientdata->files= 0;
}

void cu_closepipe(int argc, void **argv) {
  int *p1= (int*)argv[0];
  close(p1[0]); close(p1[1]);
}

void cu_closefile(int argc, void **argv) {
  FILE *f= (FILE*)(argv[0]);
  fclose(f);
}

void cu_closedir(int argc, void **argv) {
  DIR *d= (DIR*)(argv[0]);
  closedir(d);
}

void cu_closefd(int argc, void **argv) {
  int ip= *(int*)argv[0];
  close(ip);
}

int ignore_depends(struct pkginfo *pkg) {
  struct packageinlist *id;
  for (id= ignoredependss; id; id= id->next)
    if (id->pkg == pkg) return 1;
  return 0;
}

int force_depends(struct deppossi *possi) {
  return fc_depends ||
         ignore_depends(possi->ed) ||
         ignore_depends(possi->up->up);
}

int force_conflicts(struct deppossi *possi) {
  return fc_conflicts;
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

static const char* preexecscript(const char *path, char *const *argv) {
  /* returns the path to the script inside the chroot
   * none of the stuff here will work if admindir isn't inside instdir
   * as expected. - fixme
   */
  size_t instdirl;

  if (*instdir) {
    if (chroot(instdir)) ohshite(_("failed to chroot to `%.250s'"),instdir);
  }
  if (f_debug & dbg_scripts) {
    fprintf(stderr,"D0%05o: fork/exec %s (",dbg_scripts,path);
    while (*++argv) fprintf(stderr," %s",*argv);
    fputs(" )\n",stderr);
  }
  instdirl= strlen(instdir);
  if (!instdirl) return path;
  assert (strlen(path)>=instdirl);
  return path+instdirl;
}  

static char *const *vbuildarglist(const char *scriptname, va_list ap) {
  static char *bufs[PKGSCRIPTMAXARGS+1];
  char *nextarg;
  int i;

  i=0;
  if(bufs[0]) free(bufs[0]);
  bufs[i++]= strdup(scriptname); /* yes, cast away const because exec wants it that way */
  for (;;) {
    assert(i < PKGSCRIPTMAXARGS);
    nextarg= va_arg(ap,char*);
    if (!nextarg) break;
    bufs[i++]= nextarg;
  }
  bufs[i]= 0;
  return bufs;
}    

static char *const *buildarglist(const char *scriptname, ...) {
  char *const *arglist;
  va_list ap;
  va_start(ap,scriptname);
  arglist= vbuildarglist(scriptname,ap);
  va_end(ap);
  return arglist;
}

#define NSCRIPTCATCHSIGNALS (int)(sizeof(script_catchsignallist)/sizeof(int)-1)
static int script_catchsignallist[]= { SIGQUIT, SIGINT, 0 };
static struct sigaction script_uncatchsignal[NSCRIPTCATCHSIGNALS];

static void cu_restorescriptsignals(int argc, void **argv) {
  int i;
  for (i=0; i<NSCRIPTCATCHSIGNALS; i++) {
    if (sigaction(script_catchsignallist[i],&script_uncatchsignal[i],0)) {
      fprintf(stderr,_("error un-catching signal %s: %s\n"),
              strsignal(script_catchsignallist[i]),strerror(errno));
      onerr_abort++;
    }
  }
}

static void script_catchsignals(void) {
  int i;
  struct sigaction catchsig;
  
  onerr_abort++;
  memset(&catchsig,0,sizeof(catchsig));
  catchsig.sa_handler= SIG_IGN;
  sigemptyset(&catchsig.sa_mask);
  catchsig.sa_flags= 0;
  for (i=0; i<NSCRIPTCATCHSIGNALS; i++)
    if (sigaction(script_catchsignallist[i],&catchsig,&script_uncatchsignal[i]))
      ohshite(_("unable to ignore signal %s before running script"),
              strsignal(script_catchsignallist[i]));
  push_cleanup(cu_restorescriptsignals,~0, 0,0, 0);
  onerr_abort--;
}

static void setexecute(const char *path, struct stat *stab) {
  if ((stab->st_mode & 0555) == 0555) return;
  if (!chmod(path,0755)) return;
  ohshite(_("unable to set execute permissions on `%.250s'"),path);
}
static int do_script(const char *pkg, const char *scriptname, const char *scriptpath, struct stat *stab, char *const arglist[], const char *desc, const char *name, int warn) {
  const char *scriptexec;
  int c1, r;
  setexecute(scriptpath,stab);

  c1= m_fork();
  if (!c1) {
    const char **narglist;
    for (r=0; arglist[r]; r++) ;
    narglist=nfmalloc((r+1)*sizeof(char*));
    for (r=1; arglist[r-1]; r++)
      narglist[r]= arglist[r];
    scriptexec= preexecscript(scriptpath,(char * const *)narglist);
    narglist[0]= scriptexec;
    execv(scriptexec,(char * const *)narglist);
    ohshite(desc,name);
  }
  script_catchsignals(); /* This does a push_cleanup() */
  r= waitsubproc(c1,name,warn);
  pop_cleanup(ehflag_normaltidy);
  return r;
}

int maintainer_script_installed(struct pkginfo *pkg, const char *scriptname,
                                const char *description, ...) {
  /* all ...'s are const char*'s */
  const char *scriptpath;
  char *const *arglist;
  struct stat stab;
  va_list ap;
  char buf[100];

  scriptpath= pkgadminfile(pkg,scriptname);
  va_start(ap,description);
  arglist= vbuildarglist(scriptname,ap);
  va_end(ap);
  sprintf(buf,"%s script",description);

  if (stat(scriptpath,&stab)) {
    if (errno == ENOENT) {
      debug(dbg_scripts,"maintainer_script_installed nonexistent %s",scriptname);
      return 0;
    }
    ohshite(_("unable to stat installed %s script `%.250s'"),description,scriptpath);
  }
  do_script(pkg->name, scriptname, scriptpath, &stab, arglist, _("unable to execute %s"), buf, 0);
  ensure_diversions();
  return 1;
}
  
int maintainer_script_new(const char *pkgname,
			  const char *scriptname, const char *description,
                          const char *cidir, char *cidirrest, ...) {
  char *const *arglist;
  struct stat stab;
  va_list ap;
  char buf[100];
  
  va_start(ap,cidirrest);
  arglist= vbuildarglist(scriptname,ap);
  va_end(ap);
  sprintf(buf,"%s script",description);

  strcpy(cidirrest,scriptname);
  if (stat(cidir,&stab)) {
    if (errno == ENOENT) {
      debug(dbg_scripts,"maintainer_script_new nonexistent %s `%s'",scriptname,cidir);
      return 0;
    }
    ohshite(_("unable to stat new %s script `%.250s'"),description,cidir);
  }
  do_script(pkgname, scriptname, cidir, &stab, arglist, _("unable to execute new %s"), buf, 0);
  ensure_diversions();
  return 1;
}

int maintainer_script_alternative(struct pkginfo *pkg,
                                  const char *scriptname, const char *description,
                                  const char *cidir, char *cidirrest,
                                  const char *ifok, const char *iffallback) {
  const char *oldscriptpath;
  char *const *arglist;
  struct stat stab;
  char buf[100];

  oldscriptpath= pkgadminfile(pkg,scriptname);
  arglist= buildarglist(scriptname,
                        ifok,versiondescribe(&pkg->available.version,
                                             vdew_nonambig),
                        (char*)0);
  sprintf(buf,_("old %s script"),description);
  if (stat(oldscriptpath,&stab)) {
    if (errno == ENOENT) {
      debug(dbg_scripts,"maintainer_script_alternative nonexistent %s `%s'",
            scriptname,oldscriptpath);
      return 0;
    }
    fprintf(stderr,
            _("dpkg: warning - unable to stat %s `%.250s': %s\n"),
            buf,oldscriptpath,strerror(errno));
  } else {
    if (!do_script(pkg->name, scriptname, oldscriptpath, &stab, arglist, _("unable to execute %s"), buf, PROCWARN))
      return 1;
    ensure_diversions();
  }
  fprintf(stderr, _("dpkg - trying script from the new package instead ...\n"));

  arglist= buildarglist(scriptname,
                        iffallback,versiondescribe(&pkg->installed.version,
                                                   vdew_nonambig),
                        (char*)0);
  strcpy(cidirrest,scriptname);
  sprintf(buf,_("new %s script"),description);

  if (stat(cidir,&stab)) {
    if (errno == ENOENT)
      ohshit(_("there is no script in the new version of the package - giving up"));
    else
      ohshite(_("unable to stat %s `%.250s'"),buf,cidir);
  }

  do_script(pkg->name, scriptname, cidir, &stab, arglist, _("unable to execute %s"), buf, 0);
  fprintf(stderr, _("dpkg: ... it looks like that went OK.\n"));

  ensure_diversions();
  return 1;
}

void clear_istobes(void) {
  struct pkgiterator *it;
  struct pkginfo *pkg;

  it= iterpkgstart();
  while ((pkg= iterpkgnext(it)) != 0) {
    ensure_package_clientdata(pkg);
    pkg->clientdata->istobe= itb_normal;
    pkg->clientdata->replacingfilesandsaid= 0;
  }
}

void debug(int which, const char *fmt, ...) {
  va_list ap;
  if (!(f_debug & which)) return;
  fprintf(stderr,"D0%05o: ",which);
  va_start(ap,fmt);
  vfprintf(stderr,fmt,ap);
  va_end(ap);
  putc('\n',stderr);
}

int isdirectoryinuse(struct filenamenode *file, struct pkginfo *pkg) {
  /* Returns 1 if the file is used by packages other than pkg, 0 otherwise. */
  struct filepackages *packageslump;
  int i;
    
  debug(dbg_veryverbose, "isdirectoryinuse `%s' (except %s)", file->name,
        pkg ? pkg->name : "<none>");
  for (packageslump= file->packages; packageslump; packageslump= packageslump->more) {
    debug(dbg_veryverbose, "isdirectoryinuse packageslump %s ...",
          packageslump->pkgs[0] ? packageslump->pkgs[0]->name : "<none>");
    for (i=0; i < PERFILEPACKAGESLUMP && packageslump->pkgs[i]; i++) {
      debug(dbg_veryverbose, "isdirectoryinuse considering [%d] %s ...", i,
            packageslump->pkgs[i]->name);
      if (packageslump->pkgs[i] == pkg) continue;
      return 1;
    }
  }
  debug(dbg_veryverbose, "isdirectoryinuse no");
  return 0;
}

void oldconffsetflags(const struct conffile *searchconff) {
  struct filenamenode *namenode;
  
  while (searchconff) {
    namenode= findnamenode(searchconff->name, 0); /* XXX */
    namenode->flags |= fnnf_old_conff;
    debug(dbg_conffdetail, "oldconffsetflags `%s' namenode %p flags %o",
          searchconff->name, namenode, namenode->flags);
    searchconff= searchconff->next;
  }
}

int chmodsafe_unlink(const char *pathname) {
  struct stat stab;

  if (lstat(pathname,&stab)) return -1;
  if (S_ISREG(stab.st_mode) ? (stab.st_mode & 07000) :
      !(S_ISLNK(stab.st_mode) || S_ISDIR(stab.st_mode) ||
   S_ISFIFO(stab.st_mode) || S_ISSOCK(stab.st_mode))) {
    /* We chmod it if it is 1. a sticky or set-id file, or 2. an unrecognised
     * object (ie, not a file, link, directory, fifo or socket
     */
    if (chmod(pathname,0600)) return -1;
  }
  if (unlink(pathname)) return -1;
  return 0;
}

void ensure_pathname_nonexisting(const char *pathname) {
  int c1;
  const char *u;

  u= skip_slash_dotslash(pathname);
  assert(*u);

  debug(dbg_eachfile,"ensure_pathname_nonexisting `%s'",pathname);
  if (!rmdir(pathname)) return; /* Deleted it OK, it was a directory. */
  if (errno == ENOENT || errno == ELOOP) return;
  if (errno == ENOTDIR) {
    /* Either it's a file, or one of the path components is.  If one
     * of the path components is this will fail again ...
     */
    if (!chmodsafe_unlink(pathname)) return; /* OK, it was */
    if (errno == ENOTDIR) return;
  }
  if (errno != ENOTEMPTY) /* Huh ? */
    ohshite(_("failed to rmdir/unlink `%.255s'"),pathname);
  c1= m_fork();
  if (!c1) {
    execlp(RM,"rm","-rf","--",pathname,(char*)0);
    ohshite(_("failed to exec rm for cleanup"));
  }
  debug(dbg_eachfile,"ensure_pathname_nonexisting running rm -rf");
  waitsubproc(c1,"rm cleanup",0);
}

void log_action(const char *action, struct pkginfo *pkg) {
  log_message("%s %s %s %s", action, pkg->name,
	      versiondescribe(&pkg->installed.version, vdew_nonambig),
	      versiondescribe(&pkg->available.version, vdew_nonambig));
}
