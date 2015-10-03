/*
 * dpkg-query - program for query the dpkg database
 * querycmd.c - status enquiry and listing options
 *
 * Copyright © 1995,1996 Ian Jackson <ijackson@chiark.greenend.org.uk>
 * Copyright © 2000,2001 Wichert Akkerman <wakkerma@debian.org>
 * Copyright © 2006-2015 Guillem Jover <guillem@debian.org>
 * Copyright © 2011 Linaro Limited
 * Copyright © 2011 Raphaël Hertzog <hertzog@debian.org>
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
#include <sys/ioctl.h>

#if HAVE_LOCALE_H
#include <locale.h>
#endif
#include <string.h>
#include <fcntl.h>
#include <dirent.h>
#include <fnmatch.h>
#include <termios.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/pkg-array.h>
#include <dpkg/pkg-spec.h>
#include <dpkg/pkg-format.h>
#include <dpkg/pkg-show.h>
#include <dpkg/string.h>
#include <dpkg/path.h>
#include <dpkg/file.h>
#include <dpkg/options.h>

#include "filesdb.h"
#include "infodb.h"
#include "main.h"

static const char *showformat = "${binary:Package}\t${Version}\n";

static int opt_loadavail = 0;

static int getwidth(void) {
  int fd;
  int res;
  struct winsize ws;
  const char *columns;

  columns = getenv("COLUMNS");
  if (columns) {
    res = atoi(columns);
    if (res > 0)
      return res;
  }

  if (!isatty(1))
    return -1;
  else {
    res = 80;

    fd = open("/dev/tty", O_RDONLY);
    if (fd != -1) {
      if (ioctl(fd, TIOCGWINSZ, &ws) == 0)
        res = ws.ws_col;
      close(fd);
    }

    return res;
  }
}

struct list_format {
  bool head;
  int nw;
  int vw;
  int aw;
  int dw;
};

static void
list_format_init(struct list_format *fmt, struct pkg_array *array)
{
  int w;

  if (fmt->nw != 0)
    return;

  w = getwidth();
  if (w == -1) {
    int i;

    fmt->nw = 14;
    fmt->vw = 12;
    fmt->aw = 12;
    fmt->dw = 33;

    for (i = 0; i < array->n_pkgs; i++) {
      int plen, vlen, alen, dlen;

      if (array->pkgs[i] == NULL)
        continue;

      plen = str_width(pkg_name(array->pkgs[i], pnaw_nonambig));
      vlen = str_width(versiondescribe(&array->pkgs[i]->installed.version,
                                       vdew_nonambig));
      alen = str_width(dpkg_arch_describe(array->pkgs[i]->installed.arch));
      pkg_summary(array->pkgs[i], &array->pkgs[i]->installed, &dlen);

      if (plen > fmt->nw)
        fmt->nw = plen;
      if (vlen > fmt->vw)
        fmt->vw = vlen;
      if (alen > fmt->aw)
        fmt->aw = alen;
      if (dlen > fmt->dw)
        fmt->dw = dlen;
    }
  } else {
    w -= 80;
    /* Let's not try to deal with terminals that are too small. */
    if (w < 0)
      w = 0;
    /* Halve that so we can add it to both the name and description. */
    w >>= 1;
    /* Name width. */
    fmt->nw = (14 + (w / 2));
    /* Version width. */
    fmt->vw = (12 + (w / 4));
    /* Architecture width. */
    fmt->aw = (12 + (w / 4));
    /* Description width. */
    fmt->dw = (33 + w);
  }
}

static void
list_format_print(struct list_format *fmt,
                  int c_want, int c_status, int c_eflag,
                  const char *name, const char *version, const char *arch,
                  const char *desc, int desc_len)
{
  struct str_crop_info ns, vs, as, ds;

  str_gen_crop(name, fmt->nw, &ns);
  str_gen_crop(version, fmt->vw, &vs);
  str_gen_crop(arch, fmt->aw, &as);
  str_gen_crop(desc, desc_len, &ds);

  printf("%c%c%c %-*.*s %-*.*s %-*.*s %.*s\n", c_want, c_status, c_eflag,
         ns.max_bytes, ns.str_bytes, name,
         vs.max_bytes, vs.str_bytes, version,
         as.max_bytes, as.str_bytes, arch,
         ds.str_bytes, desc);
}

