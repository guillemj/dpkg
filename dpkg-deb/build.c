/*
 * dpkg-deb - construction and deconstruction of *.deb archives
 * build.c - building archives
 *
 * Copyright (C) 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright (C) 2000,2001 Wichert Akkerman <wakkerma@debian.org>
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
#include <time.h>
#include <errno.h>
#include <unistd.h>
#include <dirent.h>
#include <limits.h>
#include <ctype.h>
#include <assert.h>
#ifdef WITH_ZLIB
#include <zlib.h>
#endif

#include <dpkg.h>
#include <dpkg-db.h>
#include "dpkg-deb.h"

#ifndef S_ISLNK
# define S_ISLNK(mode) ((mode&0xF000) == S_IFLNK)
#endif

/* Simple structure to store information about a file.
 */
struct _finfo {
  struct stat	st;
  char*	fn;
  struct _finfo* next;
};

/* Do a quick check if vstring is a valid versionnumber. Valid in this case
 * means it contains at least one digit. If an error is found increment
 * *errs.
 */
static void checkversion(const char *vstring, const char *valuename, int *errs) {
  const char *p;
  if (!vstring || !*vstring) return;
  for (p=vstring; *p; p++) if (cisdigit(*p)) return;
  fprintf(stderr, _("dpkg-deb - error: %s (`%s') doesn't contain any digits\n"),
          valuename, vstring);
  (*errs)++;
}

/* Read the next filename from a filedescriptor and create a _info struct
 * for it. If there is nothing to read return NULL.
 */
static struct _finfo* getfi(const char* root, int fd) {
  static char* fn = NULL;
  static size_t fnlen = 0;
  size_t i= 0;
  struct _finfo *fi;
  size_t rl = strlen(root);

  if (fn == NULL) {
    fnlen=rl+2048;
    fn=(char*)malloc(fnlen);
  } else if (fnlen < (rl+2048)) {
    fnlen=rl+2048;
    fn=(char*)realloc(fn,fnlen);
  }
  i=sprintf(fn,"%s/",root);
  
  while (1) {
    int	res;
    if (i>=fnlen) {
      fnlen+=2048;
      fn=(char*)realloc(fn,fnlen);
    }
    if ((res=read(fd, (fn+i), sizeof(*fn)))<0) {
      if ((errno==EINTR) || (errno==EAGAIN))
	continue;
      else
	return NULL;
    }
    if (res==0)	// EOF -> parent died
      return NULL;
    if (fn[i]==0)
      break;

    i++;
    assert(i<2048);
  }

  fi=(struct _finfo*)malloc(sizeof(struct _finfo));
  lstat(fn, &(fi->st));
  fi->fn=strdup(fn+rl+1);
  fi->next=NULL;
  return fi;
}

/* Add a new _finfo struct to a single linked list of _finfo structs.
 * We perform a slight optimization to work around a `feature' in tar: tar
 * always recurses into subdirectories if you list a subdirectory. So if an
 * entry is added and the previous entry in the list is its subdirectory we
 * remove the subdirectory. 
 *
 * After a _finfo struct is added to a list it may no longer be freed, we
 * assume full responsibility for its memory.
 */
static void add_to_filist(struct _finfo* fi, struct _finfo** start, struct _finfo **end) {
  if (*start==NULL)
    *start=*end=fi;
  else 
    *end=(*end)->next=fi;
}

/* Free the memory for all entries in a list of _finfo structs
 */
static void free_filist(struct _finfo* fi) {
  while (fi) {
    struct _finfo* fl;
    free(fi->fn);
    fl=fi; fi=fi->next;
    free(fl);
  }
}

/* Overly complex function that builds a .deb file
 */
