/*
 * dpkg - main program for package management
 * main.c - main program
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2006-2010 Guillem Jover <guillem@debian.org>
 * Copyright © 2010 Canonical Ltd.
 *   written by Martin Pitt <martin.pitt@canonical.com>
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
#if HAVE_LOCALE_H
#include <locale.h>
#endif
#include <ctype.h>
#include <string.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/macros.h>
#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/command.h>
#include <dpkg/myopt.h>

#include "main.h"
#include "filesdb.h"
#include "filters.h"

static void DPKG_ATTR_NORET
printversion(const struct cmdinfo *ci, const char *value)
{
  printf(_("Debian `%s' package management program version %s.\n"),
         DPKG, DPKG_VERSION_ARCH);
  printf(_(
"This is free software; see the GNU General Public License version 2 or\n"
"later for copying conditions. There is NO warranty.\n"));

  m_output(stdout, _("<standard output>"));

  exit(0);
}
/*
   options that need fixing:
  dpkg --yet-to-unpack                 \n\
  */
static void DPKG_ATTR_NORET
usage(const struct cmdinfo *ci, const char *value)
{
  printf(_(
"Usage: %s [<option> ...] <command>\n"
"\n"), DPKG);

  printf(_(
"Commands:\n"
"  -i|--install       <.deb file name> ... | -R|--recursive <directory> ...\n"
"  --unpack           <.deb file name> ... | -R|--recursive <directory> ...\n"
"  -A|--record-avail  <.deb file name> ... | -R|--recursive <directory> ...\n"
"  --configure        <package> ... | -a|--pending\n"
"  --triggers-only    <package> ... | -a|--pending\n"
"  -r|--remove        <package> ... | -a|--pending\n"
"  -P|--purge         <package> ... | -a|--pending\n"
"  --get-selections [<pattern> ...] Get list of selections to stdout.\n"
"  --set-selections                 Set package selections from stdin.\n"
"  --clear-selections               Deselect every non-essential package.\n"
"  --update-avail <Packages-file>   Replace available packages info.\n"
"  --merge-avail <Packages-file>    Merge with info from file.\n"
"  --clear-avail                    Erase existing available info.\n"
"  --forget-old-unavail             Forget uninstalled unavailable pkgs.\n"
"  -s|--status <package> ...        Display package status details.\n"
"  -p|--print-avail <package> ...   Display available version details.\n"
"  -L|--listfiles <package> ...     List files `owned' by package(s).\n"
"  -l|--list [<pattern> ...]        List packages concisely.\n"
"  -S|--search <pattern> ...        Find package(s) owning file(s).\n"
"  -C|--audit                       Check for broken package(s).\n"
"  --print-architecture             Print dpkg architecture.\n"
"  --compare-versions <a> <op> <b>  Compare version numbers - see below.\n"
"  --force-help                     Show help on forcing.\n"
"  -Dh|--debug=help                 Show help on debugging.\n"
"\n"));

  printf(_(
"  -h|--help                        Show this help message.\n"
"  --version                        Show the version.\n"
"\n"));

  printf(_(
"Use dpkg -b|--build|-c|--contents|-e|--control|-I|--info|-f|--field|\n"
" -x|--extract|-X|--vextract|--fsys-tarfile  on archives (type %s --help).\n"
"\n"), BACKEND);

  printf(_(
"For internal use: dpkg --assert-support-predepends | --predep-package |\n"
"  --assert-working-epoch | --assert-long-filenames | --assert-multi-conrep.\n"
"\n"));

  printf(_(
"Options:\n"
"  --admindir=<directory>     Use <directory> instead of %s.\n"
"  --root=<directory>         Install on a different root directory.\n"
"  --instdir=<directory>      Change installation dir without changing admin dir.\n"
"  --path-exclude=<pattern>   Do not install paths which match a shell pattern.\n"
"  --path-include=<pattern>   Re-include a pattern after a previous exclusion.\n"
"  -O|--selected-only         Skip packages not selected for install/upgrade.\n"
"  -E|--skip-same-version     Skip packages whose same version is installed.\n"
"  -G|--refuse-downgrade      Skip packages with earlier version than installed.\n"
"  -B|--auto-deconfigure      Install even if it would break some other package.\n"
"  --[no-]triggers            Skip or force consequential trigger processing.\n"
"  --no-debsig                Do not try to verify package signatures.\n"
"  --no-act|--dry-run|--simulate\n"
"                             Just say what we would do - don't do it.\n"
"  -D|--debug=<octal>         Enable debugging (see -Dhelp or --debug=help).\n"
"  --status-fd <n>            Send status change updates to file descriptor <n>.\n"
"  --log=<filename>           Log status changes and actions to <filename>.\n"
"  --ignore-depends=<package>,...\n"
"                             Ignore dependencies involving <package>.\n"
"  --force-...                Override problems (see --force-help).\n"
"  --no-force-...|--refuse-...\n"
"                             Stop when problems encountered.\n"
"  --abort-after <n>          Abort after encountering <n> errors.\n"
"\n"), ADMINDIR);

  printf(_(
"Comparison operators for --compare-versions are:\n"
"  lt le eq ne ge gt       (treat empty version as earlier than any version);\n"
"  lt-nl le-nl ge-nl gt-nl (treat empty version as later than any version);\n"
"  < << <= = >= >> >       (only for compatibility with control file syntax).\n"
"\n"));

  printf(_(
"Use `dselect' or `aptitude' for user-friendly package management.\n"));

  m_output(stdout, _("<standard output>"));

  exit(0);
}