static void
list_format_print_header(struct list_format *fmt)
{
  int l;

  if (fmt->head)
    return;

  /* TRANSLATORS: This is the header that appears on 'dpkg-query -l'. The
   * string should remain under 80 characters. The uppercase letters in
   * the state values denote the abbreviated letter that will appear on
   * the first three columns, which should ideally match the English one
   * (e.g. Remove → supRimeix), see dpkg-query(1) for further details. The
   * translated message can use additional lines if needed. */
  fputs(_("\
Desired=Unknown/Install/Remove/Purge/Hold\n\
| Status=Not/Inst/Conf-files/Unpacked/halF-conf/Half-inst/trig-aWait/Trig-pend\n\
|/ Err?=(none)/Reinst-required (Status,Err: uppercase=bad)\n"), stdout);
  list_format_print(fmt, '|', '|', '/', _("Name"), _("Version"),
                    _("Architecture"), _("Description"), fmt->dw);

  /* Status */
  printf("+++-");

 /* Package name. */
  for (l = 0; l < fmt->nw; l++)
    printf("=");
  printf("-");

  /* Version. */
  for (l = 0; l < fmt->vw; l++)
    printf("=");
  printf("-");

  /* Architecture. */
  for (l = 0; l < fmt->aw; l++)
    printf("=");
  printf("-");

  /* Description. */
  for (l = 0; l < fmt->dw; l++)
    printf("=");
  printf("\n");

  fmt->head = true;
}

static void
pkg_array_list_item(struct pkg_array *array, struct pkginfo *pkg, void *pkg_data)
{
  struct list_format *fmt = pkg_data;
  int l;
  const char *pdesc;

  list_format_init(fmt, array);
  list_format_print_header(fmt);

  pdesc = pkg_summary(pkg, &pkg->installed, &l);
  l = min(l, fmt->dw);

  list_format_print(fmt,
                    pkg_abbrev_want(pkg),
                    pkg_abbrev_status(pkg),
                    pkg_abbrev_eflag(pkg),
                    pkg_name(pkg, pnaw_nonambig),
                    versiondescribe(&pkg->installed.version, vdew_nonambig),
                    dpkg_arch_describe(pkg->installed.arch),
                    pdesc, l);
}

static int
listpackages(const char *const *argv)
{
  struct pkg_array array;
  struct pkginfo *pkg;
  int i;
  int failures = 0;
  struct list_format fmt;

  if (!opt_loadavail)
    modstatdb_open(msdbrw_readonly);
  else
    modstatdb_open(msdbrw_readonly | msdbrw_available_readonly);

  pkg_array_init_from_db(&array);
  pkg_array_sort(&array, pkg_sorter_by_nonambig_name_arch);

  memset(&fmt, 0, sizeof(fmt));

  if (!*argv) {
    for (i = 0; i < array.n_pkgs; i++) {
      pkg = array.pkgs[i];
      if (pkg->status == PKG_STAT_NOTINSTALLED)
        array.pkgs[i] = NULL;
    }

    pkg_array_foreach(&array, pkg_array_list_item, &fmt);
  } else {
    int argc, ip, *found;
    struct pkg_spec *ps;

    for (argc = 0; argv[argc]; argc++);
    found = m_calloc(argc, sizeof(int));

    ps = m_malloc(sizeof(*ps) * argc);
    for (ip = 0; ip < argc; ip++) {
      pkg_spec_init(&ps[ip], PKG_SPEC_PATTERNS | PKG_SPEC_ARCH_WILDCARD);
      pkg_spec_parse(&ps[ip], argv[ip]);
    }

    for (i = 0; i < array.n_pkgs; i++) {
      bool pkg_found = false;

      pkg = array.pkgs[i];
      for (ip = 0; ip < argc; ip++) {
        if (pkg_spec_match_pkg(&ps[ip], pkg, &pkg->installed)) {
          pkg_found = true;
          found[ip]++;
        }
      }
      if (!pkg_found)
        array.pkgs[i] = NULL;
    }

    pkg_array_foreach(&array, pkg_array_list_item, &fmt);

    for (ip = 0; ip < argc; ip++) {
      if (!found[ip]) {
        notice(_("no packages found matching %s"), argv[ip]);
        failures++;
      }
      pkg_spec_destroy(&ps[ip]);
    }

    free(ps);
    free(found);
  }

  m_output(stdout, _("<standard output>"));
  m_output(stderr, _("<standard error>"));

  pkg_array_destroy(&array);
  modstatdb_shutdown();

  return failures;
}

