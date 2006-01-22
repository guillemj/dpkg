/*
 * dpkg - main program for package management
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
#include <fcntl.h>

#include <dpkg.h>
#include <dpkg-db.h>
#include <myopt.h>

#include "main.h"

static void printversion(void) {
  if (fputs(_("Debian GNU/Linux `"), stdout) < 0) werr("stdout");
  if (fputs(DPKG, stdout) < 0) werr("stdout");
  if (fputs(_("' package management program version "), stdout) < 0) werr("stdout");
  if (fputs( DPKG_VERSION_ARCH ".\n", stdout) < 0) werr("stdout");
  if (fputs(_( "This is free software; see the GNU General Public Licence version 2 or\n"
		"later for copying conditions.  There is NO warranty.\n"
		"See " DPKG " --licence for copyright and license details.\n"),
		 stdout) < 0) werr("stdout");
}
/*
   options that need fixing:
  dpkg --yet-to-unpack                 \n\
  */
static void usage(void) {
  if (fprintf (stdout, _("\
Usage: \n\
  dpkg -i|--install      <.deb file name> ... | -R|--recursive <dir> ...\n\
  dpkg --unpack          <.deb file name> ... | -R|--recursive <dir> ...\n\
  dpkg -A|--record-avail <.deb file name> ... | -R|--recursive <dir> ...\n\
  dpkg --configure              <package name> ... | -a|--pending\n\
  dpkg -r|--remove | -P|--purge <package name> ... | -a|--pending\n\
  dpkg --get-selections [<pattern> ...]    get list of selections to stdout\n\
  dpkg --set-selections                    set package selections from stdin\n\
  dpkg --update-avail <Packages-file>      replace available packages info\n\
  dpkg --merge-avail <Packages-file>       merge with info from file\n\
  dpkg --clear-avail                       erase existing available info\n\
  dpkg --forget-old-unavail                forget uninstalled unavailable pkgs\n\
  dpkg -s|--status <package-name> ...      display package status details\n\
  dpkg -p|--print-avail <package-name> ... display available version details\n\
  dpkg -L|--listfiles <package-name> ...   list files `owned' by package(s)\n\
  dpkg -l|--list [<pattern> ...]           list packages concisely\n\
  dpkg -S|--search <pattern> ...           find package(s) owning file(s)\n\
  dpkg -C|--audit                          check for broken package(s)\n\
  dpkg --print-architecture                print dpkg architecture\n\
  dpkg --compare-versions <a> <rel> <b>    compare version numbers - see below\n\
  dpkg --help | --version                  show this help / version number\n\
  dpkg --force-help | -Dh|--debug=help     help on forcing resp. debugging\n\
  dpkg --licence                           print copyright licensing terms\n\
\n\
Use dpkg -b|--build|-c|--contents|-e|--control|-I|--info|-f|--field|\n\
 -x|--extract|-X|--vextract|--fsys-tarfile  on archives (type %s --help.)\n\
\n\
For internal use: dpkg --assert-support-predepends | --predep-package |\n\
  --assert-working-epoch | --assert-long-filenames | --assert-multi-conrep\n\
\n\
Options:\n\
  --admindir=<directory>     Use <directory> instead of %s\n\
  --root=<directory>         Install on alternative system rooted elsewhere\n\
  --instdir=<directory>      Change inst'n root without changing admin dir\n\
  -O|--selected-only         Skip packages not selected for install/upgrade\n\
  -E|--skip-same-version     Skip packages whose same version is installed\n\
  -G|--refuse-downgrade      Skip packages with earlier version than installed\n\
  -B|--auto-deconfigure      Install even if it would break some other package\n\
  --no-debsig                Do not try to verify package signatures\n\
  --no-act|--dry-run|--simulate\n\
                             Just say what we would do - don't do it\n\
  -D|--debug=<octal>         Enable debugging - see -Dhelp or --debug=help\n\
  --status-fd <n>            Send status change updates to file descriptor <n>\n\
  --log=<filename>           Log status changes and actions to <filename>\n\
  --ignore-depends=<package>,... Ignore dependencies involving <package>\n\
  --force-...                    Override problems - see --force-help\n\
  --no-force-...|--refuse-...    Stop when problems encountered\n\
  --abort-after <n>              Abort after encountering <n> errors\n\
\n\
Comparison operators for --compare-versions are:\n\
 lt le eq ne ge gt       (treat empty version as earlier than any version);\n\
 lt-nl le-nl ge-nl gt-nl (treat empty version as later than any version);\n\
 < << <= = >= >> >       (only for compatibility with control file syntax).\n\
\n\
Use `dselect' or `aptitude' for user-friendly package management.\n"),
	    BACKEND, ADMINDIR) < 0) werr ("stdout");
}