const char thisname[]= "dpkg";
const char architecture[]= ARCHITECTURE;
const char printforhelp[]= N_(
"Type dpkg --help for help about installing and deinstalling packages [*];\n"
"Use `dselect' or `aptitude' for user-friendly package management;\n"
"Type dpkg -Dhelp for a list of dpkg debug flag values;\n"
"Type dpkg --force-help for a list of forcing options;\n"
"Type dpkg-deb --help for help about manipulating *.deb files;\n"
"\n"
"Options marked [*] produce a lot of output - pipe it through `less' or `more' !");

int f_pending=0, f_recursive=0, f_alsoselect=1, f_skipsame=0, f_noact=0;
int f_autodeconf=0, f_nodebsig=0;
int f_triggers = 0;
unsigned long f_debug=0;
/* Change fc_overwrite to 1 to enable force-overwrite by default */
int fc_downgrade=1, fc_configureany=0, fc_hold=0, fc_removereinstreq=0, fc_overwrite=0;
int fc_removeessential=0, fc_conflicts=0, fc_depends=0, fc_dependsversion=0;
int fc_breaks=0, fc_badpath=0, fc_overwritediverted=0, fc_architecture=0;
int fc_nonroot=0, fc_overwritedir=0, fc_conff_new=0, fc_conff_miss=0;
int fc_conff_old=0, fc_conff_def=0;
int fc_conff_ask = 0;
int fc_badverify = 0;

int errabort = 50;
const char *admindir= ADMINDIR;
const char *instdir= "";
struct pkg_list *ignoredependss = NULL;

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
  { "confask",             &fc_conff_ask                },
  { "depends",             &fc_depends                  },
  { "depends-version",     &fc_dependsversion           },
  { "breaks",              &fc_breaks                   },
  { "bad-path",            &fc_badpath                  },
  { "not-root",            &fc_nonroot                  },
  { "overwrite",           &fc_overwrite                },
  { "overwrite-diverted",  &fc_overwritediverted        },
  { "overwrite-dir",       &fc_overwritedir             },
  { "architecture",        &fc_architecture             },
  { "bad-verify",          &fc_badverify                },
  {  NULL                                               }
};