static int searchoutput(struct filenamenode *namenode) {
  struct filepackages_iterator *iter;
  struct pkginfo *pkg_owner;
  int found;

  if (namenode->divert) {
    const char *name_from = namenode->divert->camefrom ?
                            namenode->divert->camefrom->name : namenode->name;
    const char *name_to = namenode->divert->useinstead ?
                          namenode->divert->useinstead->name : namenode->name;

    if (namenode->divert->pkgset) {
      printf(_("diversion by %s from: %s\n"),
             namenode->divert->pkgset->name, name_from);
      printf(_("diversion by %s to: %s\n"),
             namenode->divert->pkgset->name, name_to);
    } else {
      printf(_("local diversion from: %s\n"), name_from);
      printf(_("local diversion to: %s\n"), name_to);
    }
  }
  found= 0;

  iter = filepackages_iter_new(namenode);
  while ((pkg_owner = filepackages_iter_next(iter))) {
    if (found)
      fputs(", ", stdout);
    fputs(pkg_name(pkg_owner, pnaw_nonambig), stdout);
    found++;
  }
  filepackages_iter_free(iter);

  if (found) printf(": %s\n",namenode->name);
  return found + (namenode->divert ? 1 : 0);
}

static int
searchfiles(const char *const *argv)
{
  struct filenamenode *namenode;
  struct fileiterator *iter;
  const char *thisarg;
  int found;
  int failures = 0;
  struct varbuf path = VARBUF_INIT;
  static struct varbuf vb;

  if (!*argv)
    badusage(_("--search needs at least one file name pattern argument"));

  modstatdb_open(msdbrw_readonly);
  ensure_allinstfiles_available_quiet();
  ensure_diversions();

  while ((thisarg = *argv++) != NULL) {
    found= 0;

    if (!strchr("*[?/",*thisarg)) {
      varbuf_reset(&vb);
      varbuf_add_char(&vb, '*');
      varbuf_add_str(&vb, thisarg);
      varbuf_add_char(&vb, '*');
      varbuf_end_str(&vb);
      thisarg= vb.buf;
    }
    if (!strpbrk(thisarg, "*[?\\")) {
      /* Trim trailing ‘/’ and ‘/.’ from the argument if it is not
       * a pattern, just a pathname. */
      varbuf_reset(&path);
      varbuf_add_str(&path, thisarg);
      varbuf_end_str(&path);
      varbuf_trunc(&path, path_trim_slash_slashdot(path.buf));

      namenode = findnamenode(path.buf, 0);
      found += searchoutput(namenode);
    } else {
      iter = files_db_iter_new();
      while ((namenode = files_db_iter_next(iter)) != NULL) {
        if (fnmatch(thisarg,namenode->name,0)) continue;
        found+= searchoutput(namenode);
      }
      files_db_iter_free(iter);
    }
    if (!found) {
      notice(_("no path found matching pattern %s"), thisarg);
      failures++;
      m_output(stderr, _("<standard error>"));
    } else {
      m_output(stdout, _("<standard output>"));
    }
  }
  modstatdb_shutdown();

  varbuf_destroy(&path);

  return failures;
}

