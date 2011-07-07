/*
 * dpkg-deb - construction and deconstruction of *.deb archives
 * info.c - providing information
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2001 Wichert Akkerman
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

#include <errno.h>
#include <limits.h>
#include <ctype.h>
#include <string.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/pkg-format.h>
#include <dpkg/buffer.h>
#include <dpkg/path.h>
#include <dpkg/subproc.h>
#include <dpkg/options.h>

#include "dpkg-deb.h"

static void cu_info_prepare(int argc, void **argv) {
  pid_t pid;
  char *dir;
  struct stat stab;

  dir = argv[0];
  if (lstat(dir, &stab) && errno == ENOENT)
    return;

  pid = subproc_fork();
  if (pid == 0) {
    if (chdir("/"))
      ohshite(_("failed to chdir to `/' for cleanup"));
    execlp(RM, "rm", "-rf", dir, NULL);
    ohshite(_("unable to execute %s (%s)"), _("rm command for cleanup"), RM);
  }
  subproc_wait_check(pid, _("rm command for cleanup"), 0);
}

static void info_prepare(const char *const **argvp,
                         const char **debarp,
                         const char **dirp,
                         int admininfo) {
  char *dbuf;

  *debarp= *(*argvp)++;
  if (!*debarp) badusage(_("--%s needs a .deb filename argument"),cipaction->olong);

  dbuf = mkdtemp(path_make_temp_template("dpkg-deb"));
  if (!dbuf)
    ohshite(_("unable to create temporary directory"));
  *dirp = dbuf;

  push_cleanup(cu_info_prepare, -1, NULL, 0, 1, (void *)dbuf);
  extracthalf(*debarp, dbuf, "mx", admininfo);
}

static int ilist_select(const struct dirent *de) {
  return strcmp(de->d_name,".") && strcmp(de->d_name,"..");
}

static void
info_spew(const char *debar, const char *dir, const char *const *argv)
{
  const char *component;
  struct varbuf controlfile = VARBUF_INIT;
  int fd;
  int re= 0;

  while ((component = *argv++) != NULL) {
    varbuf_reset(&controlfile);
    varbuf_add_str(&controlfile, dir);
    varbuf_add_char(&controlfile, '/');
    varbuf_add_str(&controlfile, component);
    varbuf_end_str(&controlfile);

    fd = open(controlfile.buf, O_RDONLY);
    if (fd >= 0) {
      fd_fd_copy(fd, 1, -1, _("control file '%s'"), controlfile.buf);
      close(fd);
    } else if (errno == ENOENT) {
      fprintf(stderr,
              _("dpkg-deb: `%.255s' contains no control component `%.255s'\n"),
              debar, component);
      re++;
    } else {
      ohshite(_("open component `%.255s' (in %.255s) failed in an unexpected way"),
              component, dir);
    }
  }
  varbuf_destroy(&controlfile);

  if (re > 0)
    ohshit(P_("%d requested control component is missing",
              "%d requested control components are missing", re), re);
}

static void
info_list(const char *debar, const char *dir)
{
  char interpreter[INTERPRETER_MAX+1], *p;
  int il, lines;
  struct varbuf controlfile = VARBUF_INIT;
  struct dirent **cdlist, *cdep;
  int cdn, n;
  FILE *cc;
  struct stat stab;
  int c;
  size_t dirlen;

  cdn = scandir(dir, &cdlist, &ilist_select, alphasort);
  if (cdn == -1)
    ohshite(_("cannot scan directory `%.255s'"), dir);
  varbuf_add_str(&controlfile, dir);
  varbuf_add_char(&controlfile, '/');
  dirlen = controlfile.used;

  for (n = 0; n < cdn; n++) {
    cdep = cdlist[n];
    varbuf_trunc(&controlfile, dirlen);
    varbuf_add_str(&controlfile, cdep->d_name);
    varbuf_end_str(&controlfile);
    if (stat(controlfile.buf, &stab))
      ohshite(_("cannot stat `%.255s' (in `%.255s')"), cdep->d_name, dir);
    if (S_ISREG(stab.st_mode)) {
      cc = fopen(controlfile.buf, "r");
      if (!cc)
        ohshite(_("cannot open `%.255s' (in `%.255s')"), cdep->d_name, dir);
      lines = 0;
      interpreter[0] = '\0';
      if (getc(cc) == '#') {
        if (getc(cc) == '!') {
          while ((c= getc(cc))== ' ');
          p=interpreter; *p++='#'; *p++='!'; il=2;
          while (il<INTERPRETER_MAX && !isspace(c) && c!=EOF) {
            *p++= c; il++; c= getc(cc);
          }
          *p = '\0';
          if (c=='\n') lines++;
        }
      }
      while ((c= getc(cc))!= EOF) { if (c == '\n') lines++; }
      if (ferror(cc)) ohshite(_("failed to read `%.255s' (in `%.255s')"),
                              cdep->d_name, dir);
      fclose(cc);
      printf(_(" %7jd bytes, %5d lines   %c  %-20.127s %.127s\n"),
             (intmax_t)stab.st_size, lines, S_IXUSR & stab.st_mode ? '*' : ' ',
             cdep->d_name, interpreter);
    } else {
      printf(_("     not a plain file          %.255s\n"), cdep->d_name);
    }
    free(cdep);
  }
  free(cdlist);

  varbuf_trunc(&controlfile, dirlen);
  varbuf_add_str(&controlfile, CONTROLFILE);
  varbuf_end_str(&controlfile);
  cc = fopen(controlfile.buf, "r");
  if (!cc) {
    if (errno != ENOENT)
      ohshite(_("failed to read `%.255s' (in `%.255s')"), CONTROLFILE, dir);
    fputs(_("(no `control' file in control archive!)\n"), stdout);
  } else {
    lines= 1;
    while ((c= getc(cc))!= EOF) {
      if (lines)
        putc(' ', stdout);
      putc(c, stdout);
      lines= c=='\n';
    }
    if (!lines)
      putc('\n', stdout);

    if (ferror(cc))
      ohshite(_("failed to read `%.255s' (in `%.255s')"), CONTROLFILE, dir);
    fclose(cc);
  }

  m_output(stdout, _("<standard output>"));
  varbuf_destroy(&controlfile);
}

static void
info_field(const char *debar, const char *dir, const char *const *fields,
           bool showfieldname)
{
  struct varbuf controlfile = VARBUF_INIT;
  FILE *cc;
  char fieldname[MAXFIELDNAME+1];
  char *pf;
  const char *const *fp;
  int c, lno, fnl;
  bool doing;

  varbuf_add_str(&controlfile, dir);
  varbuf_add_char(&controlfile, '/');
  varbuf_add_str(&controlfile, CONTROLFILE);
  varbuf_end_str(&controlfile);
  cc = fopen(controlfile.buf, "r");
  if (!cc)
    ohshite(_("could not open the `control' component"));
  doing = true;
  lno = 1;
  for (;;) {
    c = getc(cc);
    if (c == EOF) {
      doing = false;
      break;
    }
    if (c == '\n') {
      lno++;
      doing = true;
      continue;
    }
    if (!isspace(c)) {
      for (pf=fieldname, fnl=0;
           fnl <= MAXFIELDNAME && c!=EOF && !isspace(c) && c!=':';
           c= getc(cc)) { *pf++= c; fnl++; }
      *pf = '\0';
      doing= fnl >= MAXFIELDNAME || c=='\n' || c==EOF;
      for (fp=fields; !doing && *fp; fp++)
        if (!strcasecmp(*fp, fieldname))
          doing = true;
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
  if (fclose(cc))
    ohshite(_("error closing the '%s' component"), CONTROLFILE);
  if (doing) putc('\n',stdout);
  m_output(stdout, _("<standard output>"));
  varbuf_destroy(&controlfile);
}

int
do_showinfo(const char *const *argv)
{
  struct varbuf controlfile = VARBUF_INIT;
  const char *debar, *dir;
  struct pkginfo *pkg;
  struct pkg_format_node *fmt = pkg_format_parse(showformat);

  if (!fmt)
    ohshit(_("Error in format"));

  info_prepare(&argv, &debar, &dir, 1);

  varbuf_add_str(&controlfile, dir);
  varbuf_add_char(&controlfile, '/');
  varbuf_add_str(&controlfile, CONTROLFILE);
  varbuf_end_str(&controlfile);
  parsedb(controlfile.buf,
          pdb_recordavailable | pdb_rejectstatus | pdb_ignorefiles, &pkg);
  pkg_format_show(fmt, pkg, &pkg->available);
  varbuf_destroy(&controlfile);

  return 0;
}

int
do_info(const char *const *argv)
{
  const char *debar, *dir;

  if (*argv && argv[1]) {
    info_prepare(&argv, &debar, &dir, 1);
    info_spew(debar, dir, argv);
  } else {
    info_prepare(&argv, &debar, &dir, 2);
    info_list(debar, dir);
  }

  return 0;
}

int
do_field(const char *const *argv)
{
  const char *debar, *dir;

  info_prepare(&argv, &debar, &dir, 1);
  if (*argv) {
    info_field(debar, dir, argv, argv[1] != NULL);
  } else {
    static const char *const controlonly[] = { CONTROLFILE, NULL };
    info_spew(debar, dir, controlonly);
  }

  return 0;
}

int
do_contents(const char *const *argv)
{
  const char *debar;

  if (!(debar= *argv++) || *argv) badusage(_("--contents takes exactly one argument"));
  extracthalf(debar, NULL, "tv", 0);

  return 0;
}
/* vi: sw=2
 */