static void setdebug(const struct cmdinfo *cpi, const char *value) {
  char *endp;

  if (*value == 'h') {
    printf(_(
"%s debugging option, --debug=<octal> or -D<octal>:\n"
"\n"
" number  ref. in source   description\n"
"      1   general           Generally helpful progress information\n"
"      2   scripts           Invocation and status of maintainer scripts\n"
"     10   eachfile          Output for each file processed\n"
"    100   eachfiledetail    Lots of output for each file processed\n"
"     20   conff             Output for each configuration file\n"
"    200   conffdetail       Lots of output for each configuration file\n"
"     40   depcon            Dependencies and conflicts\n"
"    400   depcondetail      Lots of dependencies/conflicts output\n"
"  10000   triggers          Trigger activation and processing\n"
"  20000   triggersdetail    Lots of output regarding triggers\n"
"  40000   triggersstupid    Silly amounts of output regarding triggers\n"
"   1000   veryverbose       Lots of drivel about eg the dpkg/info directory\n"
"   2000   stupidlyverbose   Insane amounts of drivel\n"
"\n"
"Debugging options are be mixed using bitwise-or.\n"
"Note that the meanings and values are subject to change.\n"), DPKG);
    m_output(stdout, _("<standard output>"));
    exit(0);
  }
  
  f_debug= strtoul(value,&endp,8);
  if (value == endp || *endp) badusage(_("--debug requires an octal argument"));
}

static void
setfilter(const struct cmdinfo *cip, const char *value)
{
  filter_add(value, cip->arg);
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

  copy= m_malloc(strlen(value)+2);
  strcpy(copy,value);
  copy[strlen(value) + 1] = '\0';
  for (p=copy; *p; p++) {
    if (*p != ',') continue;
    *p++ = '\0';
    if (!*p || *p==',' || p==copy+1)
      badusage(_("null package name in --ignore-depends comma-separated list `%.250s'"),
               value);
  }
  p= copy;
  while (*p) {
    pnerr = illegal_packagename(p, NULL);
    if (pnerr) ohshite(_("--ignore-depends requires a legal package name. "
                       "`%.250s' is not; %s"), p, pnerr);

    pkg_list_prepend(&ignoredependss, findpackage(p));

    p+= strlen(p)+1;
  }

  free(copy);
}

static void setinteger(const struct cmdinfo *cip, const char *value) {
  unsigned long v;
  char *ep;

  v= strtoul(value,&ep,0);
  if (value == ep || *ep || v > INT_MAX)
    badusage(_("invalid integer for --%s: `%.250s'"),cip->olong,value);
  *cip->iassignto= v;
}

static void setpipe(const struct cmdinfo *cip, const char *value) {
  struct pipef **pipe_head = cip->parg;
  struct pipef *pipe_new;
  unsigned long v;
  char *ep;

  v= strtoul(value,&ep,0);
  if (value == ep || *ep || v > INT_MAX)
    badusage(_("invalid integer for --%s: `%.250s'"),cip->olong,value);

  setcloexec(v, _("<package status and progress file descriptor>"));

  pipe_new = nfmalloc(sizeof(struct pipef));
  pipe_new->fd = v;
  pipe_new->next = *pipe_head;
  *pipe_head = pipe_new;
}

static bool
is_invoke_action(enum action action)
{
  switch (action) {
  case act_unpack:
  case act_configure:
  case act_install:
  case act_triggers:
  case act_remove:
  case act_purge:
    return true;
  default:
    return false;
  }
}

struct invoke_hook *pre_invoke_hooks = NULL;
struct invoke_hook **pre_invoke_hooks_tail = &pre_invoke_hooks;
struct invoke_hook *post_invoke_hooks = NULL;
struct invoke_hook **post_invoke_hooks_tail = &post_invoke_hooks;

static void
set_invoke_hook(const struct cmdinfo *cip, const char *value)
{
  struct invoke_hook ***hook_tail = cip->parg;
  struct invoke_hook *hook_new;

  hook_new = nfmalloc(sizeof(struct invoke_hook));
  hook_new->command = nfstrsave(value);
  hook_new->next = NULL;

  /* Add the new hook at the tail of the list to preserve the order. */
  **hook_tail = hook_new;
  *hook_tail = &hook_new->next;
}

static void
run_invoke_hooks(const char *action, struct invoke_hook *hook_head)
{
  struct invoke_hook *hook;

  setenv("DPKG_HOOK_ACTION", action, 1);

  for (hook = hook_head; hook; hook = hook->next) {
    int status;

    /* XXX: As an optimization, use exec instead if no shell metachar are
     * used “!$=&|\\`'"^~;<>{}[]()?*#”. */
    status = system(hook->command);
    if (status != 0)
      ohshit(_("error executing hook '%s', exit code %d"), hook->command,
             status);
  }

  unsetenv("DPKG_HOOK_ACTION");
}