static int
enqperpackage(const char *const *argv)
{
  const char *thisarg;
  struct fileinlist *file;
  struct pkginfo *pkg;
  struct filenamenode *namenode;
  int failures = 0;

  if (!*argv)
    badusage(_("--%s needs at least one package name argument"), cipaction->olong);

  if (cipaction->arg_int == act_printavail)
    modstatdb_open(msdbrw_readonly | msdbrw_available_readonly);
  else
    modstatdb_open(msdbrw_readonly);

  while ((thisarg = *argv++) != NULL) {
    pkg = dpkg_options_parse_pkgname(cipaction, thisarg);

    switch (cipaction->arg_int) {
    case act_status:
      if (pkg->status == PKG_STAT_NOTINSTALLED &&
          pkg->priority == PKG_PRIO_UNKNOWN &&
          str_is_unset(pkg->section) &&
          !pkg->files &&
          pkg->want == PKG_WANT_UNKNOWN &&
          !pkg_is_informative(pkg, &pkg->installed)) {
        notice(_("package '%s' is not installed and no information is available"),
               pkg_name(pkg, pnaw_nonambig));
        failures++;
      } else {
        writerecord(stdout, _("<standard output>"), pkg, &pkg->installed);
      }
      break;
    case act_printavail:
      if (!pkg_is_informative(pkg, &pkg->available)) {
        notice(_("package '%s' is not available"),
               pkgbin_name(pkg, &pkg->available, pnaw_nonambig));
        failures++;
      } else {
        writerecord(stdout, _("<standard output>"), pkg, &pkg->available);
      }
      break;
    case act_listfiles:
      switch (pkg->status) {
      case PKG_STAT_NOTINSTALLED:
        notice(_("package '%s' is not installed"),
               pkg_name(pkg, pnaw_nonambig));
        failures++;
        break;
      default:
        ensure_packagefiles_available(pkg);
        ensure_diversions();
        file= pkg->clientdata->files;
        if (!file) {
          printf(_("Package '%s' does not contain any files (!)\n"),
                 pkg_name(pkg, pnaw_nonambig));
        } else {
          while (file) {
            namenode= file->namenode;
            puts(namenode->name);
            if (namenode->divert && !namenode->divert->camefrom) {
              if (!namenode->divert->pkgset)
		printf(_("locally diverted to: %s\n"),
		       namenode->divert->useinstead->name);
              else if (pkg->set == namenode->divert->pkgset)
		printf(_("package diverts others to: %s\n"),
		       namenode->divert->useinstead->name);
              else
		printf(_("diverted by %s to: %s\n"),
		       namenode->divert->pkgset->name,
		       namenode->divert->useinstead->name);
            }
            file= file->next;
          }
        }
        break;
      }
      break;
    default:
      internerr("unknown action '%d'", cipaction->arg_int);
    }

    if (*argv != NULL)
      putchar('\n');

    m_output(stdout, _("<standard output>"));
  }

  if (failures) {
    fputs(_("Use dpkg --info (= dpkg-deb --info) to examine archive files,\n"
         "and dpkg --contents (= dpkg-deb --contents) to list their contents.\n"),stderr);
    m_output(stderr, _("<standard error>"));
  }
  modstatdb_shutdown();

  return failures;
}

static void
pkg_array_show_item(struct pkg_array *array, struct pkginfo *pkg, void *pkg_data)
{
  struct pkg_format_node *fmt = pkg_data;

  pkg_format_show(fmt, pkg, &pkg->installed);
}

static int
showpackages(const char *const *argv)
{
  struct dpkg_error err;
  struct pkg_array array;
  struct pkginfo *pkg;
  struct pkg_format_node *fmt;
  int i;
  int failures = 0;

  fmt = pkg_format_parse(showformat, &err);
  if (!fmt) {
    notice(_("error in show format: %s"), err.str);
    dpkg_error_destroy(&err);
    failures++;
    return failures;
  }

  if (!opt_loadavail)
    modstatdb_open(msdbrw_readonly);
  else
    modstatdb_open(msdbrw_readonly | msdbrw_available_readonly);

  pkg_array_init_from_db(&array);
  pkg_array_sort(&array, pkg_sorter_by_nonambig_name_arch);

  if (!*argv) {
    for (i = 0; i < array.n_pkgs; i++) {
      pkg = array.pkgs[i];
      if (pkg->status == PKG_STAT_NOTINSTALLED)
        continue;
      pkg_format_show(fmt, pkg, &pkg->installed);
    }
  } else {
    int argc, ip, *found;
    struct pkg_spec *ps;

    for (argc = 0; argv[argc]; argc++);
    found = m_calloc(argc, sizeof(int));

    ps = m_malloc(sizeof(*ps) * argc);
    for (ip = 0; ip < argc; ip++) {
      pkg_spec_init(&ps[ip], PKG_SPEC_PATTERNS | PKG_SPEC_ARCH_WILDCARD);
      pkg_spec_parse(&ps[ip], argv[ip]);
    }

    for (i = 0; i < array.n_pkgs; i++) {
      bool pkg_found = false;

      pkg = array.pkgs[i];
      for (ip = 0; ip < argc; ip++) {
        if (pkg_spec_match_pkg(&ps[ip], pkg, &pkg->installed)) {
          pkg_found = true;
          found[ip]++;
        }
      }
      if (!pkg_found)
        array.pkgs[i] = NULL;
    }

    pkg_array_foreach(&array, pkg_array_show_item, fmt);

    for (ip = 0; ip < argc; ip++) {
      if (!found[ip]) {
        notice(_("no packages found matching %s"), argv[ip]);
        failures++;
      }
      pkg_spec_destroy(&ps[ip]);
    }

    free(ps);
    free(found);
  }

  m_output(stdout, _("<standard output>"));
  m_output(stderr, _("<standard error>"));

  pkg_array_destroy(&array);
  pkg_format_free(fmt);
  modstatdb_shutdown();

  return failures;
}

