/*
 * dpkg-deb - construction and deconstruction of *.deb archives
 * info.c - providing information
 *
 * Copyright (C) 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright (C) 2001 Wichert Akkerman
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

#include <dpkg.h>
#include <dpkg-db.h>
#include <myopt.h>
#include "dpkg-deb.h"

static void cu_info_prepare(int argc, void **argv) {
  pid_t c1;
  int status;
  char *directory;
  struct stat stab;

  directory= (char*)(argv[0]);
  if (chdir("/")) { perror(_("failed to chdir to `/' for cleanup")); return; }
  if (lstat(directory,&stab) && errno==ENOENT) return;
  if ((c1= fork()) == -1) { perror(_("failed to fork for cleanup")); return; }
  if (!c1) {
    execlp(RM,"rm","-rf",directory,(char*)0);
    perror(_("failed to exec rm for cleanup")); _exit(1);
  }
  if (waitpid(c1,&status,0) != c1) { perror(_("failed to wait for rm cleanup")); return; }
  if (status) { fprintf(stderr,_("rm cleanup failed, code %d\n"),status); }
} 

static void info_prepare(const char *const **argvp,
                         const char **debarp,
                         const char **directoryp,
                         int admininfo) {
  static char *dbuf;
  pid_t c1;
  
  *debarp= *(*argvp)++;
  if (!*debarp) badusage(_("--%s needs a .deb filename argument"),cipaction->olong);
  /* This creates a temporary directory, so ignore the warning. */
  if ((dbuf= tempnam(NULL,"dpkg")) == NULL)
    ohshite(_("failed to make temporary directoryname"));
  *directoryp= dbuf;

  if (!(c1= m_fork())) {
    execlp(RM,"rm","-rf",dbuf,(char*)0); ohshite(_("failed to exec rm -rf"));
  }
  waitsubproc(c1,"rm -rf",0);
  push_cleanup(cu_info_prepare,-1, 0,0, 1, (void*)dbuf);
  extracthalf(*debarp, dbuf, "mx", admininfo);
}

static int ilist_select(const struct dirent *de) {
  return strcmp(de->d_name,".") && strcmp(de->d_name,"..");
}

static void info_spew(const char *debar, const char *directory,
                      const char *const *argv) {
  const char *component;
  FILE *co;
  int re= 0;

  while ((component= *argv++) != 0) {
    co= fopen(component,"r");
    if (co) {
      stream_fd_copy(co, 1, -1, _("info_spew"));
    } else if (errno == ENOENT) {
      if (fprintf(stderr, _("dpkg-deb: `%.255s' contains no control component `%.255s'\n"),
                  debar, component) == EOF) werr("stderr");
      re++;
    } else {
      ohshite(_("open component `%.255s' (in %.255s) failed in an unexpected way"),
              component, directory);
    }
  }
  if (re==1)
    ohshit(_("One requested control component is missing"));
  else if (re>1)
    ohshit(_("%d requested control components are missing"), re);
}