static void setforce(const struct cmdinfo *cip, const char *value) {
  const char *comma;
  size_t l;
  const struct forceinfo *fip;

  if (!strcmp(value,"help")) {
    printf(_(
"%s forcing options - control behaviour when problems found:\n"
"  warn but continue:  --force-<thing>,<thing>,...\n"
"  stop with error:    --refuse-<thing>,<thing>,... | --no-force-<thing>,...\n"
" Forcing things:\n"
"  all [!]                Set all force options\n"
"  downgrade [*]          Replace a package with a lower version\n"
"  configure-any          Configure any package which may help this one\n"
"  hold                   Process incidental packages even when on hold\n"
"  bad-path               PATH is missing important programs, problems likely\n"
"  not-root               Try to (de)install things even when not root\n"
"  overwrite              Overwrite a file from one package with another\n"
"  overwrite-diverted     Overwrite a diverted file with an undiverted version\n"
"  bad-verify             Install a package even if it fails authenticity check\n"
"  depends-version [!]    Turn dependency version problems into warnings\n"
"  depends [!]            Turn all dependency problems into warnings\n"
"  confnew [!]            Always use the new config files, don't prompt\n"
"  confold [!]            Always use the old config files, don't prompt\n"
"  confdef [!]            Use the default option for new config files if one\n"
"                         is available, don't prompt. If no default can be found,\n"
"                         you will be prompted unless one of the confold or\n"
"                         confnew options is also given\n"
"  confmiss [!]           Always install missing config files\n"
"  confask [!]            Offer to replace config files with no new versions\n"
"  breaks [!]             Install even if it would break another package\n"
"  conflicts [!]          Allow installation of conflicting packages\n"
"  architecture [!]       Process even packages with wrong architecture\n"
"  overwrite-dir [!]      Overwrite one package's directory with another's file\n"
"  remove-reinstreq [!]   Remove packages which require installation\n"
"  remove-essential [!]   Remove an essential package\n"
"\n"
"WARNING - use of options marked [!] can seriously damage your installation.\n"
"Forcing options marked [*] are enabled by default.\n"), DPKG);
    m_output(stdout, _("<standard output>"));
    exit(0);
  }

  for (;;) {
    comma= strchr(value,',');
    l = comma ? (size_t)(comma - value) : strlen(value);
    for (fip=forceinfos; fip->name; fip++)
      if (!strncmp(fip->name,value,l) && strlen(fip->name)==l) break;
    if (!fip->name) {
      if (strncmp("all", value, l) == 0) {
	for (fip=forceinfos; fip->name; fip++)
	  if (fip->opt)
	    *fip->opt= cip->arg;
      } else
	badusage(_("unknown force/refuse option `%.*s'"),
	         (int)min(l, 250), value);
    } else {
      if (fip->opt)
	*fip->opt= cip->arg;
      else
	warning(_("obsolete force/refuse option '%s'\n"), fip->name);
    }
    if (!comma) break;
    value= ++comma;
  }
}