static bool
pkg_infodb_is_internal(const char *filetype)
{
  /* Do not expose internal database files. */
  if (strcmp(filetype, LISTFILE) == 0 ||
      strcmp(filetype, CONFFILESFILE) == 0)
    return true;

  if (strlen(filetype) > MAXCONTROLFILENAME)
    return true;

  return false;
}

static void
pkg_infodb_check_filetype(const char *filetype)
{
  const char *c;

  /* Validate control file name for sanity. */
  for (c = "/."; *c; c++)
    if (strchr(filetype, *c))
      badusage(_("control file contains %c"), *c);
}

static void
pkg_infodb_print_filename(const char *filename, const char *filetype)
{
  if (pkg_infodb_is_internal(filetype))
    return;

  printf("%s\n", filename);
}

static void
pkg_infodb_print_filetype(const char *filename, const char *filetype)
{
  if (pkg_infodb_is_internal(filetype))
    return;

  printf("%s\n", filetype);
}

static void
control_path_file(struct pkginfo *pkg, const char *control_file)
{
  const char *control_path;
  struct stat st;

  control_path = pkg_infodb_get_file(pkg, &pkg->installed, control_file);
  if (stat(control_path, &st) < 0)
    return;
  if (!S_ISREG(st.st_mode))
    return;

  pkg_infodb_print_filename(control_path, control_file);
}

static int
control_path(const char *const *argv)
{
  struct pkginfo *pkg;
  const char *pkgname;
  const char *control_file;

  pkgname = *argv++;
  if (!pkgname)
    badusage(_("--%s needs at least one package name argument"),
             cipaction->olong);

  control_file = *argv++;
  if (control_file && *argv)
    badusage(_("--%s takes at most two arguments"), cipaction->olong);

  if (control_file)
    pkg_infodb_check_filetype(control_file);

  modstatdb_open(msdbrw_readonly);

  pkg = dpkg_options_parse_pkgname(cipaction, pkgname);
  if (pkg->status == PKG_STAT_NOTINSTALLED)
    ohshit(_("package '%s' is not installed"),
           pkg_name(pkg, pnaw_nonambig));

  if (control_file)
    control_path_file(pkg, control_file);
  else
    pkg_infodb_foreach(pkg, &pkg->installed, pkg_infodb_print_filename);

  modstatdb_shutdown();

  return 0;
}

static int
control_list(const char *const *argv)
{
  struct pkginfo *pkg;
  const char *pkgname;

  pkgname = *argv++;
  if (!pkgname || *argv)
    badusage(_("--%s takes one package name argument"), cipaction->olong);

  modstatdb_open(msdbrw_readonly);

  pkg = dpkg_options_parse_pkgname(cipaction, pkgname);
  if (pkg->status == PKG_STAT_NOTINSTALLED)
    ohshit(_("package '%s' is not installed"), pkg_name(pkg, pnaw_nonambig));

  pkg_infodb_foreach(pkg, &pkg->installed, pkg_infodb_print_filetype);

  modstatdb_shutdown();

  return 0;
}

static int
control_show(const char *const *argv)
{
  struct pkginfo *pkg;
  const char *pkgname;
  const char *filename;
  const char *control_file;

  pkgname = *argv++;
  if (!pkgname || !*argv)
    badusage(_("--%s takes exactly two arguments"),
             cipaction->olong);

  control_file = *argv++;
  if (!control_file || *argv)
    badusage(_("--%s takes exactly two arguments"), cipaction->olong);

  pkg_infodb_check_filetype(control_file);

  modstatdb_open(msdbrw_readonly);

  pkg = dpkg_options_parse_pkgname(cipaction, pkgname);
  if (pkg->status == PKG_STAT_NOTINSTALLED)
    ohshit(_("package '%s' is not installed"), pkg_name(pkg, pnaw_nonambig));

  if (pkg_infodb_has_file(pkg, &pkg->installed, control_file))
    filename = pkg_infodb_get_file(pkg, &pkg->installed, control_file);
  else
    ohshit(_("control file '%s' does not exist"), control_file);

  modstatdb_shutdown();

  file_show(filename);

  return 0;
}