const char thisname[]= "dpkg";
const char architecture[]= ARCHITECTURE;
const char printforhelp[]= N_("\
Type dpkg --help for help about installing and deinstalling packages [*];\n\
Use `dselect' or `aptitude' for user-friendly package management;\n\
Type dpkg -Dhelp for a list of dpkg debug flag values;\n\
Type dpkg --force-help for a list of forcing options;\n\
Type dpkg-deb --help for help about manipulating *.deb files;\n\
Type dpkg --licence for copyright licence and lack of warranty (GNU GPL) [*].\n\
\n\
Options marked [*] produce a lot of output - pipe it through `less' or `more' !");

const struct cmdinfo *cipaction= 0;
int f_pending=0, f_recursive=0, f_alsoselect=1, f_skipsame=0, f_noact=0;
int f_autodeconf=0, f_nodebsig=0;
unsigned long f_debug=0;
/* Change fc_overwrite to 1 to enable force-overwrite by default */
int fc_downgrade=1, fc_configureany=0, fc_hold=0, fc_removereinstreq=0, fc_overwrite=0;
int fc_removeessential=0, fc_conflicts=0, fc_depends=0, fc_dependsversion=0;
int fc_autoselect=1, fc_badpath=0, fc_overwritediverted=0, fc_architecture=0;
int fc_nonroot=0, fc_overwritedir=0, fc_conff_new=0, fc_conff_miss=0;
int fc_conff_old=0, fc_conff_def=0;
int fc_badverify = 0;

int errabort = 50;
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
  { "confnew",             &fc_conff_new                },
  { "confold",             &fc_conff_old                },
  { "confdef",             &fc_conff_def                },
  { "confmiss",            &fc_conff_miss               },
  { "depends",             &fc_depends                  },
  { "depends-version",     &fc_dependsversion           },
  { "auto-select",         &fc_autoselect               },
  { "bad-path",            &fc_badpath                  },
  { "not-root",            &fc_nonroot                  },
  { "overwrite",           &fc_overwrite                },
  { "overwrite-diverted",  &fc_overwritediverted        },
  { "overwrite-dir",       &fc_overwritedir             },
  { "architecture",        &fc_architecture             },
  { "bad-verify",          &fc_badverify                },
  {  0                                                  }
};

static void helponly(const struct cmdinfo *cip, const char *value) NONRETURNING;
static void helponly(const struct cmdinfo *cip, const char *value) {
  usage(); exit(0);
}
static void versiononly(const struct cmdinfo *cip, const char *value) NONRETURNING;
static void versiononly(const struct cmdinfo *cip, const char *value) {
  printversion(); exit(0);
}

static void setaction(const struct cmdinfo *cip, const char *value) {
  if (cipaction)
    badusage(_("conflicting actions --%s and --%s"),cip->olong,cipaction->olong);
  cipaction= cip;
}

static void setobsolete(const struct cmdinfo *cip, const char *value) {
  fprintf(stderr, _("Warning: obsolete option `--%s'\n"),cip->olong);
}

static void setdebug(const struct cmdinfo *cpi, const char *value) {
  char *endp;

  if (*value == 'h') {
    if (printf(
_("%s debugging option, --debug=<octal> or -D<octal>:\n\n\
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
Note that the meanings and values are subject to change.\n"),
             DPKG) < 0) werr("stdout");
    exit(0);
  }
  
  f_debug= strtoul(value,&endp,8);
  if (*endp) badusage(_("--debug requires an octal argument"));
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
      badusage(_("null package name in --ignore-depends comma-separated list `%.250s'"),
               value);
  }
  p= copy;
  while (*p) {
    pnerr= illegal_packagename(value,0);
    if (pnerr) ohshite(_("--ignore-depends requires a legal package name. "
                       "`%.250s' is not; %s"), value, pnerr);
    ni= m_malloc(sizeof(struct packageinlist));
    ni->pkg= findpackage(value);
    ni->next= ignoredependss;
    ignoredependss= ni;
    p+= strlen(p)+1;
  }
}

static void setinteger(const struct cmdinfo *cip, const char *value) {
  unsigned long v;
  char *ep;

  v= strtoul(value,&ep,0);
  if (*ep || v > INT_MAX)
    badusage(_("invalid integer for --%s: `%.250s'"),cip->olong,value);
  *cip->iassignto= v;
}