void do_build(const char *const *argv) {
  static const char *const maintainerscripts[]= {
    PREINSTFILE, POSTINSTFILE, PRERMFILE, POSTRMFILE, 0
  };
  
  char *m;
  const char *debar, *directory, *const *mscriptp, *versionstring, *arch;
  char *controlfile, *tfbuf;
  const char *envbuf;
  struct pkginfo *checkedinfo;
  struct arbitraryfield *field;
  FILE *ar, *gz, *cf;
  int p1[2],p2[2],p3[2], warns, errs, n, c, subdir, gzfd;
  pid_t c1,c2,c3;
  struct stat controlstab, datastab, mscriptstab, debarstab;
  char conffilename[MAXCONFFILENAME+1];
  time_t thetime= 0;
  struct _finfo *fi;
  struct _finfo *symlist = NULL;
  struct _finfo *symlist_end = NULL;
  
/* Decode our arguments */
  directory= *argv++; if (!directory) badusage(_("--build needs a directory argument"));
  /* template for our tempfiles */
  if ((envbuf= getenv("TMPDIR")) == NULL)
    envbuf= P_tmpdir;
  tfbuf = (char *)malloc(strlen(envbuf)+13);
  strcpy(tfbuf,envbuf);
  strcat(tfbuf,"/dpkg.XXXXXX");
  subdir= 0;
  if ((debar= *argv++) !=0) {
    if (*argv) badusage(_("--build takes at most two arguments"));
    if (debar) {
      if (stat(debar,&debarstab)) {
        if (errno != ENOENT)
          ohshite(_("unable to check for existence of archive `%.250s'"),debar);
      } else if (S_ISDIR(debarstab.st_mode)) {
        subdir= 1;
      }
    }
  } else {
    m= m_malloc(strlen(directory) + sizeof(DEBEXT));
    strcpy(m,directory); strcat(m,DEBEXT);
    debar= m;
  }
    
  /* Perform some sanity checks on the to-be-build package.
   */
  if (nocheckflag) {
    if (subdir)
      ohshit(_("target is directory - cannot skip control file check"));
    printf(_("dpkg-deb: warning, not checking contents of control area.\n"
           "dpkg-deb: building an unknown package in `%s'.\n"), debar);
  } else {
    controlfile= m_malloc(strlen(directory) + sizeof(BUILDCONTROLDIR) +
                          sizeof(CONTROLFILE) + sizeof(CONFFILESFILE) +
                          sizeof(POSTINSTFILE) + sizeof(PREINSTFILE) +
                          sizeof(POSTRMFILE) + sizeof(PRERMFILE) +
                          MAXCONFFILENAME + 5);
    /* Lets start by reading in the control-file so we can check its contents */
    strcpy(controlfile, directory);
    strcat(controlfile, "/" BUILDCONTROLDIR "/" CONTROLFILE);
    warns= 0; errs= 0;
    parsedb(controlfile, pdb_recordavailable|pdb_rejectstatus,
            &checkedinfo, stderr, &warns);
    assert(checkedinfo->available.valid);
    if (strspn(checkedinfo->name,
               "abcdefghijklmnopqrstuvwxyz0123456789+-.")
        != strlen(checkedinfo->name))
      ohshit(_("package name has characters that aren't lowercase alphanums or `-+.'"));
    if (checkedinfo->priority == pri_other) {
      fprintf(stderr, _("warning, `%s' contains user-defined Priority value `%s'\n"),
              controlfile, checkedinfo->otherpriority);
      warns++;
    }
    for (field= checkedinfo->available.arbs; field; field= field->next) {
      fprintf(stderr, _("warning, `%s' contains user-defined field `%s'\n"),
              controlfile, field->name);
      warns++;
    }
    checkversion(checkedinfo->available.version.version,"(upstream) version",&errs);
    checkversion(checkedinfo->available.version.revision,"Debian revision",&errs);
    if (errs) ohshit(_("%d errors in control file"),errs);

    if (subdir) {
      versionstring= versiondescribe(&checkedinfo->available.version,vdew_never);
      arch= checkedinfo->available.architecture; if (!arch) arch= "";
      m= m_malloc(sizeof(DEBEXT)+1+strlen(debar)+1+strlen(checkedinfo->name)+
                  strlen(versionstring)+1+strlen(arch));
      sprintf(m,"%s/%s_%s%s%s" DEBEXT,debar,checkedinfo->name,versionstring,
              arch[0] ? "_" : "", arch);
      debar= m;
    }
    printf(_("dpkg-deb: building package `%s' in `%s'.\n"), checkedinfo->name, debar);

    /* Check file permissions */
    strcpy(controlfile, directory);
    strcat(controlfile, "/" BUILDCONTROLDIR "/");
    if (lstat(controlfile,&mscriptstab)) ohshite("unable to stat control directory");
    if (!S_ISDIR(mscriptstab.st_mode)) ohshit("control directory is not a directory");
    if ((mscriptstab.st_mode & 07757) != 0755)
      ohshit(_("control directory has bad permissions %03lo (must be >=0755 "
             "and <=0775)"), (unsigned long)(mscriptstab.st_mode & 07777));

    for (mscriptp= maintainerscripts; *mscriptp; mscriptp++) {
      strcpy(controlfile, directory);
      strcat(controlfile, "/" BUILDCONTROLDIR "/");
      strcat(controlfile, *mscriptp);

      if (!lstat(controlfile,&mscriptstab)) {
        if (S_ISLNK(mscriptstab.st_mode)) continue;
        if (!S_ISREG(mscriptstab.st_mode))
          ohshit(_("maintainer script `%.50s' is not a plain file or symlink"),*mscriptp);
        if ((mscriptstab.st_mode & 07557) != 0555)
          ohshit(_("maintainer script `%.50s' has bad permissions %03lo "
                 "(must be >=0555 and <=0775)"),
                 *mscriptp, (unsigned long)(mscriptstab.st_mode & 07777));
      } else if (errno != ENOENT) {
        ohshite(_("maintainer script `%.50s' is not stattable"),*mscriptp);
      }
    }

    /* Check if conffiles contains sane information */
    strcpy(controlfile, directory);
    strcat(controlfile, "/" BUILDCONTROLDIR "/" CONFFILESFILE);
    if ((cf= fopen(controlfile,"r"))) {
      while (fgets(conffilename,MAXCONFFILENAME+1,cf)) {
        n= strlen(conffilename);
        if (!n) ohshite(_("empty string from fgets reading conffiles"));
        if (conffilename[n-1] != '\n') {
          fprintf(stderr, _("warning, conffile name `%.50s...' is too long, or missing final newline\n"), 
		  conffilename);
          warns++;
          while ((c= getc(cf)) != EOF && c != '\n');
          continue;
        }
        conffilename[n-1]= 0;
        strcpy(controlfile, directory);
        strcat(controlfile, "/");
        strcat(controlfile, conffilename);
        if (lstat(controlfile,&controlstab)) {
          if (errno == ENOENT)
            ohshit(_("conffile `%.250s' does not appear in package"),conffilename);
          else
            ohshite(_("conffile `%.250s' is not stattable"),conffilename);
        } else if (!S_ISREG(controlstab.st_mode)) {
          fprintf(stderr, _("warning, conffile `%s'"
                  " is not a plain file\n"), conffilename);
          warns++;
        }
      }
      if (ferror(cf)) ohshite(_("error reading conffiles file"));
      fclose(cf);
    } else if (errno != ENOENT) {
      ohshite(_("error opening conffiles file"));
    }
    if (warns) {
      if (fprintf(stderr, _("dpkg-deb: ignoring %d warnings about the control"
                  " file(s)\n"), warns) == EOF) werr("stderr");
    }
  }
  if (ferror(stdout)) werr("stdout");
  
  /* Now that we have verified everything its time to actually
   * build something. Lets start by making the ar-wrapper.
   */
  if (!(ar=fopen(debar,"wb"))) ohshite(_("unable to create `%.255s'"),debar);
  if (setvbuf(ar, 0, _IONBF, 0)) ohshite(_("unable to unbuffer `%.255s'"),debar);
  /* Fork a tar to package the control-section of the package */
  m_pipe(p1);
  if (!(c1= m_fork())) {
    m_dup2(p1[1],1); close(p1[0]); close(p1[1]);
    if (chdir(directory)) ohshite(_("failed to chdir to `%.255s'"),directory);
    if (chdir(BUILDCONTROLDIR)) ohshite(_("failed to chdir to .../DEBIAN"));
    execlp(TAR,"tar","-cf","-",".",(char*)0); ohshite(_("failed to exec tar -cf"));
  }
  close(p1[1]);
  /* Create a temporary file to store the control data in. Immediately unlink
   * our temporary file so others can't mess with it.
   */
  if ((gzfd= mkstemp(tfbuf)) == -1) ohshite(_("failed to make tmpfile (control)"));
  if ((gz= fdopen(gzfd,"a")) == NULL) ohshite(_("failed to open tmpfile "
      "(control), %s"), tfbuf);
  /* make sure it's gone, the fd will remain until we close it */
  if (unlink(tfbuf)) ohshit(_("failed to unlink tmpfile (control), %s"),
      tfbuf);
  /* reset this, so we can use it elsewhere */
  strcpy(tfbuf,envbuf);
  strcat(tfbuf,"/dpkg.XXXXXX");
  /* And run gzip to compress our control archive */
  if (!(c2= m_fork())) {
    m_dup2(p1[0],0); m_dup2(gzfd,1); close(p1[0]); close(gzfd);
    compress_cat(GZ, 0, 1, "9", _("control"));
  }
  close(p1[0]);
  waitsubproc(c2,"gzip -9c",0);
  waitsubproc(c1,"tar -cf",0);
  if (fstat(gzfd,&controlstab)) ohshite(_("failed to fstat tmpfile (control)"));
  /* We have our first file for the ar-archive. Write a header for it to the
   * package and insert it.
   */
  if (oldformatflag) {
    if (fprintf(ar, "%-8s\n%ld\n", OLDARCHIVEVERSION, (long)controlstab.st_size) == EOF)
      werr(debar);
  } else {
    thetime= time(0);
    if (fprintf(ar,
                "!<arch>\n"
                "debian-binary   %-12lu0     0     100644  %-10ld`\n"
                ARCHIVEVERSION "\n"
                "%s"
                ADMINMEMBER "%-12lu0     0     100644  %-10ld`\n",
                thetime,
                (long)sizeof(ARCHIVEVERSION),
                (sizeof(ARCHIVEVERSION)&1) ? "\n" : "",
                (unsigned long)thetime,
                (long)controlstab.st_size) == EOF)
      werr(debar);
  }                
                
  if (lseek(gzfd,0,SEEK_SET)) ohshite(_("failed to rewind tmpfile (control)"));
  fd_fd_copy(gzfd, fileno(ar), -1, _("control"));

  /* Control is done, now we need to archive the data. Start by creating
   * a new temporary file. Immediately unlink the temporary file so others
   * can't mess with it. */
  if (!oldformatflag) {
    fclose(gz);
    if ((gzfd= mkstemp(tfbuf)) == -1) ohshite(_("failed to make tmpfile (data)"));
    if ((gz= fdopen(gzfd,"a")) == NULL) ohshite(_("failed to open tmpfile "
        "(data), %s"), tfbuf);
    /* make sure it's gone, the fd will remain until we close it */
    if (unlink(tfbuf)) ohshit(_("failed to unlink tmpfile (data), %s"),
        tfbuf);
    /* reset these, in case we want to use the later */
    strcpy(tfbuf,envbuf);
    strcat(tfbuf,"/dpkg.XXXXXX");
  }
  /* Fork off a tar. We will feed it a list of filenames on stdin later.
   */
  m_pipe(p1);
  m_pipe(p2);
  if (!(c1= m_fork())) {
    m_dup2(p1[0],0); close(p1[0]); close(p1[1]);
    m_dup2(p2[1],1); close(p2[0]); close(p2[1]);
    if (chdir(directory)) ohshite(_("failed to chdir to `%.255s'"),directory);
    execlp(TAR,"tar","-cf", "-", "-T", "-", "--null", "--no-recursion", (char*)0);
    ohshite(_("failed to exec tar -cf"));
  }
  close(p1[0]);
  close(p2[1]);
  /* Of course we should not forget to compress the archive as well.. */
  if (!(c2= m_fork())) {
    close(p1[1]);
    m_dup2(p2[0],0); close(p2[0]);
    m_dup2(oldformatflag ? fileno(ar) : gzfd,1);
    compress_cat(compress_type, 0, 1, compression, _("data"));
  }
  close(p2[0]);
  /* All the pipes are set, now lets run find, and start feeding
   * filenames to tar.
   */

  m_pipe(p3);
  if (!(c3= m_fork())) {
    m_dup2(p3[1],1); close(p3[0]); close(p3[1]);
    if (chdir(directory)) ohshite(_("failed to chdir to `%.255s'"),directory);
    execlp(FIND,"find",".","-path","./" BUILDCONTROLDIR,"-prune","-o","-print0",(char*)0);
    ohshite(_("failed to exec find"));
  }
  close(p3[1]);
  /* We need to reorder the files so we can make sure that symlinks
   * will not appear before their target.
   */
  while ((fi=getfi(directory, p3[0]))!=NULL)
    if (S_ISLNK(fi->st.st_mode))
      add_to_filist(fi,&symlist,&symlist_end);
    else {
      if (write(p1[1], fi->fn, strlen(fi->fn)+1) ==- 1)
	ohshite(_("failed to write filename to tar pipe (data)"));
    }
  close(p3[0]);
  waitsubproc(c3,"find",0);

  for (fi= symlist;fi;fi= fi->next)
    if (write(p1[1], fi->fn, strlen(fi->fn)+1) == -1)
      ohshite(_("failed to write filename to tar pipe (data)"));
  /* All done, clean up wait for tar and gzip to finish their job */
  close(p1[1]);
  free_filist(symlist);
  waitsubproc(c2,"<compress> from tar -cf",0);
  waitsubproc(c1,"tar -cf",0);
  /* Okay, we have data.tar.gz as well now, add it to the ar wrapper */
  if (!oldformatflag) {
    const char *datamember;
    switch (compress_type) {
      case GZ: datamember= DATAMEMBER_GZ; break;
      case BZ2: datamember= DATAMEMBER_BZ2; break;
      case CAT: datamember= DATAMEMBER_CAT; break;
      default:
        ohshit(_("Internal error, compress_type `%i' unknown!"), compress_type);
    }
    if (fstat(gzfd,&datastab)) ohshite("_(failed to fstat tmpfile (data))");
    if (fprintf(ar,
                "%s"
                "%s" "%-12lu0     0     100644  %-10ld`\n",
                (controlstab.st_size & 1) ? "\n" : "",
                datamember,
                (unsigned long)thetime,
                (long)datastab.st_size) == EOF)
      werr(debar);

    if (lseek(gzfd,0,SEEK_SET)) ohshite(_("failed to rewind tmpfile (data)"));
    fd_fd_copy(gzfd, fileno(ar), -1, _("cat (data)"));

    if (datastab.st_size & 1)
      if (putc('\n',ar) == EOF)
        werr(debar);
  }
  if (fclose(ar)) werr(debar);
                             
  exit(0);
}

