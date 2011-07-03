/*
 * dpkg-deb - construction and deconstruction of *.deb archives
 * main.c - main program
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
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

#include <assert.h>
#include <limits.h>
#if HAVE_LOCALE_H
#include <locale.h>
#endif
#include <ctype.h>
#include <string.h>
#include <dirent.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/macros.h>
#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/compress.h>
#include <dpkg/options.h>

#include "dpkg-deb.h"

const char* showformat	= "${Package}\t${Version}\n";

static void DPKG_ATTR_NORET
printversion(const struct cmdinfo *cip, const char *value)
{
  printf(_("Debian `%s' package archive backend version %s.\n"),
         BACKEND, DPKG_VERSION_ARCH);
  printf(_(
"This is free software; see the GNU General Public License version 2 or\n"
"later for copying conditions. There is NO warranty.\n"));

  m_output(stdout, _("<standard output>"));

  exit(0);
}

static void DPKG_ATTR_NORET
usage(const struct cmdinfo *cip, const char *value)
{
  printf(_(
"Usage: %s [<option> ...] <command>\n"
"\n"), BACKEND);

  printf(_(
"Commands:\n"
"  -b|--build <directory> [<deb>]   Build an archive.\n"
"  -c|--contents <deb>              List contents.\n"
"  -I|--info <deb> [<cfile> ...]    Show info to stdout.\n"
"  -W|--show <deb>                  Show information on package(s)\n"
"  -f|--field <deb> [<cfield> ...]  Show field(s) to stdout.\n"
"  -e|--control <deb> [<directory>] Extract control info.\n"
"  -x|--extract <deb> <directory>   Extract files.\n"
"  -X|--vextract <deb> <directory>  Extract & list files.\n"
"  --fsys-tarfile <deb>             Output filesystem tarfile.\n"
"\n"));

  printf(_(
"  -h|--help                        Show this help message.\n"
"  --version                        Show the version.\n"
"\n"));

  printf(_(
"<deb> is the filename of a Debian format archive.\n"
"<cfile> is the name of an administrative file component.\n"
"<cfield> is the name of a field in the main `control' file.\n"
"\n"));

  printf(_(
"Options:\n"
"  --showformat=<format>            Use alternative format for --show.\n"
"  -D                               Enable debugging output.\n"
"  --old, --new                     Select archive format.\n"
"  --nocheck                        Suppress control file check (build bad\n"
"                                     packages).\n"
"  -z#                              Set the compression level when building.\n"
"  -Z<type>                         Set the compression type used when building.\n"
"                                     Allowed types: gzip, xz, bzip2, lzma, none.\n"
"\n"));

  printf(_(
"Format syntax:\n"
"  A format is a string that will be output for each package. The format\n"
"  can include the standard escape sequences \\n (newline), \\r (carriage\n"
"  return) or \\\\ (plain backslash). Package information can be included\n"
"  by inserting variable references to package fields using the ${var[;width]}\n"
"  syntax. Fields will be right-aligned unless the width is negative in which\n"
"  case left alignment will be used.\n"));

  printf(_(
"\n"
"Use `dpkg' to install and remove packages from your system, or\n"
"`dselect' or `aptitude' for user-friendly package management.  Packages\n"
"unpacked using `dpkg-deb --extract' will be incorrectly installed !\n"));

  m_output(stdout, _("<standard output>"));

  exit(0);
}

static const char printforhelp[] =
  N_("Type dpkg-deb --help for help about manipulating *.deb files;\n"
     "Type dpkg --help for help about installing and deinstalling packages.");

int debugflag=0, nocheckflag=0, oldformatflag=BUILDOLDPKGFORMAT;
struct compressor *compressor = &compressor_gzip;
int compress_level = -1;

static void
set_compress_level(const struct cmdinfo *cip, const char *value)
{
  long level;
  char *end;

  level = strtol(value, &end, 0);
  if (value == end || *end || level > INT_MAX)
    badusage(_("invalid integer for -%c: '%.250s'"), cip->oshort, value);

  if (level < 0 || level > 9)
    badusage(_("invalid compression level for -%c: %ld'"), cip->oshort, level);

  compress_level = level;
}

static void
setcompresstype(const struct cmdinfo *cip, const char *value)
{
  compressor = compressor_find_by_name(value);
  if (compressor == NULL)
    ohshit(_("unknown compression type `%s'!"), value);
}

static const struct cmdinfo cmdinfos[]= {
  ACTION("build",         'b', 0, do_build),
  ACTION("contents",      'c', 0, do_contents),
  ACTION("control",       'e', 0, do_control),
  ACTION("info",          'I', 0, do_info),
  ACTION("field",         'f', 0, do_field),
  ACTION("extract",       'x', 0, do_extract),
  ACTION("vextract",      'X', 0, do_vextract),
  ACTION("fsys-tarfile",  0,   0, do_fsystarfile),
  ACTION("show",          'W', 0, do_showinfo),

  { "new",           0,   0, &oldformatflag, NULL,         NULL,          0 },
  { "old",           0,   0, &oldformatflag, NULL,         NULL,          1 },
  { "debug",         'D', 0, &debugflag,     NULL,         NULL,          1 },
  { "nocheck",       0,   0, &nocheckflag,   NULL,         NULL,          1 },
  { "compression",   'z', 1, NULL,           NULL,         set_compress_level },
  { "compress_type", 'Z', 1, NULL,           NULL,         setcompresstype  },
  { "showformat",    0,   1, NULL,           &showformat,  NULL             },
  { "help",          'h', 0, NULL,           NULL,         usage            },
  { "version",       0,   0, NULL,           NULL,         printversion     },
  {  NULL,           0,   0, NULL,           NULL,         NULL             }
};

int main(int argc, const char *const *argv) {
  int ret;

  setlocale(LC_NUMERIC, "POSIX");
  setlocale(LC_ALL, "");
  bindtextdomain(PACKAGE, LOCALEDIR);
  textdomain(PACKAGE);

  dpkg_set_progname(BACKEND);
  standard_startup();
  myopt(&argv, cmdinfos, printforhelp);

  if (!cipaction) badusage(_("need an action option"));

  unsetenv("GZIP");

  ret = cipaction->action(argv);

  standard_shutdown();

  return ret;
}

/* vi: sw=2
 */