static void setpipe(const struct cmdinfo *cip, const char *value) {
  static struct pipef **lastpipe;
  unsigned long v;
  char *ep;

  v= strtoul(value,&ep,0);
  if (*ep || v > INT_MAX)
    badusage(_("invalid integer for --%s: `%.250s'"),cip->olong,value);

  lastpipe= cip->parg;
  if (*lastpipe) {
    (*lastpipe)->next= nfmalloc(sizeof(struct pipef));
    *lastpipe= (*lastpipe)->next;
  } else {
    *lastpipe= nfmalloc(sizeof(struct pipef));
  }
  (*lastpipe)->fd= v;
  (*lastpipe)->next= NULL;
}

static void setforce(const struct cmdinfo *cip, const char *value) {
  const char *comma;
  size_t l;
  const struct forceinfo *fip;

  if (!strcmp(value,"help")) {
    if (printf(_("%s forcing options - control behaviour when problems found:\n\
  warn but continue:  --force-<thing>,<thing>,...\n\
  stop with error:    --refuse-<thing>,<thing>,... | --no-force-<thing>,...\n\
 Forcing things:\n\
  all                    Set all force options\n\
  auto-select [*]        (De)select packages to install (remove) them\n\
  downgrade [*]          Replace a package with a lower version\n\
  configure-any          Configure any package which may help this one\n\
  hold                   Process incidental packages even when on hold\n\
  bad-path               PATH is missing important programs, problems likely\n\
  not-root               Try to (de)install things even when not root\n\
  overwrite              Overwrite a file from one package with another\n\
  overwrite-diverted     Overwrite a diverted file with an undiverted version\n\
  bad-verify             Install a package even if it fails authenticity check\n\
  depends-version [!]    Turn dependency version problems into warnings\n\
  depends [!]            Turn all dependency problems into warnings\n\
  confnew [!]            Always use the new config files, don't prompt\n\
  confold [!]            Always use the old config files, don't prompt\n\
  confdef [!]            Use the default option for new config files if one\n\
                         is available, don't prompt. If no default can be found,\n\
                         you will be prompted unless one of the confold or\n\
                         confnew options is also given\n\
  confmiss [!]           Always install missing config files\n\
  conflicts [!]          Allow installation of conflicting packages\n\
  architecture [!]       Process even packages with wrong architecture\n\
  overwrite-dir [!]      Overwrite one package's directory with another's file\n\
  remove-reinstreq [!]   Remove packages which require installation\n\
  remove-essential [!]   Remove an essential package\n\
\n\
WARNING - use of options marked [!] can seriously damage your installation.\n\
Forcing options marked [*] are enabled by default.\n"),
               DPKG) < 0) werr("stdout");
    exit(0);
  }

  for (;;) {
    comma= strchr(value,',');
    l= comma ? (int)(comma-value) : strlen(value);
    for (fip=forceinfos; fip->name; fip++)
      if (!strncmp(fip->name,value,l) && strlen(fip->name)==l) break;
    if (!fip->name)
      if(!strncmp("all",value,l))
	for (fip=forceinfos; fip->name; fip++)
	  *fip->opt= cip->arg;
      else
	badusage(_("unknown force/refuse option `%.*s'"), l<250 ? (int)l : 250, value);
    else
      *fip->opt= cip->arg;
    if (!comma) break;
    value= ++comma;
  }
}

extern const char *log_file;

static const char okpassshortopts[]= "D";

