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
  if (fputs(_("Debian `"), stdout) < 0) werr("stdout");
  if (fputs(BACKEND, stdout) < 0) werr("stdout");
  if (fputs(_("' package archive backend version "), stdout) < 0) werr("stdout");
  if (fputs(DPKG_VERSION_ARCH ".\n", stdout) < 0) werr("stdout");
  if (fputs(_("This is free software; see the GNU General Public Licence version 2 or\n"
	      "later for copying conditions. There is NO warranty.\n"
	      "See dpkg-deb --licence for details.\n"),
	    stdout) < 0) werr("stdout");
}

static void usage(void) {
  if (fputs(_(
"Command:\n"
"  -b|--build <directory> [<deb>]    build an archive.\n"
"  -c|--contents <deb>               list contents.\n"
"  -I|--info <deb> [<cfile>...]      show info to stdout.\n"
"  -W|--show <deb>                   show information on package(s)\n"
"  -f|--field <deb> [<cfield>...]    show field(s) to stdout.\n"
"  -e|--control <deb> [<directory>]  extract control info.\n"
"  -x|--extract <deb> <directory>    extract files.\n"
"  -X|--vextract <deb> <directory>   extract & list files.\n"
"  --fsys-tarfile <deb>              output filesystem tarfile.\n"
"  -h|--help                         display this message.\n"
"  --version | --licence             show version/licence.\n"
"\n"
"<deb> is the filename of a Debian format archive.\n"
"<cfile> is the name of an administrative file component.\n"
"<cfield> is the name of a field in the main `control' file.\n"
"\n"
"Options:\n"
"  --showformat=<format>      use alternative format for --show\n"
"  -D                         enable debugging output\n"
"  --old, --new               select archive format\n"
"  --nocheck                  suppress control file check (build bad package).\n"
"  -z# to set the compression when building\n"
"  -Z<type>                   set the compression type to use when building.\n"
"                             allowed values: gzip, bzip2, none\n"
"\n"
"Format syntax:\n"
"  A format is a string that will be output for each package. The format\n"
"  can include the standard escape sequences \\n (newline), \\r (carriage\n"
"  return) or \\\\ (plain backslash). Package information can be included\n"
"  by inserting variable references to package fields using the ${var[;width]}\n"
"  syntax. Fields will be right-aligned unless the width is negative in which\n"
"   case left alignment will be used. \n"
"\n"
"Use `dpkg' to install and remove packages from your system, or\n"
"`dselect' or `aptitude' for user-friendly package management.  Packages\n"
"unpacked using `dpkg-deb --extract' will be incorrectly installed !\n"),
	    stdout) < 0) werr("stdout");
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
    badusage(_("conflicting actions --%s and --%s"),cip->olong,cipaction->olong);
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
