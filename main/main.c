/*
 * dpkg - main program for package management
 * main.c - main program
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
#include <errno.h>
#include <unistd.h>
#include <dirent.h>
#include <limits.h>
#include <ctype.h>

#include "config.h"
#include "dpkg.h"
#include "dpkg-db.h"
#include "version.h"
#include "myopt.h"

#include "main.h"

static void printversion(void) {
  if (!fputs("Debian Linux `" DPKG "' package management program version "
              DPKG_VERSION_ARCH ".\n"
             "Copyright 1994-1996 Ian Jackson, Bruce Perens.  This is free software;\n"
             "see the GNU General Public Licence version 2 or later for copying\n"
             "conditions.  There is NO warranty.  See dpkg --licence for details.\n",
             stdout)) werr("stdout");
}

static void usage(void) {
  if (!fputs("\
Usage: " DPKG " -i|--install    <.deb file name> ... | -R|--recursive <dir> ...\n\
       " DPKG " --unpack        <.deb file name> ... | -R|--recursive <dir> ...\n\
       " DPKG " -A|--avail      <.deb file name> ... | -R|--recursive <dir> ...\n\
       " DPKG " --configure     <package name> ... | -a|--pending\n\
       " DPKG " -r|--remove | --purge <package name> ... | -a|--pending\n\
       " DPKG " -s|--status       <package-name> ...\n\
       " DPKG " -L|--listfiles    <package-name> ...\n\
       " DPKG " -l|--list         [<package-name-pattern> ...]\n\
       " DPKG " -S|--search       <filename-search-pattern> ...\n\
       " DPKG " -C|--audit | --yet-to-unpack\n\
       " DPKG " --merge-avail | --update-avail <Packages-file>\n\
Use " DPKG " -b|--build|-c|--contents|-e|--control|-I|--info|-f|--field|\n\
 -x|--extract|-X|--vextract|--fsys-tarfile  on archives (type " BACKEND " --help.)\n\
For internal use: " DPKG " --assert-support-predepends | --predep-package\n\
\n\
Options: --help --version --licence   --force-help  -Dh|--debug=help\n\
         --root=<directory>   --admindir=<directory>   --instdir=<directory>\n\
         -O|--selected-only   -E|--skip-same-version   -G=--refuse-downgrade\n\
         -B|--auto-deconfigure   --ignore-depends=<package>,...\n\
         -D|--debug=<octal>   --force-...  --no-force-...|--refuse-...\n\
         --largemem|--smallmem   --no-act\n\
\n\
Use `" DSELECT "' for user-friendly package management.\n",
             stdout)) werr("stdout");
}

const char thisname[]= DPKG;
const char architecture[]= ARCHITECTURE;
const char printforhelp[]=
 "Type " DPKG " --help for help about installing and deinstalling packages;\n"
 "Use " DSELECT " for user-friendly package management;\n"
 "Type " DPKG " -Dhelp for a list of " DPKG " debug flag values;\n"
 "Type " DPKG " --force-help for a list of forcing options;\n"
 "Type " BACKEND " --help for help about manipulating *.deb files.";

const struct cmdinfo *cipaction= 0;
int f_pending=0, f_recursive=0, f_alsoselect=1, f_skipsame=0, f_noact=0;
int f_autodeconf=0, f_largemem=0;
unsigned long f_debug=0;
int fc_downgrade=1, fc_configureany=0, fc_hold=0, fc_removereinstreq=0, fc_overwrite=1;
int fc_removeessential=0, fc_conflicts=0, fc_depends=0, fc_dependsversion=0;
int fc_autoselect=1, fc_badpath=0, fc_overwritediverted=0, fc_architecture=0;

const char *admindir= ADMINDIR;
const char *instdir= "";
struct packageinlist *ignoredependss=0;

static const struct forceinfo {
  const char *name;
  int *opt;
} forceinfos[]= {
  { "downgrade",           &fc_downgrade                },
  { "configure-any",       &fc_configureany             },
  { "hold",                &fc_hold                     },
  { "remove-reinstreq",    &fc_removereinstreq          },
  { "remove-essential",    &fc_removeessential          },
  { "conflicts",           &fc_conflicts                },
  { "depends",             &fc_depends                  },
  { "depends-version",     &fc_dependsversion           },
  { "auto-select",         &fc_autoselect               },
  { "bad-path",            &fc_badpath                  },
  { "overwrite",           &fc_overwrite                },
  { "overwrite-diverted",  &fc_overwritediverted        },
  { "architecture",        &fc_architecture             },
  {  0                                                  }
};

static void helponly(const struct cmdinfo *cip, const char *value) {
  usage(); exit(0);
}
static void versiononly(const struct cmdinfo *cip, const char *value) {
  printversion(); exit(0);
}

static void setaction(const struct cmdinfo *cip, const char *value) {
  if (cipaction)
    badusage("conflicting actions --%s and --%s",cip->olong,cipaction->olong);
  cipaction= cip;
}

static void setdebug(const struct cmdinfo *cpi, const char *value) {
  char *endp;

  if (*value == 'h') {
    if (!fputs(
DPKG " debugging option, --debug=<octal> or -D<octal>:\n\n\
 number  ref. in source   description\n\
      1   general           Generally helpful progress information\n\
      2   scripts           Invocation and status of maintainer scripts\n\
     10   eachfile          Output for each file processed\n\
    100   eachfiledetail    Lots of output for each file processed\n\
     20   conff             Output for each configuration file\n\
    200   conffdetail       Lots of output for each configuration file\n\
     40   depcon            Dependencies and conflicts\n\
    400   depcondetail      Lots of dependencies/conflicts output\n\
   1000   veryverbose       Lots of drivel about eg the dpkg/info directory\n\
   2000   stupidlyverbose   Insane amounts of drivel\n\n\
Debugging options are be mixed using bitwise-or.\n\
Note that the meanings and values are subject to change.\n",
             stderr)) werr("stderr");
    exit(0);
  }
  
  f_debug= strtoul(value,&endp,8);
  if (*endp) badusage("--debug requires an octal argument");
}

static void setroot(const struct cmdinfo *cip, const char *value) {
  char *p;
  instdir= value;
  p= m_malloc(strlen(value) + sizeof(ADMINDIR));
  strcpy(p,value);
  strcat(p,ADMINDIR);
  admindir= p;
}

static void ignoredepends(const struct cmdinfo *cip, const char *value) {
  char *copy, *p;
  const char *pnerr;
  struct packageinlist *ni;

  copy= m_malloc(strlen(value)+2);
  strcpy(copy,value);
  copy[strlen(value)+1]= 0;
  for (p=copy; *p; p++) {
    if (*p != ',') continue;
    *p++= 0;
    if (!*p || *p==',' || p==copy+1)
      badusage("null package name in --ignore-depends comma-separated list `%.250s'",
               value);
  }
  p= copy;
  while (*p) {
    pnerr= illegal_packagename(value,0);
    if (pnerr) ohshite("--ignore-depends requires a legal package name. "
                       "`%.250s' is not; %s", value, pnerr);
    ni= m_malloc(sizeof(struct packageinlist));
    ni->pkg= findpackage(value);
    ni->next= ignoredependss;
    ignoredependss= ni;
    p+= strlen(p)+1;
  }
}

static void setforce(const struct cmdinfo *cip, const char *value) {
  const char *comma;
  int l;
  const struct forceinfo *fip;

  if (!strcmp(value,"help")) {
    if (!fputs(
DPKG " forcing options - control behaviour when problems found:\n\
  warn but continue:  --force-<thing>,<thing>,...\n\
  stop with error:    --refuse-<thing>,<thing>,... | --no-force-<thing>,...\n\
 Forcing things:\n\
  auto-select [*]        (De)select packages to install (remove) them\n\
  dowgrade [*]           Replace a package with a lower version\n\
  configure-any          Configure any package which may help this one\n\
  hold                   Process incidental packages even when on hold\n\
  bad-path               PATH is missing important programs, problems likely\n\
  overwrite              Overwrite a file from one package with another\n\
  overwrite-diverted     Overwrite a diverted file with an undiverted version\n\
  depends-version [!]    Turn dependency version problems into warnings\n\
  depends [!]            Turn all dependency problems into warnings\n\
  conflicts [!]          Allow installation of conflicting packages\n\
  architecture [!]       Process even packages with wrong architecture\n\
  remove-reinstreq [!]   Remove packages which require installation\n\
  remove-essential [!]   Remove an essential package\n\
\n\
WARNING - use of options marked [!] can seriously damage your installation.\n\
Forcing options marked [*] are enabled by default.\n",
               stderr)) werr("stderr");
    exit(0);
  }

  for (;;) {
    comma= strchr(value,',');
    l= comma ? (int)(comma-value) : strlen(value);
    for (fip=forceinfos; fip->name; fip++)
      if (!strncmp(fip->name,value,l) && strlen(fip->name)==l) break;
    if (!fip->name)
      badusage("unknown force/refuse option `%.*s'", l<250 ? l : 250, value);
    *fip->opt= cip->arg;
    if (!comma) break;
    value= ++comma;
  }
}

static const char *const passlongopts[]= {
  "build", "contents", "control", "info", "field", "extract",
  "vextract", "fsys-tarfile", 0
};

static const char passshortopts[]= "bceIfxX";
static const char okpassshortopts[]= "D";

static const struct cmdinfo cmdinfos[]= {
  { "install",           'i',  0,  0, 0,               setaction,     act_install    },
  { "unpack",             0,   0,  0, 0,               setaction,     act_unpack     },
  { "avail",             'A',  0,  0, 0,               setaction,     act_avail      },
  { "configure",          0,   0,  0, 0,               setaction,     act_configure  },
  { "remove",            'r',  0,  0, 0,               setaction,     act_remove     },
  { "purge",              0,   0,  0, 0,               setaction,     act_purge      },
  { "list",              'l',  0,  0, 0,               setaction,     act_list       },
  { "status",            's',  0,  0, 0,               setaction,     act_status     },
  { "search",            'S',  0,  0, 0,               setaction,     act_search     },
  { "audit",             'C',  0,  0, 0,               setaction,     act_audit      },
  { "listfiles",         'L',  0,  0, 0,               setaction,     act_listfiles  },
  { "update-avail",       0,   0,  0, 0,               setaction,     act_avreplace  },
  { "merge-avail",        0,   0,  0, 0,               setaction,     act_avmerge    },
  { "yet-to-unpack",      0,   0,  0, 0,               setaction,     act_unpackchk  },
  { "assert-support-predepends", 0, 0,  0, 0,          setaction,    act_assuppredep },
  { "print-architecture", 0,   0,  0, 0,               setaction,     act_printarch  },
  { "print-installation-architecture", 0,0,  0,0,      setaction,  act_printinstarch },
  { "predep-package",     0,   0,  0, 0,               setaction,  act_predeppackage },
  { "pending",           'a',  0,  &f_pending,     0,  0,             1              },
  { "recursive",         'R',  0,  &f_recursive,   0,  0,             1              },
  { "no-act",             0,   0,  &f_noact,       0,  0,             1              },
  {  0,                  'G',  0,  &fc_downgrade,  0,  0, /* alias for --refuse */ 0 },
  { "selected-only",     'O',  0,  &f_alsoselect,  0,  0,             0              },
  { "no-also-select",  'N', 0, &f_alsoselect, 0, 0, 0 /* fixme: remove eventually */ },
  { "skip-same-version", 'E',  0,  &f_skipsame,    0,  0,             1              },
  { "auto-deconfigure",  'B',  0,  &f_autodeconf,  0,  0,             1              },
  { "largemem",           0,   0,  &f_largemem,    0,  0,             1              },
  { "smallmem",           0,   0,  &f_largemem,    0,  0,            -1              },
  { "root",               0,   1,  0, 0,               setroot                       },
  { "admindir",           0,   1,  0, &admindir,       0                             },
  { "instdir",            0,   1,  0, &instdir,        0                             },
  { "ignore-depends",     0,   1,  0, 0,               ignoredepends                 },
  { "force",              0,   2,  0, 0,               setforce,      1              },
  { "refuse",             0,   2,  0, 0,               setforce,      0              },
  { "no-force",           0,   2,  0, 0,               setforce,      0              },
  { "debug",             'D',  1,  0, 0,               setdebug                      },
  { "help",              'h',  0,  0, 0,               helponly                      },
  { "version",            0,   0,  0, 0,               versiononly                   },
  { "licence",/* UK spelling */ 0,0,0,0,               showcopyright                 },
  { "license",/* US spelling */ 0,0,0,0,               showcopyright                 },
  {  0,                   0                                                          }
};

