/*
 * dpkg-deb - construction and deconstruction of *.deb archives
 * main.c - main program
 *
 * Copyright (C) 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
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
#include <assert.h>

#include <dpkg.h>
#include <dpkg-db.h>
#include <myopt.h>

#include "dpkg-deb.h"

const char* showformat	= "${Package}\t${Version}\n";

static void printversion(void) {
  if (printf(_("Debian `%s' package archive backend version %s.\n"),
	     BACKEND, DPKG_VERSION_ARCH) < 0) werr("stdout");
  if (printf(_("This is free software; see the GNU General Public License version 2 or\n"
	       "later for copying conditions. There is NO warranty.\n"
	       "See %s --license for copyright and license details.\n"),
	     BACKEND) < 0) werr("stdout");
}

static void usage(void) {
  if (printf(_(
"Usage: %s [<option> ...] <command>\n"
"\n"), BACKEND) < 0) werr("stdout");

  if (printf(_(
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
"\n")) < 0) werr("stdout");

  if (printf(_(
"  -h|--help                        Show this help message.\n"
"  --version                        Show the version.\n"
"  --license|--licence              Show the copyright licensing terms.\n"
"\n")) < 0) werr("stdout");

  if (printf(_(
"<deb> is the filename of a Debian format archive.\n"
"<cfile> is the name of an administrative file component.\n"
"<cfield> is the name of a field in the main `control' file.\n"
"\n")) < 0) werr("stdout");

  if (printf(_(
"Options:\n"
"  --showformat=<format>            Use alternative format for --show.\n"
"  -D                               Enable debugging output.\n"
"  --old, --new                     Select archive format.\n"
"  --nocheck                        Suppress control file check (build bad\n"
"                                     packages).\n"
"  -z#                              Set the compression level when building.\n"
"  -Z<type>                         Set the compression type used when building.\n"
"                                     Allowed values: gzip, bzip2, none.\n"
"\n")) < 0) werr("stdout");

  if (printf(_(
"Format syntax:\n"
"  A format is a string that will be output for each package. The format\n"
"  can include the standard escape sequences \\n (newline), \\r (carriage\n"
"  return) or \\\\ (plain backslash). Package information can be included\n"
"  by inserting variable references to package fields using the ${var[;width]}\n"
"  syntax. Fields will be right-aligned unless the width is negative in which\n"
"  case left alignment will be used.\n")) < 0) werr("stdout");

  if (printf(_(
"\n"
"Use `dpkg' to install and remove packages from your system, or\n"
"`dselect' or `aptitude' for user-friendly package management.  Packages\n"
"unpacked using `dpkg-deb --extract' will be incorrectly installed !\n")) < 0)
    werr("stdout");
}

const char thisname[]= BACKEND;
const char printforhelp[]=
  N_("Type dpkg-deb --help for help about manipulating *.deb files;\n"
     "Type dpkg --help for help about installing and deinstalling packages.");

int debugflag=0, nocheckflag=0, oldformatflag=BUILDOLDPKGFORMAT;
const char* compression=NULL;
enum compression_type compress_type = GZ;
const struct cmdinfo *cipaction=0;
dofunction *action=0;

static void helponly(const struct cmdinfo *cip, const char *value) NONRETURNING;
static void helponly(const struct cmdinfo *cip, const char *value) {
  usage(); exit(0);
}
static void versiononly(const struct cmdinfo *cip, const char *value) NONRETURNING;
static void versiononly(const struct cmdinfo *cip, const char *value) {
  printversion(); exit(0);
}

static void setaction(const struct cmdinfo *cip, const char *value);
static void setcompresstype(const struct cmdinfo *cip, const char *value);

static dofunction *const dofunctions[]= {
  do_build,
  do_contents,
  do_control,
  do_info,
  do_field,
  do_extract,
  do_vextract,
  do_fsystarfile,
  do_showinfo
};

/* NB: the entries using setaction must appear first and be in the
 * same order as dofunctions:
 */
static const struct cmdinfo cmdinfos[]= {
  { "build",        'b',  0,  0, 0,               setaction        },
  { "contents",     'c',  0,  0, 0,               setaction        },
  { "control",      'e',  0,  0, 0,               setaction        },
  { "info",         'I',  0,  0, 0,               setaction        },
  { "field",        'f',  0,  0, 0,               setaction        },
  { "extract",      'x',  0,  0, 0,               setaction        },
  { "vextract",     'X',  0,  0, 0,               setaction        },
  { "fsys-tarfile",  0,   0,  0, 0,               setaction        },
  { "show",         'W',  0,  0, 0,               setaction        },
  { "new",           0,   0,  &oldformatflag, 0,  0,            0  },
  { "old",           0,   0,  &oldformatflag, 0,  0,            1  },
  { "debug",        'D',  0,  &debugflag,     0,  0,            1  },
  { "nocheck",       0,   0,  &nocheckflag,   0,  0,            1  },
  { "compression",  'z',  1,  0,   &compression,  0,            1  },
  { "compress_type",'Z',  1,  0, 0,               setcompresstype  },
  { "showformat",    0,   1,  0, &showformat,     0                },
  { "help",         'h',  0,  0, 0,               helponly         },
  { "version",       0,   0,  0, 0,               versiononly      },
  { "licence",       0,   0,  0, 0,               showcopyright    }, /* UK spelling */
  { "license",       0,   0,  0, 0,               showcopyright    }, /* US spelling */
  {  0,              0                                             }
};

static void setaction(const struct cmdinfo *cip, const char *value) {
  if (cipaction)
    badusage(_("conflicting actions -%c (--%s) and -%c (--%s)"),
             cip->oshort, cip->olong, cipaction->oshort, cipaction->olong);
  cipaction= cip;
  assert((int)(cip-cmdinfos) < (int)(sizeof(dofunctions)*sizeof(dofunction*)));
  action= dofunctions[cip-cmdinfos];
}

static void setcompresstype(const struct cmdinfo *cip, const char *value) {
  if (!strcmp(value, "gzip"))
    compress_type= GZ;
  else if (!strcmp(value, "bzip2"))
    compress_type= BZ2;
  else if (!strcmp(value, "none"))
    compress_type= CAT;
  else
    ohshit(_("unknown compression type `%s'!"), value);
}

int main(int argc, const char *const *argv) {
  jmp_buf ejbuf;

  setlocale(LC_NUMERIC, "POSIX");
  standard_startup(&ejbuf, argc, &argv, NULL, 0, cmdinfos);
  if (!cipaction) badusage(_("need an action option"));

  unsetenv("GZIP");
  action(argv);
  standard_shutdown(0);
  exit(0);
}

/* vi: sw=2
 */