static void info_list(const char *debar, const char *directory) {
  char interpreter[INTERPRETER_MAX+1], *p;
  int il, lines;
  struct dirent **cdlist, *cdep;
  int cdn;
  FILE *cc;
  struct stat stab;
  int c;

  cdn= scandir(".", &cdlist, &ilist_select, alphasort);
  if (cdn == -1) ohshite(_("cannot scan directory `%.255s'"),directory);

  while (cdn-- >0) {
    cdep= *cdlist++;
    if (stat(cdep->d_name,&stab))
      ohshite(_("cannot stat `%.255s' (in `%.255s')"),cdep->d_name,directory);
    if (S_ISREG(stab.st_mode)) {
      if (!(cc= fopen(cdep->d_name,"r")))
        ohshite(_("cannot open `%.255s' (in `%.255s')"),cdep->d_name,directory);
      lines= 0; interpreter[0]= 0;
      if ((c= getc(cc))== '#') {
        if ((c= getc(cc))== '!') {
          while ((c= getc(cc))== ' ');
          p=interpreter; *p++='#'; *p++='!'; il=2;
          while (il<INTERPRETER_MAX && !isspace(c) && c!=EOF) {
            *p++= c; il++; c= getc(cc);
          }
          *p++= 0;
          if (c=='\n') lines++;
        }
      }
      while ((c= getc(cc))!= EOF) { if (c == '\n') lines++; }
      if (ferror(cc)) ohshite(_("failed to read `%.255s' (in `%.255s')"),
                              cdep->d_name,directory);
      fclose(cc);
      if (printf(_(" %7ld bytes, %5d lines   %c  %-20.127s %.127s\n"),
                 (long)stab.st_size, lines,
                 S_IXUSR & stab.st_mode ? '*' : ' ',
                 cdep->d_name, interpreter) == EOF)
        werr("stdout");
    } else {
      if (printf(_("     not a plain file          %.255s\n"),cdep->d_name) == EOF)
        werr("stdout");
    }
  }
  if (!(cc= fopen("control","r"))) {
    if (errno != ENOENT) ohshite(_("failed to read `control' (in `%.255s')"),directory);
    if (fputs(_("(no `control' file in control archive!)\n"),stdout) < 0) werr("stdout");
  } else {
    lines= 1;
    while ((c= getc(cc))!= EOF) {
      if (lines) if (putc(' ',stdout) == EOF) werr("stdout");
      if (putc(c,stdout) == EOF) werr("stdout");
      lines= c=='\n';
    }
    if (!lines) if (putc('\n',stdout) == EOF) werr("stdout");
  }
}

static void info_field(const char *debar, const char *directory,
                       const char *const *fields, int showfieldname) {
  FILE *cc;
  char fieldname[MAXFIELDNAME+1];
  char *pf;
  const char *const *fp;
  int doing, c, lno, fnl;

  if (!(cc= fopen("control","r"))) ohshite(_("could not open the `control' component"));
  doing= 1; lno= 1;
  for (;;) {
    c= getc(cc);  if (c==EOF) { doing=0; break; }
    if (c == '\n') { lno++; doing=1; continue; }
    if (!isspace(c)) {
      doing= 0;
      for (pf=fieldname, fnl=0;
           fnl <= MAXFIELDNAME && c!=EOF && !isspace(c) && c!=':';
           c= getc(cc)) { *pf++= c; fnl++; }
      *pf++= 0;
      doing= fnl >= MAXFIELDNAME || c=='\n' || c==EOF;
      for (fp=fields; !doing && *fp; fp++)
        if (!strcasecmp(*fp,fieldname)) doing=1;
      if (showfieldname) {
        if (doing)
          fputs(fieldname,stdout);
      } else {
        if (c==':') c= getc(cc);
        while (c != '\n' && isspace(c)) c= getc(cc);
      }
    }
    for(;;) {
      if (c == EOF) break;
      if (doing) putc(c,stdout);
      if (c == '\n') { lno++; break; }
      c= getc(cc);
    }
    if (c == EOF) break;
  }
  if (ferror(cc)) ohshite(_("failed during read of `control' component"));
  if (doing) putc('\n',stdout);
  if (ferror(stdout)) werr("stdout");
}

void do_showinfo(const char* const* argv) {
  const char *debar, *directory;
  struct pkginfo *pkg;
  struct lstitem* fmt = parseformat(showformat);

  if (!fmt)
    ohshit(_("Error in format"));

  info_prepare(&argv,&debar,&directory,1);

  parsedb(CONTROLFILE, pdb_ignorefiles, &pkg, NULL, NULL);
  show1package(fmt,pkg);
}


void do_info(const char *const *argv) {
  const char *debar, *directory;

  if (*argv && argv[1]) {
    info_prepare(&argv,&debar,&directory,1);
    info_spew(debar,directory, argv);
  } else {
    info_prepare(&argv,&debar,&directory,2);
    info_list(debar,directory);
  }
}

void do_field(const char *const *argv) {
  const char *debar, *directory;

  info_prepare(&argv,&debar,&directory,1);
  if (*argv) {
    info_field(debar, directory, argv, argv[1]!=0);
  } else {
    static const char *const controlonly[]= { "control", 0 };
    info_spew(debar,directory, controlonly);
  }
}

void do_contents(const char *const *argv) {
  const char *debar;
  
  if (!(debar= *argv++) || *argv) badusage(_("--contents takes exactly one argument"));
  extracthalf(debar, 0, "tv", 0);
}
/* vi: sw=2
 */