static void execbackend(int argc, const char *const *argv) {
  execvp(BACKEND, (char* const*) argv);
  ohshite("failed to exec " BACKEND);
}

int main(int argc, const char *const *argv) {
  jmp_buf ejbuf;
  int c;
  const char *argp, *const *blongopts, *const *argvs;

  if (setjmp(ejbuf)) { /* expect warning about possible clobbering of argv */
    error_unwind(ehflag_bombout); exit(2);
  }
  push_error_handler(&ejbuf,print_error_fatal,0);

  umask(022); /* Make sure all our status databases are readable. */
  
  for (argvs=argv+1; (argp= *argvs) && *argp++=='-'; argvs++) {
    if (*argp++=='-') {
      if (!strcmp(argp,"-")) break;
      for (blongopts=passlongopts; *blongopts; blongopts++) {
        if (!strcmp(argp,*blongopts)) execbackend(argc,argv);
      }
    } else {
      if (!*--argp) break;
      while ((c= *argp++)) {
        if (strchr(passshortopts,c)) execbackend(argc,argv);
        if (!strchr(okpassshortopts,c)) break;
      }
    }
  }

  myopt(&argv,cmdinfos);
  if (!cipaction) badusage("need an action option");

  setvbuf(stdout,0,_IONBF,0);
  filesdbinit();
  
  switch (cipaction->arg) {
  case act_install: case act_unpack: case act_avail:
    checkpath();
    archivefiles(argv);
    break;
  case act_configure: case act_remove: case act_purge:
    checkpath();
    packages(argv);
    break;
  case act_listfiles: case act_status:
    enqperpackage(argv);
    break;
  case act_avreplace: 
    availablefrompackages(argv,1);
    break;
  case act_avmerge:
    availablefrompackages(argv,0);
    break;
  case act_audit:
    audit(argv);
    break;
  case act_unpackchk:
    unpackchk(argv);
    break;
  case act_list:
    listpackages(argv);
    break;
  case act_search:
    searchfiles(argv);
    break;
  case act_assuppredep:
    assertsupportpredepends(argv);
    break;
  case act_predeppackage:
    predeppackage(argv);
    break;
  case act_printinstarch:
    if (printf("%s\n",architecture) == EOF) werr("stdout");
    if (fflush(stdout)) werr("stdout");
    break;
  case act_printarch:
    printarchitecture(argv);
    break;
  default:
    internerr("unknown action");
  }

  set_error_display(0,0);
  error_unwind(ehflag_normaltidy);

  return reportbroken_retexitstatus();
}