void execbackend(const char *const *argv) DPKG_ATTR_NORET;
void commandfd(const char *const *argv);
static const struct cmdinfo cmdinfos[]= {
  /* This table has both the action entries in it and the normal options.
   * The action entries are made with the ACTION macro, as they all
   * have a very similar structure.
   */
#define ACTIONBACKEND(longopt, shortopt, backend) \
 { longopt, shortopt, 0, NULL, NULL, setaction, 0, (void *)backend, (void_func *)execbackend }

  ACTION( "install",                        'i', act_install,              archivefiles    ),
  ACTION( "unpack",                          0,  act_unpack,               archivefiles    ),
  ACTION( "record-avail",                   'A', act_avail,                archivefiles    ),
  ACTION( "configure",                       0,  act_configure,            packages        ),
  ACTION( "remove",                         'r', act_remove,               packages        ),
  ACTION( "purge",                          'P', act_purge,                packages        ),
  ACTION( "triggers-only",                   0,  act_triggers,             packages        ),
  ACTIONBACKEND( "listfiles",               'L', DPKGQUERY),
  ACTIONBACKEND( "status",                  's', DPKGQUERY),
  ACTION( "get-selections",                  0,  act_getselections,        getselections   ),
  ACTION( "set-selections",                  0,  act_setselections,        setselections   ),
  ACTION( "clear-selections",                0,  act_clearselections,      clearselections ),
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
  ACTION( "print-installation-architecture", 0,  act_printinstarch,        printinstarch  ),
  ACTION( "predep-package",                  0,  act_predeppackage,        predeppackage   ),
  ACTION( "compare-versions",                0,  act_cmpversions,          cmpversions     ),
/*
  ACTION( "command-fd",                   'c', act_commandfd,   commandfd     ),
*/
  
  { "pre-invoke",        0,   1, NULL,          NULL,      set_invoke_hook, 0, &pre_invoke_hooks_tail },
  { "post-invoke",       0,   1, NULL,          NULL,      set_invoke_hook, 0, &post_invoke_hooks_tail },
  { "path-exclude",      0,   1, NULL,          NULL,      setfilter,     0 },
  { "path-include",      0,   1, NULL,          NULL,      setfilter,     1 },
  { "status-fd",         0,   1, NULL,          NULL,      setpipe, 0, &status_pipes },
  { "log",               0,   1, NULL,          &log_file, NULL,    0 },
  { "pending",           'a', 0, &f_pending,    NULL,      NULL,    1 },
  { "recursive",         'R', 0, &f_recursive,  NULL,      NULL,    1 },
  { "no-act",            0,   0, &f_noact,      NULL,      NULL,    1 },
  { "dry-run",           0,   0, &f_noact,      NULL,      NULL,    1 },
  { "simulate",          0,   0, &f_noact,      NULL,      NULL,    1 },
  { "no-debsig",         0,   0, &f_nodebsig,   NULL,      NULL,    1 },
  /* Alias ('G') for --refuse. */
  {  NULL,               'G', 0, &fc_downgrade, NULL,      NULL,    0 },
  { "selected-only",     'O', 0, &f_alsoselect, NULL,      NULL,    0 },
  { "triggers",           0,  0, &f_triggers,   NULL,      NULL,    1 },
  { "no-triggers",        0,  0, &f_triggers,   NULL,      NULL,   -1 },
  /* FIXME: Remove ('N') sometime. */
  { "no-also-select",    'N', 0, &f_alsoselect, NULL,      NULL,    0 },
  { "skip-same-version", 'E', 0, &f_skipsame,   NULL,      NULL,    1 },
  { "auto-deconfigure",  'B', 0, &f_autodeconf, NULL,      NULL,    1 },
  { "root",              0,   1, NULL,          NULL,      setroot,       0 },
  { "abort-after",       0,   1, &errabort,     NULL,      setinteger,    0 },
  { "admindir",          0,   1, NULL,          &admindir, NULL,          0 },
  { "instdir",           0,   1, NULL,          &instdir,  NULL,          0 },
  { "ignore-depends",    0,   1, NULL,          NULL,      ignoredepends, 0 },
  { "force",             0,   2, NULL,          NULL,      setforce,      1 },
  { "refuse",            0,   2, NULL,          NULL,      setforce,      0 },
  { "no-force",          0,   2, NULL,          NULL,      setforce,      0 },
  { "debug",             'D', 1, NULL,          NULL,      setdebug,      0 },
  { "help",              'h', 0, NULL,          NULL,      usage,         0 },
  { "version",           0,   0, NULL,          NULL,      printversion,  0 },
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
  { NULL,                0,   0, NULL,          NULL,      NULL,          0 }
};

