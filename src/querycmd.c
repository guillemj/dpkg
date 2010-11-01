/*
 * dpkg-query - program for query the dpkg database
 * querycmd.c - status enquiry and listing options
 *
 * Copyright © 1995,1996 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2000,2001 Wichert Akkerman <wakkerma@debian.org>
 * Copyright © 2006-2009 Guillem Jover <guillem@debian.org>
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
#include <sys/ioctl.h>
#include <sys/termios.h>

#if HAVE_LOCALE_H
#include <locale.h>
#endif
#include <string.h>
#include <fcntl.h>
#include <dirent.h>
#include <fnmatch.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/pkg-array.h>
#include <dpkg/pkg-format.h>
#include <dpkg/pkg-show.h>
#include <dpkg/path.h>
#include <dpkg/myopt.h>

#include "filesdb.h"
#include "main.h"

static const char* showformat		= "${Package}\t${Version}\n";

static int getwidth(void) {
  int fd;
  int res;
  struct winsize ws;
  const char* columns;

  if ((columns=getenv("COLUMNS")) && ((res=atoi(columns))>0))
    return res;
  else if (!isatty(1))
    return -1;
  else {
    if ((fd=open("/dev/tty",O_RDONLY))!=-1) {
      if (ioctl(fd, TIOCGWINSZ, &ws)==-1)
	ws.ws_col=80;
      close(fd);
    }
    return ws.ws_col;
  }
}

static void
list1package(struct pkginfo *pkg, bool *head, struct pkg_array *array)
{
  int i,l,w;
  static int nw,vw,dw;
  const char *pdesc;
  static char format[80]   = "";

  if (format[0] == '\0') {
    w=getwidth();
    if (w == -1) {
      nw=14, vw=14, dw=44;
      for (i = 0; i < array->n_pkgs; i++) {
	int plen, vlen, dlen;

	plen = strlen(array->pkgs[i]->name);
	vlen = strlen(versiondescribe(&array->pkgs[i]->installed.version,
	                              vdew_nonambig));
	pkg_summary(array->pkgs[i], &dlen);

	if (plen > nw) nw = plen;
	if (vlen > vw) vw = vlen;
	if (dlen > dw) dw = dlen;
      }
    } else {
      w-=80;
      /* Let's not try to deal with terminals that are too small. */
      if (w < 0)
        w = 0;
      /* Halve that so we can add it to both the name and description. */
      w >>= 2;
      /* Name width. */
      nw = (14 + w);
      /* Version width. */
      vw = (14 + w);
      /* Description width. */
      dw = (44 + (2 * w));
    }
    sprintf(format,"%%c%%c%%c %%-%d.%ds %%-%d.%ds %%.*s\n", nw, nw, vw, vw);
  }

  if (!*head) {
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
    printf(format,'|','|','/', _("Name"), _("Version"), 40, _("Description"));

    /* Status */
    printf("+++-");

   /* Package name. */
    for (l = 0; l < nw; l++)
      printf("=");
    printf("-");

    /* Version. */
    for (l = 0; l < vw; l++)
      printf("=");
    printf("-");

    /* Description. */
    for (l = 0; l < dw; l++)
      printf("=");
    printf("\n");
    *head = true;
  }

  pdesc = pkg_summary(pkg, &l);
  l = min(l, dw);

  printf(format,
         "uihrp"[pkg->want],
         "ncHUFWti"[pkg->status],
         " R"[pkg->eflag],
         pkg->name,
         versiondescribe(&pkg->installed.version, vdew_nonambig),
         l, pdesc);
}

