/*
 * dpkg-deb - construction and deconstruction of *.deb archives
 * build.c - building archives
 *
 * Copyright (C) 1994,1995 Ian Jackson <iwj10@cus.cam.ac.uk>
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

#include "config.h"
#include "dpkg.h"
#include "dpkg-db.h"
#include "dpkg-deb.h"

#ifndef S_ISLNK
# define S_ISLNK(mode) ((mode&0xF000) == S_IFLNK)
#endif

static void checkversion(const char *vstring, const char *fieldname, int *errs) {
  const char *p;
  if (!vstring || !*vstring) return;
  for (p=vstring; *p; p++) if (isdigit(*p)) return;
  fprintf(stderr, BACKEND " - error: %s field (`%s') doesn't contain any digits\n",
          fieldname, vstring);
  (*errs)++;
}

void do_build(const char *const *argv) {
  static const char *const maintainerscripts[]= {
    PREINSTFILE, POSTINSTFILE, PRERMFILE, POSTRMFILE, 0
  };
  
  char *m;
  const char *debar, *directory, *const *mscriptp;
  char *controlfile;
  struct pkginfo *checkedinfo;
  struct arbitraryfield *field;
  FILE *ar, *gz, *cf;
  int p1[2],p2[2], warns, errs, n, c;
  pid_t c1,c2,c3,c4,c5;
  struct stat controlstab, datastab, mscriptstab;
  char conffilename[MAXCONFFILENAME+1];
  time_t thetime= 0;
  
  directory= *argv++; if (!directory) badusage("--build needs a directory argument");
  if ((debar= *argv++) !=0) {
    if (*argv) badusage("--build takes at most two arguments");
  } else {
    m= m_malloc(strlen(directory) + sizeof(DEBEXT));
    strcpy(m,directory); strcat(m,DEBEXT);
    debar= m;
  }
  
  if (nocheckflag) {
    printf(BACKEND ": warning, not checking contents of control area.\n"
           BACKEND ": building an unknown package in `%s'.\n", debar);
  } else {
    controlfile= m_malloc(strlen(directory) + sizeof(BUILDCONTROLDIR) +
                          sizeof(CONTROLFILE) + sizeof(CONFFILESFILE) +
                          sizeof(POSTINSTFILE) + sizeof(PREINSTFILE) +
                          sizeof(POSTRMFILE) + sizeof(PRERMFILE) +
                          MAXCONFFILENAME + 5);
    strcpy(controlfile, directory);
    strcat(controlfile, "/" BUILDCONTROLDIR "/" CONTROLFILE);
    warns= 0; errs= 0;
    parsedb(controlfile, pdb_recordavailable|pdb_rejectstatus,
            &checkedinfo, stderr, &warns);
    assert(checkedinfo->available.valid);
    if (strspn(checkedinfo->name,
               "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-.")
        != strlen(checkedinfo->name))
      ohshit("package name has characters that aren't alphanums or `-+.'");
    if (checkedinfo->priority == pri_other) {
      fprintf(stderr, "warning, `%s' contains user-defined Priority value `%s'\n",
              controlfile, checkedinfo->otherpriority);
      warns++;
    }
    for (field= checkedinfo->available.arbs; field; field= field->next) {
      fprintf(stderr, "warning, `%s' contains user-defined field `%s'\n",
              controlfile, field->name);
      warns++;
    }
    checkversion(checkedinfo->available.version,"Version",&errs);
    checkversion(checkedinfo->available.revision,"Revision",&errs);
    if (errs) ohshit("%d errors in control file",errs);
    printf(BACKEND ": building package `%s' in `%s'.\n", checkedinfo->name, debar);

    strcpy(controlfile, directory);
    strcat(controlfile, "/" BUILDCONTROLDIR "/");
    if (lstat(controlfile,&mscriptstab)) ohshite("unable to stat control directory");
    if (!S_ISDIR(mscriptstab.st_mode)) ohshit("control directory is not a directory");
    if ((mscriptstab.st_mode & 07757) != 0755)
      ohshit("control directory has bad permissions %03lo (must be >=0755 "
             "and <=0775)", (unsigned long)(mscriptstab.st_mode & 07777));

    for (mscriptp= maintainerscripts; *mscriptp; mscriptp++) {
      strcpy(controlfile, directory);
      strcat(controlfile, "/" BUILDCONTROLDIR "/");
      strcat(controlfile, *mscriptp);

      if (!lstat(controlfile,&mscriptstab)) {
        if (S_ISLNK(mscriptstab.st_mode)) continue;
        if (!S_ISREG(mscriptstab.st_mode))
          ohshit("maintainer script `%.50s' is not a plain file or symlink",*mscriptp);
        if ((mscriptstab.st_mode & 07557) != 0555)
          ohshit("maintainer script `%.50s' has bad permissions %03lo "
                 "(must be >=0555 and <=0775)",
                 *mscriptp, (unsigned long)(mscriptstab.st_mode & 07777));
      } else if (errno != ENOENT) {
        ohshite("maintainer script `%.50s' is not stattable",*mscriptp);
      }
    }

    strcpy(controlfile, directory);
    strcat(controlfile, "/" BUILDCONTROLDIR "/" CONFFILESFILE);
    if ((cf= fopen(controlfile,"r"))) {
      while (fgets(conffilename,MAXCONFFILENAME+1,cf)) {
        n= strlen(conffilename);
        if (!n) ohshite("empty string from fgets reading conffiles");
        if (conffilename[n-1] != '\n') {
          fprintf(stderr, "warning, conffile name `%.50s...' is too long", conffilename);
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
            ohshit("conffile `%.250s' does not appear in package",conffilename);
          else
            ohshite("conffile `%.250s' is not stattable",conffilename);
        } else if (!S_ISREG(controlstab.st_mode)) {
          fprintf(stderr, "warning, conffile `%s'"
                  " is not a plain file\n", conffilename);
          warns++;
        }
      }
      if (ferror(cf)) ohshite("error reading conffiles file");
      fclose(cf);
    } else if (errno != ENOENT) {
      ohshite("error opening conffiles file");
    }
    if (warns) {
      if (fprintf(stderr, BACKEND ": ignoring %d warnings about the control"
                  " file(s)\n", warns) == EOF) werr("stderr");
    }
  }
  if (ferror(stdout)) werr("stdout");
  
  if (!(ar=fopen(debar,"wb"))) ohshite("unable to create `%.255s'",debar);
  if (setvbuf(ar, 0, _IONBF, 0)) ohshite("unable to unbuffer `%.255s'",debar);
  m_pipe(p1);
  if (!(c1= m_fork())) {
    m_dup2(p1[1],1); close(p1[0]); close(p1[1]);
    if (chdir(directory)) ohshite("failed to chdir to `%.255s'",directory);
    if (chdir(BUILDCONTROLDIR)) ohshite("failed to chdir to .../" BUILDCONTROLDIR);
    execlp(TAR,"tar","-cf","-",".",(char*)0); ohshite("failed to exec tar -cf");
  }
  close(p1[1]);
  if (!(gz= tmpfile())) ohshite("failed to make tmpfile (control)");
  if (!(c2= m_fork())) {
    m_dup2(p1[0],0); m_dup2(fileno(gz),1); close(p1[0]);
    execlp(GZIP,"gzip","-9c",(char*)0); ohshite("failed to exec gzip -9c");
  }
  close(p1[0]);
  waitsubproc(c2,"gzip -9c",0);
  waitsubproc(c1,"tar -cf",0);
  if (fstat(fileno(gz),&controlstab)) ohshite("failed to fstat tmpfile (control)");
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
                
  if (lseek(fileno(gz),0,SEEK_SET)) ohshite("failed to rewind tmpfile (control)");
  if (!(c3= m_fork())) {
    m_dup2(fileno(gz),0); m_dup2(fileno(ar),1);
    execlp(CAT,"cat",(char*)0); ohshite("failed to exec cat (control)");
  }
  waitsubproc(c3,"cat (control)",0);
  
  if (!oldformatflag) {
    fclose(gz);
    if (!(gz= tmpfile())) ohshite("failed to make tmpfile (data)");
  }
  m_pipe(p2);
  if (!(c4= m_fork())) {
    m_dup2(p2[1],1); close(p2[0]); close(p2[1]);
    if (chdir(directory)) ohshite("failed to chdir to `%.255s'",directory);
    execlp(TAR,"tar","--exclude",BUILDCONTROLDIR,"-cf","-",".",(char*)0);
    ohshite("failed to exec tar --exclude");
  }
  close(p2[1]);
  if (!(c5= m_fork())) {
    m_dup2(p2[0],0); close(p2[0]);
    m_dup2(oldformatflag ? fileno(ar) : fileno(gz),1);
    execlp(GZIP,"gzip","-9c",(char*)0);
    ohshite("failed to exec gzip -9c from tar --exclude");
  }
  close(p2[0]);
  waitsubproc(c5,"gzip -9c from tar --exclude",0);
  waitsubproc(c4,"tar --exclude",0);
  if (!oldformatflag) {
    if (fstat(fileno(gz),&datastab)) ohshite("failed to fstat tmpfile (data)");
    if (fprintf(ar,
                "%s"
                DATAMEMBER "%-12lu0     0     100644  %-10ld`\n",
                (controlstab.st_size & 1) ? "\n" : "",
                (unsigned long)thetime,
                (long)datastab.st_size) == EOF)
      werr(debar);

    if (lseek(fileno(gz),0,SEEK_SET)) ohshite("failed to rewind tmpfile (data)");
    if (!(c3= m_fork())) {
      m_dup2(fileno(gz),0); m_dup2(fileno(ar),1);
      execlp(CAT,"cat",(char*)0); ohshite("failed to exec cat (data)");
    }
    waitsubproc(c3,"cat (data)",0);

    if (datastab.st_size & 1)
      if (putc('\n',ar) == EOF)
        werr(debar);
  }
  if (fclose(ar)) werr(debar);
                             
  exit(0);
}