void execbackend(const char *const *argv) {
  struct command cmd;
  char *arg;

  command_init(&cmd, cipaction->parg, NULL);
  command_add_arg(&cmd, cipaction->parg);

  /*
   * Special case: dpkg-query takes the --admindir option, and if dpkg itself
   * was given a different admin directory, we need to pass it along to it.
   */
  if (strcmp(cipaction->parg, DPKGQUERY) == 0 &&
      strcmp(admindir, ADMINDIR) != 0) {
    arg = m_malloc((strlen("--admindir=") + strlen(admindir) + 1));
    sprintf(arg, "--admindir=%s", admindir);
    command_add_arg(&cmd, arg);
  }

  arg = m_malloc(2 + strlen(cipaction->olong) + 1);
  sprintf(arg, "--%s", cipaction->olong);
  command_add_arg(&cmd, arg);

  /* Exlicitely separate arguments from options as any user-supplied
   * separator got stripped by the option parser */
  command_add_arg(&cmd, "--");
  command_add_argl(&cmd, (const char **)argv);

  command_exec(&cmd);
}

void commandfd(const char *const *argv) {
  struct varbuf linevb = VARBUF_INIT;
  const char * pipein;
  const char **newargs = NULL;
  char *ptr, *endptr;
  FILE *in;
  unsigned long infd;
  int c, lno, i;
  bool skipchar;
  void (*actionfunction)(const char *const *argv);

  pipein = *argv++;
  if (pipein == NULL)
    badusage(_("--command-fd takes one argument, not zero"));
  if (*argv)
    badusage(_("--command-fd only takes one argument"));
  errno = 0;
  infd = strtoul(pipein, &endptr, 10);
  if (pipein == endptr || *endptr || infd > INT_MAX)
    ohshite(_("invalid integer for --%s: `%.250s'"), "command-fd", pipein);
  if ((in= fdopen(infd, "r")) == NULL)
    ohshite(_("couldn't open `%i' for stream"), (int) infd);

  for (;;) {
    bool mode = false;
    int argc= 1;
    lno= 0;

    push_error_context();

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
    newargs = m_realloc(newargs, sizeof(const char *) * (argc + 1));
    argc= 1;
    ptr= linevb.buf;
    endptr= ptr + linevb.used;
    skipchar = false;
    while(ptr < endptr) {
      if (skipchar) {
	skipchar = false;
      } else if (*ptr == '\\') {
	memmove(ptr, (ptr+1), (linevb.used-(linevb.buf - ptr)-1));
	endptr--;
	skipchar = true;
	continue;
      } else if (isspace(*ptr)) {
	if (mode == true) {
	  *ptr = '\0';
	  mode = false;
	}
      } else {
	if (mode == false) {
	  newargs[argc]= ptr;
	  argc++;
	  mode = true;
	}
      }
      ptr++;
    }
    *ptr = '\0';
    newargs[argc++] = NULL;

/* We strdup each argument, but never free it, because the error messages
 * contain references back to these strings.  Freeing them, and reusing
 * the memory, would make those error messages confusing, to say the
 * least.
 */
    for(i=1;i<argc;i++)
      if (newargs[i])
        newargs[i] = m_strdup(newargs[i]);

    setaction(NULL, NULL);
    myopt((const char *const**)&newargs,cmdinfos);
    if (!cipaction) badusage(_("need an action option"));

    actionfunction= (void (*)(const char* const*))cipaction->farg;
    actionfunction(newargs);

    pop_error_context(ehflag_normaltidy);
  }
}


int main(int argc, const char *const *argv) {
  void (*actionfunction)(const char *const *argv);

  setlocale(LC_ALL, "");
  bindtextdomain(PACKAGE, LOCALEDIR);
  textdomain(PACKAGE);

  standard_startup();
  loadcfgfile(DPKG, cmdinfos);
  myopt(&argv, cmdinfos);

  if (!cipaction) badusage(_("need an action option"));

  if (!f_triggers)
    f_triggers = (cipaction->arg == act_triggers && *argv) ? -1 : 1;

  setvbuf(stdout, NULL, _IONBF, 0);

  if (is_invoke_action(cipaction->arg))
    run_invoke_hooks(cipaction->olong, pre_invoke_hooks);

  filesdbinit();

  actionfunction= (void (*)(const char* const*))cipaction->farg;

  actionfunction(argv);

  if (is_invoke_action(cipaction->arg))
    run_invoke_hooks(cipaction->olong, post_invoke_hooks);

  standard_shutdown();

  return reportbroken_retexitstatus();
}