static void DPKG_ATTR_NORET
printversion(const struct cmdinfo *ci, const char *value)
{
  printf(_("Debian %s package management program query tool version %s.\n"),
         DPKGQUERY, PACKAGE_RELEASE);
  printf(_(
"This is free software; see the GNU General Public License version 2 or\n"
"later for copying conditions. There is NO warranty.\n"));

  m_output(stdout, _("<standard output>"));

  exit(0);
}

static void DPKG_ATTR_NORET
usage(const struct cmdinfo *ci, const char *value)
{
  printf(_(
"Usage: %s [<option> ...] <command>\n"
"\n"), DPKGQUERY);

  printf(_(
"Commands:\n"
"  -s|--status <package> ...        Display package status details.\n"
"  -p|--print-avail <package> ...   Display available version details.\n"
"  -L|--listfiles <package> ...     List files 'owned' by package(s).\n"
"  -l|--list [<pattern> ...]        List packages concisely.\n"
"  -W|--show [<pattern> ...]        Show information on package(s).\n"
"  -S|--search <pattern> ...        Find package(s) owning file(s).\n"
"     --control-list <package>      Print the package control file list.\n"
"     --control-show <package> <file>\n"
"                                   Show the package control file.\n"
"  -c|--control-path <package> [<file>]\n"
"                                   Print path for package control file.\n"
"\n"));

  printf(_(
"  -?, --help                       Show this help message.\n"
"      --version                    Show the version.\n"
"\n"));

  printf(_(
"Options:\n"
"  --admindir=<directory>           Use <directory> instead of %s.\n"
"  --load-avail                     Use available file on --show and --list.\n"
"  -f|--showformat=<format>         Use alternative format for --show.\n"
"\n"), ADMINDIR);

  printf(_(
"Format syntax:\n"
"  A format is a string that will be output for each package. The format\n"
"  can include the standard escape sequences \\n (newline), \\r (carriage\n"
"  return) or \\\\ (plain backslash). Package information can be included\n"
"  by inserting variable references to package fields using the ${var[;width]}\n"
"  syntax. Fields will be right-aligned unless the width is negative in which\n"
"  case left alignment will be used.\n"));

  m_output(stdout, _("<standard output>"));

  exit(0);
}

static const char printforhelp[] = N_(
"Use --help for help about querying packages.");

static const char *admindir;

/* This table has both the action entries in it and the normal options.
 * The action entries are made with the ACTION macro, as they all
 * have a very similar structure. */
static const struct cmdinfo cmdinfos[]= {
  ACTION( "listfiles",                      'L', act_listfiles,     enqperpackage   ),
  ACTION( "status",                         's', act_status,        enqperpackage   ),
  ACTION( "print-avail",                    'p', act_printavail,    enqperpackage   ),
  ACTION( "list",                           'l', act_listpackages,  listpackages    ),
  ACTION( "search",                         'S', act_searchfiles,   searchfiles     ),
  ACTION( "show",                           'W', act_listpackages,  showpackages    ),
  ACTION( "control-path",                   'c', act_controlpath,   control_path    ),
  ACTION( "control-list",                    0,  act_controllist,   control_list    ),
  ACTION( "control-show",                    0,  act_controlshow,   control_show    ),

  { "admindir",   0,   1, NULL, &admindir,   NULL          },
  { "load-avail", 0,   0, &opt_loadavail, NULL, NULL, 1    },
  { "showformat", 'f', 1, NULL, &showformat, NULL          },
  { "help",       '?', 0, NULL, NULL,        usage         },
  { "version",    0,   0, NULL, NULL,        printversion  },
  {  NULL,        0,   0, NULL, NULL,        NULL          }
};

int main(int argc, const char *const *argv) {
  int ret;

  dpkg_set_report_piped_mode(_IOFBF);
  dpkg_locales_init(PACKAGE);
  dpkg_program_init("dpkg-query");
  dpkg_options_parse(&argv, cmdinfos, printforhelp);

  admindir = dpkg_db_set_dir(admindir);

  if (!cipaction) badusage(_("need an action option"));

  filesdbinit();

  ret = cipaction->action(argv);

  dpkg_program_done();

  return !!ret;
}
