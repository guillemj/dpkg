/*
 * dpkg-deb - construction and deconstruction of *.deb archives
 * info.c - providing information
 *
 * Copyright © 1994,1995 Ian Jackson <ijackson@chiark.greenend.org.uk>
 * Copyright © 2001 Wichert Akkerman
 * Copyright © 2007-2015 Guillem Jover <guillem@debian.org>
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
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include <config.h>
#include <compat.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <errno.h>
#include <limits.h>
#include <string.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/c-ctype.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/parsedump.h>
#include <dpkg/pkg-format.h>
#include <dpkg/buffer.h>
#include <dpkg/path.h>
#include <dpkg/options.h>

#include "dpkg-deb.h"

static void cu_info_prepare(int argc, void **argv) {
  char *dir;

  dir = argv[0];
  path_remove_tree(dir);
  free(dir);
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

  push_cleanup(cu_info_prepare, -1, 1, (void *)dbuf);
  extracthalf(*debarp, dbuf, DPKG_TAR_EXTRACT | DPKG_TAR_NOMTIME, admininfo);
}

static int ilist_select(const struct dirent *de) {
  return strcmp(de->d_name,".") && strcmp(de->d_name,"..");
}

static void
info_spew(const char *debar, const char *dir, const char *const *argv)
{
  struct dpkg_error err;
  const char *component;
  struct varbuf controlfile = VARBUF_INIT;
  int fd;
  int re= 0;

  while ((component = *argv++) != NULL) {
    varbuf_reset(&controlfile);
    varbuf_printf(&controlfile, "%s/%s", dir, component);

    fd = open(controlfile.buf, O_RDONLY);
    if (fd >= 0) {
      if (fd_fd_copy(fd, 1, -1, &err) < 0)
        ohshit(_("cannot extract control file '%s' from '%s': %s"),
               controlfile.buf, debar, err.str);
      close(fd);
    } else if (errno == ENOENT) {
      notice(_("'%.255s' contains no control component '%.255s'"),
             debar, component);
      re++;
    } else {
      ohshite(_("open component '%.255s' (in %.255s) failed in an unexpected way"),
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

  cdn = scandir(dir, &cdlist, &ilist_select, alphasort);
  if (cdn == -1)
    ohshite(_("cannot scan directory '%.255s'"), dir);

  for (n = 0; n < cdn; n++) {
    cdep = cdlist[n];

    varbuf_reset(&controlfile);
    varbuf_printf(&controlfile, "%s/%s", dir, cdep->d_name);

    if (stat(controlfile.buf, &stab))
      ohshite(_("cannot stat '%.255s' (in '%.255s')"), cdep->d_name, dir);
    if (S_ISREG(stab.st_mode)) {
      cc = fopen(controlfile.buf, "r");
      if (!cc)
        ohshite(_("cannot open '%.255s' (in '%.255s')"), cdep->d_name, dir);
      lines = 0;
      interpreter[0] = '\0';
      if (getc(cc) == '#') {
        if (getc(cc) == '!') {
          while ((c= getc(cc))== ' ');
          p=interpreter; *p++='#'; *p++='!'; il=2;
          while (il < INTERPRETER_MAX && !c_isspace(c) && c != EOF) {
            *p++= c; il++; c= getc(cc);
          }
          *p = '\0';
          if (c=='\n') lines++;
        }
      }
      while ((c= getc(cc))!= EOF) { if (c == '\n') lines++; }
      if (ferror(cc))
        ohshite(_("failed to read '%.255s' (in '%.255s')"), cdep->d_name, dir);
      fclose(cc);
      printf(_(" %7jd bytes, %5d lines   %c  %-20.127s %.127s\n"),
             (intmax_t)stab.st_size, lines,
             (S_IXUSR & stab.st_mode) ? '*' : ' ',
             cdep->d_name, interpreter);
    } else {
      printf(_("     not a plain file          %.255s\n"), cdep->d_name);
    }
    free(cdep);
  }
  free(cdlist);

  varbuf_reset(&controlfile);
  varbuf_printf(&controlfile, "%s/%s", dir, CONTROLFILE);
  cc = fopen(controlfile.buf, "r");
  if (!cc) {
    if (errno != ENOENT)
      ohshite(_("failed to read '%.255s' (in '%.255s')"), CONTROLFILE, dir);
    warning(_("no 'control' file in control archive!"));
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
      ohshite(_("failed to read '%.255s' (in '%.255s')"), CONTROLFILE, dir);
    fclose(cc);
  }

  m_output(stdout, _("<standard output>"));
  varbuf_destroy(&controlfile);
}

static void
info_field(const char *debar, const char *dir, const char *const *fields,
           enum fwriteflags fieldflags)
{
  char *controlfile;
  struct varbuf str = VARBUF_INIT;
  struct pkginfo *pkg;
  int i;

  controlfile = str_fmt("%s/%s", dir, CONTROLFILE);
  parsedb(controlfile, pdb_parse_binary | pdb_ignore_archives, &pkg);
  free(controlfile);

  for (i = 0; fields[i]; i++) {
    const struct fieldinfo *field;
    const struct arbitraryfield *arbfield;

    varbuf_reset(&str);
    field = find_field_info(fieldinfos, fields[i]);
    if (field) {
      field->wcall(&str, pkg, &pkg->available, fieldflags, field);
    } else {
      arbfield = find_arbfield_info(pkg->available.arbs, fields[i]);
      if (arbfield)
        varbuf_add_arbfield(&str, arbfield, fieldflags);
    }
    varbuf_end_str(&str);

    if (fieldflags & fw_printheader)
      printf("%s", str.buf);
    else
      printf("%s\n", str.buf);
  }

  m_output(stdout, _("<standard output>"));

  varbuf_destroy(&str);
}

int
do_showinfo(const char *const *argv)
{
  const char *debar, *dir;
  char *controlfile;
  struct dpkg_error err;
  struct pkginfo *pkg;
  struct pkg_format_node *fmt;

  fmt = pkg_format_parse(showformat, &err);
  if (!fmt)
    ohshit(_("error in show format: %s"), err.str);

  info_prepare(&argv, &debar, &dir, 1);

  controlfile  = str_fmt("%s/%s", dir, CONTROLFILE);
  parsedb(controlfile, pdb_parse_binary | pdb_ignore_archives, &pkg);
  pkg_format_show(fmt, pkg, &pkg->available);
  pkg_format_free(fmt);
  free(controlfile);

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
    info_field(debar, dir, argv, argv[1] != NULL ? fw_printheader : 0);
  } else {
    static const char *const controlonly[] = { CONTROLFILE, NULL };
    info_spew(debar, dir, controlonly);
  }

  return 0;
}

int
do_contents(const char *const *argv)
{
  const char *debar = *argv++;

  if (debar == NULL || *argv)
    badusage(_("--%s takes exactly one argument"), cipaction->olong);
  extracthalf(debar, NULL, DPKG_TAR_LIST, 0);

  return 0;
}
