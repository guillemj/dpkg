/*
 * dpkg-split - splitting and joining of multipart *.deb archives
 * main.c - main program
 *
 * Copyright (C) 1995 Ian Jackson <ian@chiark.greenend.org.uk>
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

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <assert.h>
#include <sys/types.h>
#include <sys/stat.h>

#include <dpkg.h>
#include <dpkg-db.h>
#include <myopt.h>

#include "dpkg-split.h"

static void printversion(void) {
  if (fputs
      (_("Debian GNU/Linux `dpkg-split' package split/join tool; version "), stdout) < 0) werr ("stdout");
  if (fputs (DPKG_VERSION_ARCH ".\n", stdout) < 0) werr ("stdout");
  if (fputs (_("Copyright (C) 1994-1996 Ian Jackson.  This is free software; see the\n"
       "GNU General Public Licence version 2 or later for copying conditions.\n"
       "There is NO warranty.  See dpkg-split --licence for details.\n"),
       stdout) < 0) werr("stdout");
}

static void usage(void) {
  if (printf(_("\
Usage: dpkg-split -s|--split <file> [<prefix>]     Split an archive.\n\
       dpkg-split -j|--join <part> <part> ...      Join parts together.\n\
       dpkg-split -I|--info <part> ...             Display info about a part.\n\
       dpkg-split -h|--help|--version|--licence    Show help/version/licence.\n\
\n\
       dpkg-split -a|--auto -o <complete> <part>   Auto-accumulate parts.\n\
       dpkg-split -l|--listq                       List unmatched pieces.\n\
       dpkg-split -d|--discard [<filename> ...]    Discard unmatched pieces.\n\
\n\
Options:  --depotdir <directory>  (default is %s/%s)\n\
          -S|--partsize <size>    (in Kb, for -s, default is 450)\n\
          -o|--output <file>      (for -j, default is <package>-<version>.deb)\n\
          -Q|--npquiet            (be quiet when -a is not a part)\n\
          --msdos                 (generate 8.3 filenames)\n\
\n\
Exit status: 0 = OK;  1 = -a is not a part;  2 = trouble!\n"),
             ADMINDIR, PARTSDIR) < 0) werr("stdout");
}

const char thisname[]= SPLITTER;
const char printforhelp[]= N_("Type dpkg-split --help for help.");

dofunction *action=NULL;
const struct cmdinfo *cipaction=NULL;
long maxpartsize= SPLITPARTDEFMAX;
const char *depotdir= ADMINDIR "/" PARTSDIR, *outputfile= NULL;
struct partqueue *queue= NULL;
int npquiet= 0, msdos= 0;

void rerr(const char *fn) {
  ohshite(_("error reading %s"),fn);
}

void rerreof(FILE *f, const char *fn) {
  if (ferror(f)) ohshite(_("error reading %.250s"),fn);
  ohshit(_("unexpected end of file in %.250s"),fn);
}

static void helponly(const struct cmdinfo *cip, const char *value) NONRETURNING;
static void helponly(const struct cmdinfo *cip, const char *value) {
  usage(); exit(0);
}
static void versiononly(const struct cmdinfo *cip, const char *value) NONRETURNING;
static void versiononly(const struct cmdinfo *cip, const char *value) {
  printversion(); exit(0);
}

static void setaction(const struct cmdinfo *cip, const char *value);

static void setpartsize(const struct cmdinfo *cip, const char *value) {
  long newpartsize;
  char *endp;

  newpartsize= strtol(value,&endp,10);
  if (newpartsize <= 0 || newpartsize > (INT_MAX >> 10))
    badusage(_("part size is far too large or is not positive"));

  maxpartsize= newpartsize << 10;
  if (maxpartsize <= HEADERALLOWANCE)
    badusage(_("part size must be at least %dk (to allow for header)"),
             (HEADERALLOWANCE >> 10) + 1);
}

static dofunction *const dofunctions[]= {
  do_split,
  do_join,
  do_info,
  do_auto,
  do_queue,
  do_discard,
};

/* NB: the entries using setaction must appear first and be in the
 * same order as dofunctions:
 */
static const struct cmdinfo cmdinfos[]= {
  { "split",        's',  0,  NULL, NULL,             setaction           },
  { "join",         'j',  0,  NULL, NULL,             setaction           },
  { "info",         'I',  0,  NULL, NULL,             setaction           },
  { "auto",         'a',  0,  NULL, NULL,             setaction           },
  { "listq",        'l',  0,  NULL, NULL,             setaction           },
  { "discard",      'd',  0,  NULL, NULL,             setaction           },
  { "help",         'h',  0,  NULL, NULL,             helponly            },
  { "version",       0,   0,  NULL, NULL,             versiononly         },
  { "licence",       0,   0,  NULL, NULL,             showcopyright       }, /* UK spelling */
  { "license",       0,   0,  NULL, NULL,             showcopyright       }, /* US spelling */
  { "depotdir",      0,   1,  NULL, &depotdir,     NULL                   },
  { "partsize",     'S',  1,  NULL, NULL,             setpartsize         },
  { "output",       'o',  1,  NULL, &outputfile,   NULL                   },
  { "npquiet",      'Q',  0,  &npquiet, NULL,      NULL,              1   },
  { "msdos",         0,   0,  &msdos, NULL,        NULL,              1   },
  {  NULL,              0                                              }
};

static void setaction(const struct cmdinfo *cip, const char *value) {
  if (cipaction)
    badusage(_("conflicting actions --%s and --%s"),cip->olong,cipaction->olong);
  cipaction= cip;
  assert((int)(cip-cmdinfos) < (int)(sizeof(dofunctions)*sizeof(dofunction*)));
  action= dofunctions[cip-cmdinfos];
}

int main(int argc, const char *const *argv) {
  jmp_buf ejbuf;
  int l;
  char *p;

  standard_startup(&ejbuf, argc, &argv, NULL, 0, cmdinfos);
  if (!cipaction) badusage(_("need an action option"));

  l= strlen(depotdir);
  if (l && depotdir[l-1] != '/') {
    p= nfmalloc(l+2);
    strcpy(p,depotdir);
    strcpy(p+l,"/");
    depotdir= p;
  }

  setvbuf(stdout,NULL,_IONBF,0);
  action(argv);

  if (ferror(stderr)) werr("stderr");
  
  standard_shutdown(0);
  exit(0);
}