static int
listpackages(const char *const *argv)
{
  struct pkg_array array;
  struct pkginfo *pkg;
  int i;
  int failures = 0;
  bool head;

  modstatdb_init(admindir,msdbrw_readonly);

  pkg_array_init_from_db(&array);
  pkg_array_sort(&array, pkg_sorter_by_name);

  head = false;

  if (!*argv) {
    for (i = 0; i < array.n_pkgs; i++) {
      pkg = array.pkgs[i];
      if (pkg->status == stat_notinstalled) continue;
      list1package(pkg, &head, &array);
    }
  } else {
    int argc, ip, *found;

    for (argc = 0; argv[argc]; argc++);
    found = m_malloc(sizeof(int) * argc);
    memset(found, 0, sizeof(int) * argc);

    for (i = 0; i < array.n_pkgs; i++) {
      pkg = array.pkgs[i];
      for (ip = 0; ip < argc; ip++) {
        if (!fnmatch(argv[ip], pkg->name, 0)) {
          list1package(pkg, &head, &array);
          found[ip]++;
          break;
        }
      }
    }

    /* FIXME: we might get non-matching messages for sub-patterns specified
     * after their super-patterns, due to us skipping on first match. */
    for (ip = 0; ip < argc; ip++) {
      if (!found[ip]) {
        fprintf(stderr, _("No packages found matching %s.\n"), argv[ip]);
        failures++;
      }
    }
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

    if (namenode->divert->pkg) {
      printf(_("diversion by %s from: %s\n"),
             namenode->divert->pkg->name, name_from);
      printf(_("diversion by %s to: %s\n"),
             namenode->divert->pkg->name, name_to);
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
    fputs(pkg_owner->name, stdout);
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
  struct fileiterator *it;
  const char *thisarg;
  int found;
  int failures = 0;
  struct varbuf path = VARBUF_INIT;
  static struct varbuf vb;

  if (!*argv)
    badusage(_("--search needs at least one file name pattern argument"));

  modstatdb_init(admindir,msdbrw_readonly|msdbrw_noavail);
  ensure_allinstfiles_available_quiet();
  ensure_diversions();

  while ((thisarg = *argv++) != NULL) {
    found= 0;

    /* Trim trailing ‘/’ and ‘/.’ from the argument if it's
     * not a pattern, just a path. */
    if (!strpbrk(thisarg, "*[?\\")) {
      varbufreset(&path);
      varbufaddstr(&path, thisarg);
      varbufaddc(&path, '\0');

      varbuf_trunc(&path, path_rtrim_slash_slashdot(path.buf));

      thisarg = path.buf;
    }

    if (!strchr("*[?/",*thisarg)) {
      varbufreset(&vb);
      varbufaddc(&vb,'*');
      varbufaddstr(&vb,thisarg);
      varbufaddc(&vb,'*');
      varbufaddc(&vb,0);
      thisarg= vb.buf;
    }
    if (!strpbrk(thisarg, "*[?\\")) {
      namenode= findnamenode(thisarg, 0);
      found += searchoutput(namenode);
    } else {
      it= iterfilestart();
      while ((namenode = iterfilenext(it)) != NULL) {
        if (fnmatch(thisarg,namenode->name,0)) continue;
        found+= searchoutput(namenode);
      }
      iterfileend(it);
    }
    if (!found) {
      fprintf(stderr, _("%s: no path found matching pattern %s.\n"), thisname,
              thisarg);
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

  if (cipaction->arg==act_listfiles)
    modstatdb_init(admindir,msdbrw_readonly|msdbrw_noavail);
  else
    modstatdb_init(admindir,msdbrw_readonly);

  while ((thisarg = *argv++) != NULL) {
    pkg = pkg_db_find(thisarg);

    switch (cipaction->arg) {
    case act_status:
      if (pkg->status == stat_notinstalled &&
          pkg->priority == pri_unknown &&
          !(pkg->section && *pkg->section) &&
          !pkg->files &&
          pkg->want == want_unknown &&
          !pkg_is_informative(pkg, &pkg->installed)) {
        fprintf(stderr,_("Package `%s' is not installed and no info is available.\n"),pkg->name);
        failures++;
      } else {
        writerecord(stdout, _("<standard output>"), pkg, &pkg->installed);
      }
      break;
    case act_printavail:
      if (!pkg_is_informative(pkg, &pkg->available)) {
        fprintf(stderr,_("Package `%s' is not available.\n"),pkg->name);
        failures++;
      } else {
        writerecord(stdout, _("<standard output>"), pkg, &pkg->available);
      }
      break;
    case act_listfiles:
      switch (pkg->status) {
      case stat_notinstalled:
        fprintf(stderr,_("Package `%s' is not installed.\n"),pkg->name);
        failures++;
        break;
      default:
        ensure_packagefiles_available(pkg);
        ensure_diversions();
        file= pkg->clientdata->files;
        if (!file) {
          printf(_("Package `%s' does not contain any files (!)\n"),pkg->name);
        } else {
          while (file) {
            namenode= file->namenode;
            puts(namenode->name);
            if (namenode->divert && !namenode->divert->camefrom) {
              if (!namenode->divert->pkg)
		printf(_("locally diverted to: %s\n"),
		       namenode->divert->useinstead->name);
              else if (pkg == namenode->divert->pkg)
		printf(_("package diverts others to: %s\n"),
		       namenode->divert->useinstead->name);
              else
		printf(_("diverted by %s to: %s\n"),
		       namenode->divert->pkg->name,
		       namenode->divert->useinstead->name);
            }
            file= file->next;
          }
        }
        break;
      }
      break;
    default:
      internerr("unknown action '%d'", cipaction->arg);
    }

    if (*(argv + 1) == NULL)
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

static int
showpackages(const char *const *argv)
{
  struct pkg_array array;
  struct pkginfo *pkg;
  struct pkg_format_node *fmt = pkg_format_parse(showformat);
  int i;
  int failures = 0;

  if (!fmt) {
    failures++;
    return failures;
  }

  modstatdb_init(admindir,msdbrw_readonly);

  pkg_array_init_from_db(&array);
  pkg_array_sort(&array, pkg_sorter_by_name);

  if (!*argv) {
    for (i = 0; i < array.n_pkgs; i++) {
      pkg = array.pkgs[i];
      if (pkg->status == stat_notinstalled) continue;
      pkg_format_show(fmt, pkg, &pkg->installed);
    }
  } else {
    int argc, ip, *found;

    for (argc = 0; argv[argc]; argc++);
    found = m_malloc(sizeof(int) * argc);
    memset(found, 0, sizeof(int) * argc);

    for (i = 0; i < array.n_pkgs; i++) {
      pkg = array.pkgs[i];
      for (ip = 0; ip < argc; ip++) {
        if (!fnmatch(argv[ip], pkg->name, 0)) {
          pkg_format_show(fmt, pkg, &pkg->installed);
          found[ip]++;
          break;
        }
      }
    }

    /* FIXME: we might get non-matching messages for sub-patterns specified
     * after their super-patterns, due to us skipping on first match. */
    for (ip = 0; ip < argc; ip++) {
      if (!found[ip]) {
        fprintf(stderr, _("No packages found matching %s.\n"), argv[ip]);
        failures++;
      }
    }
  }

  m_output(stdout, _("<standard output>"));
  m_output(stderr, _("<standard error>"));

  pkg_array_destroy(&array);
  pkg_format_free(fmt);
  modstatdb_shutdown();

  return failures;
}

static void
control_path_file(struct pkginfo *pkg, const char *control_file)
{
  const char *control_path;
  struct stat st;

  /* Do not expose internal database files. */
  if (strcmp(control_file, LISTFILE) == 0 ||
      strcmp(control_file, CONFFILESFILE) == 0)
    return;

  control_path = pkgadminfile(pkg, control_file);

  if (stat(control_path, &st) < 0)
    return;

  if (!S_ISREG(st.st_mode))
    return;

  printf("%s\n", control_path);
}

static void
control_path_pkg(struct pkginfo *pkg)
{
  DIR *db_dir;
  struct dirent *db_de;
  struct varbuf db_path;
  size_t db_path_len;

  varbufinit(&db_path, 0);
  varbufaddstr(&db_path, pkgadmindir());
  db_path_len = db_path.used;
  varbufaddc(&db_path, '\0');

  db_dir = opendir(db_path.buf);
  if (!db_dir)
    ohshite(_("cannot read info directory"));

  push_cleanup(cu_closedir, ~0, NULL, 0, 1, (void *)db_dir);
  while ((db_de = readdir(db_dir)) != NULL) {
    const char *p;

    /* Ignore dotfiles, including ‘.’ and ‘..’. */
    if (db_de->d_name[0] == '.')
      continue;

    /* Ignore anything odd. */
    p = strrchr(db_de->d_name, '.');
    if (!p)
      continue;

    /* Ignore files from other packages. */
    if (strlen(pkg->name) != (size_t)(p - db_de->d_name) ||
        strncmp(db_de->d_name, pkg->name, p - db_de->d_name))
      continue;

    /* Skip past the full stop. */
    p++;

    /* Do not expose internal database files. */
    if (strcmp(p, LISTFILE) == 0 ||
        strcmp(p, CONFFILESFILE) == 0)
      continue;

    if (strlen(p) > MAXCONTROLFILENAME)
      continue;

    varbuf_trunc(&db_path, db_path_len);
    varbufaddstr(&db_path, db_de->d_name);
    varbufaddc(&db_path, '\0');

    printf("%s\n", db_path.buf);
  }
  pop_cleanup(ehflag_normaltidy); /* closedir */

  varbuf_destroy(&db_path);
}

static int
control_path(const char *const *argv)
{
  struct pkginfo *pkg;
  const char *pkg_name;
  const char *control_file;

  pkg_name = *argv++;
  if (!pkg_name)
    badusage(_("--%s needs at least one package name argument"),
             cipaction->olong);

  control_file = *argv++;
  if (control_file && *argv)
    badusage(_("--%s takes at most two arguments"), cipaction->olong);

  /* Validate control file name for sanity. */
  if (control_file) {
    const char *c;

    for (c = "/."; *c; c++)
      if (strchr(control_file, *c))
        badusage(_("control file contains %c"), *c);
  }

  modstatdb_init(admindir, msdbrw_readonly | msdbrw_noavail);

  pkg = pkg_db_find(pkg_name);
  if (pkg->status == stat_notinstalled)
    badusage(_("Package `%s' is not installed.\n"), pkg->name);

  if (control_file)
    control_path_file(pkg, control_file);
  else
    control_path_pkg(pkg);

  modstatdb_shutdown();

  return 0;
}

static void DPKG_ATTR_NORET
printversion(const struct cmdinfo *ci, const char *value)
{
  printf(_("Debian %s package management program query tool version %s.\n"),
         DPKGQUERY, DPKG_VERSION_ARCH);
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
"  -L|--listfiles <package> ...     List files `owned' by package(s).\n"
"  -l|--list [<pattern> ...]        List packages concisely.\n"
"  -W|--show <pattern> ...          Show information on package(s).\n"
"  -S|--search <pattern> ...        Find package(s) owning file(s).\n"
"  -c|--control-path <package> [<file>]\n"
"                                   Print path for package control file.\n"
"\n"));

  printf(_(
"  -h|--help                        Show this help message.\n"
"  --version                        Show the version.\n"
"\n"));

  printf(_(
"Options:\n"
"  --admindir=<directory>           Use <directory> instead of %s.\n"
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

const char thisname[]= "dpkg-query";
const char printforhelp[]= N_("Use --help for help about querying packages.");

const char *admindir= ADMINDIR;

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

  { "admindir",   0,   1, NULL, &admindir,   NULL          },
  { "showformat", 'f', 1, NULL, &showformat, NULL          },
  { "help",       'h', 0, NULL, NULL,        usage         },
  { "version",    0,   0, NULL, NULL,        printversion  },
  {  NULL,        0,   0, NULL, NULL,        NULL          }
};

int main(int argc, const char *const *argv) {
  int (*actionfunction)(const char *const *argv);
  int ret;

  setlocale(LC_ALL, "");
  bindtextdomain(PACKAGE, LOCALEDIR);
  textdomain(PACKAGE);

  standard_startup();
  myopt(&argv, cmdinfos);

  if (!cipaction) badusage(_("need an action option"));

  setvbuf(stdout, NULL, _IONBF, 0);
  filesdbinit();

  actionfunction = (int (*)(const char *const *))cipaction->farg;

  ret = actionfunction(argv);

  standard_shutdown();

  return !!ret;
}