void execbackend(const char *const *argv) NONRETURNING;
void commandfd(const char *const *argv);
static const struct cmdinfo cmdinfos[]= {
  /* This table has both the action entries in it and the normal options.
   * The action entries are made with the ACTION macro, as they all
   * have a very similar structure.
   */
#define ACTION(longopt,shortopt,code,function) \
 { longopt, shortopt, 0,0,0, setaction, code, 0, (voidfnp)function }
#define OBSOLETE(longopt,shortopt) \
 { longopt, shortopt, 0,0,0, setobsolete, 0, 0, 0 }
#define ACTIONBACKEND(longopt,shortop, backend) \
 { longopt, shortop, 0,0,0, setaction, 0, (void*)backend, (voidfnp)execbackend }

  ACTION( "install",                        'i', act_install,              archivefiles    ),
  ACTION( "unpack",                          0,  act_unpack,               archivefiles    ),
  ACTION( "record-avail",                   'A', act_avail,                archivefiles    ),
  ACTION( "configure",                       0,  act_configure,            packages        ),
  ACTION( "remove",                         'r', act_remove,               packages        ),
  ACTION( "purge",                          'P', act_purge,                packages        ),
  ACTIONBACKEND( "listfiles",               'L', DPKGQUERY),
  ACTIONBACKEND( "status",                  's', DPKGQUERY),
  ACTION( "get-selections",                  0,  act_getselections,        getselections   ),
  ACTION( "set-selections",                  0,  act_setselections,        setselections   ),
  ACTIONBACKEND( "print-avail",             'p', DPKGQUERY),
  ACTION( "update-avail",                    0,  act_avreplace,            updateavailable ),
  ACTION( "merge-avail",                     0,  act_avmerge,              updateavailable ),
  ACTION( "clear-avail",                     0,  act_avclear,              updateavailable ),
  ACTION( "forget-old-unavail",              0,  act_forgetold,            forgetold       ),
  ACTION( "audit",                          'C', act_audit,                audit           ),
  ACTION( "yet-to-unpack",                   0,  act_unpackchk,            unpackchk       ),
  ACTIONBACKEND( "list",                    'l', DPKGQUERY),
  ACTIONBACKEND( "search",                  'S', DPKGQUERY),
  ACTION( "assert-support-predepends",       0,  act_assertpredep,         assertpredep    ),
  ACTION( "assert-working-epoch",            0,  act_assertepoch,          assertepoch     ),
  ACTION( "assert-long-filenames",           0,  act_assertlongfilenames,  assertlongfilenames ),
  ACTION( "assert-multi-conrep",             0,  act_assertmulticonrep,    assertmulticonrep ),
  ACTION( "print-architecture",              0,  act_printarch,            printarch   ),
  ACTION( "print-installation-architecture", 0,  act_printinstarch,        printarch   ),
  ACTION( "predep-package",                  0,  act_predeppackage,        predeppackage   ),
  ACTION( "compare-versions",                0,  act_cmpversions,          cmpversions     ),
/*
  ACTION( "command-fd",                   'c', act_commandfd,   commandfd     ),
*/
  
  { "status-fd",	  0,   1,  0,              0,  setpipe, 0, &status_pipes },
  { "log",                0,   1,  0, &log_file,       0                             },
  { "pending",           'a',  0,  &f_pending,     0,  0,             1              },
  { "recursive",         'R',  0,  &f_recursive,   0,  0,             1              },
  { "no-act",             0,   0,  &f_noact,       0,  0,             1              },
  { "dry-run",            0,   0,  &f_noact,       0,  0,             1              },
  { "simulate",           0,   0,  &f_noact,       0,  0,             1              },
  { "no-debsig",          0,   0,  &f_nodebsig,    0,  0,             1              },
  {  0,                  'G',  0,  &fc_downgrade,  0,  0, /* alias for --refuse */ 0 },
  { "selected-only",     'O',  0,  &f_alsoselect,  0,  0,             0              },
  { "no-also-select",    'N',  0,  &f_alsoselect,  0,0,0 /* fixme: remove sometime */ },
  { "skip-same-version", 'E',  0,  &f_skipsame,    0,  0,             1              },
  { "auto-deconfigure",  'B',  0,  &f_autodeconf,  0,  0,             1              },
  OBSOLETE( "largemem", 0 ),
  OBSOLETE( "smallmem", 0 ),
  { "root",               0,   1,  0, 0,               setroot                       },
  { "abort-after",        0,   1,  &errabort,      0,  setinteger,    0              },
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
  ACTIONBACKEND( "build",		'b', BACKEND),
  ACTIONBACKEND( "contents",		'c', BACKEND),
  ACTIONBACKEND( "control",		'e', BACKEND),
  ACTIONBACKEND( "info",		'I', BACKEND),
  ACTIONBACKEND( "field",		'f', BACKEND),
  ACTIONBACKEND( "extract",		'x', BACKEND),
  ACTIONBACKEND( "new",			0,  BACKEND),
  ACTIONBACKEND( "old",			0,  BACKEND),
  ACTIONBACKEND( "vextract",		'X', BACKEND),
  ACTIONBACKEND( "fsys-tarfile",	0,   BACKEND),
  {  0,                   0                                                          }
};

void execbackend(const char *const *argv) {
  char **nargv;
  int i, argc = 1;
  const char *const *arg = argv;
  while(*arg != 0) { arg++; argc++; }
  nargv= malloc(sizeof(char *) * (argc + 2));

  if (!nargv) ohshite(_("couldn't malloc in execbackend"));
  nargv[0]= strdup(cipaction->parg);
  if (!nargv[0]) ohshite(_("couldn't strdup in execbackend"));
  nargv[1]= malloc(strlen(cipaction->olong) + 3);
  if (!nargv[1]) ohshite(_("couldn't malloc in execbackend"));
  strcpy(nargv[1], "--");
  strcat(nargv[1], cipaction->olong);
  for (i= 2; i <= argc; i++) {
    nargv[i]= strdup(argv[i-2]);
    if (!nargv[i]) ohshite(_("couldn't strdup in execbackend"));
  }
  nargv[i]= 0;
  execvp(cipaction->parg, nargv);
  ohshite(_("failed to exec %s"),(char *)cipaction->parg);
}
void commandfd(const char *const *argv) {
  jmp_buf ejbuf;
  struct varbuf linevb;
  const char * pipein;
  const char **newargs;
  char *ptr, *endptr;
  FILE *in;
  int c, lno, infd, i, skipchar;
  static void (*actionfunction)(const char *const *argv);

  if ((pipein= *argv++) == NULL) badusage(_("--command-fd takes 1 argument, not 0"));
  if (*argv) badusage(_("--command-fd only takes 1 argument"));
  if ((infd= strtol(pipein, (char **)NULL, 10)) == -1)
    ohshite(_("invalid number for --command-fd"));
  if ((in= fdopen(infd, "r")) == NULL)
    ohshite(_("couldn't open `%i' for stream"), infd);

  if (setjmp(ejbuf)) { /* expect warning about possible clobbering of argv */
    error_unwind(ehflag_bombout); exit(2);
  }
  varbufinit(&linevb);
  for (;;lno= 0) {
    const char **oldargs= NULL;
    int argc= 1, mode= 0;
    lno= 0;
    push_error_handler(&ejbuf,print_error_fatal,0);

    do { c= getc(in); if (c == '\n') lno++; } while (c != EOF && isspace(c));
    if (c == EOF) break;
    if (c == '#') {
      do { c= getc(in); if (c == '\n') lno++; } while (c != EOF && c != '\n');
      continue;
    }
    varbufreset(&linevb);
    do {
      varbufaddc(&linevb,c);
      c= getc(in);
      if (c == '\n') lno++;
      if (isspace(c)) argc++;  /* This isn't fully accurate, but overestimating can't hurt. */
    } while (c != EOF && c != '\n');
    if (c == EOF) ohshit(_("unexpected eof before end of line %d"),lno);
    if (!argc) continue;
    varbufaddc(&linevb,0);
printf("line=`%*s'\n",(int)linevb.used,linevb.buf);
    oldargs= newargs= realloc(oldargs,sizeof(const char *) * (argc + 1));
    argc= 1;
    ptr= linevb.buf;
    endptr= ptr + linevb.used;
    skipchar= 0;
    while(ptr < endptr) {
      if (skipchar) {
	skipchar= 0;
      } else if (*ptr == '\\') {
	memmove(ptr, (ptr+1), (linevb.used-(linevb.buf - ptr)-1));
	endptr--;
	skipchar= 1;
	continue;
      } else if (isspace(*ptr)) {
	if (mode == 1) {
	  *ptr= 0;
	  mode= 0;
	}
      } else {
	if (mode == 0) {
	  newargs[argc]= ptr;
	  argc++;
	  mode= 1;
	}
      }
      ptr++;
    }
    *ptr= 0;
    newargs[argc++] = 0;

/* We strdup each argument, but never free it, because the error messages
 * contain references back to these strings.  Freeing them, and reusing
 * the memory, would make those error messages confusing, to say the
 * least.
 */
    for(i=1;i<argc;i++)
	if (newargs[i]) newargs[i]=strdup(newargs[i]);

    cipaction= NULL;
    myopt((const char *const**)&newargs,cmdinfos);
    if (!cipaction) badusage(_("need an action option"));

    actionfunction= (void (*)(const char* const*))cipaction->farg;
    actionfunction(newargs);
    set_error_display(0,0);
    error_unwind(ehflag_normaltidy);
  }
}


int main(int argc, const char *const *argv) {
  jmp_buf ejbuf;
  static void (*actionfunction)(const char *const *argv);

  standard_startup(&ejbuf, argc, &argv, DPKG, 1, cmdinfos);
  if (!cipaction) badusage(_("need an action option"));

  setvbuf(stdout,0,_IONBF,0);
  filesdbinit();

  actionfunction= (void (*)(const char* const*))cipaction->farg;

  actionfunction(argv);

  standard_shutdown(0);

  return reportbroken_retexitstatus();
}
