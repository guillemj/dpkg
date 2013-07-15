/*
 * dpkg - main program for package management
 * main.c - main program
 *
 * Copyright © 1994,1995 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2006-2012 Guillem Jover <guillem@debian.org>
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
#include <dpkg/arch.h>
#include <dpkg/subproc.h>
#include <dpkg/command.h>
#include <dpkg/pkg-spec.h>
#include <dpkg/options.h>

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
 * FIXME: Options that need fixing:
 * dpkg --yet-to-unpack
 * dpkg --command-fd
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
"  --add-architecture <arch>        Add <arch> to the list of architectures.\n"
"  --remove-architecture <arch>     Remove <arch> from the list of architectures.\n"
"  --print-architecture             Print dpkg architecture.\n"
"  --print-foreign-architectures    Print allowed foreign architectures.\n"
"  --compare-versions <a> <op> <b>  Compare version numbers - see below.\n"
"  --force-help                     Show help on forcing.\n"
"  -Dh|--debug=help                 Show help on debugging.\n"
"\n"));

  printf(_(
"  -?, --help                       Show this help message.\n"
"      --version                    Show the version.\n"
"\n"));

  printf(_(
"Use dpkg -b|--build|-c|--contents|-e|--control|-I|--info|-f|--field|\n"
" -x|--extract|-X|--vextract|--fsys-tarfile  on archives (type %s --help).\n"
"\n"), BACKEND);

  printf(_(
"For internal use: dpkg --assert-support-predepends | --predep-package |\n"
"  --assert-working-epoch | --assert-long-filenames | --assert-multi-conrep |\n"
"  --assert-multi-arch.\n"
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
"  --status-logger=<command>  Send status change updates to <command>'s stdin.\n"
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
"Use 'apt' or 'aptitude' for user-friendly package management.\n"));

  m_output(stdout, _("<standard output>"));

  exit(0);
}

static const char printforhelp[] = N_(
"Type dpkg --help for help about installing and deinstalling packages [*];\n"
"Use 'apt' or 'aptitude' for user-friendly package management;\n"
"Type dpkg -Dhelp for a list of dpkg debug flag values;\n"
"Type dpkg --force-help for a list of forcing options;\n"
"Type dpkg-deb --help for help about manipulating *.deb files;\n"
"\n"
"Options marked [*] produce a lot of output - pipe it through 'less' or 'more' !");

int f_pending=0, f_recursive=0, f_alsoselect=1, f_skipsame=0, f_noact=0;
int f_autodeconf=0, f_nodebsig=0;
int f_triggers = 0;
int fc_downgrade=1, fc_configureany=0, fc_hold=0, fc_removereinstreq=0, fc_overwrite=0;
int fc_removeessential=0, fc_conflicts=0, fc_depends=0, fc_dependsversion=0;
int fc_breaks=0, fc_badpath=0, fc_overwritediverted=0, fc_architecture=0;
int fc_nonroot=0, fc_overwritedir=0, fc_conff_new=0, fc_conff_miss=0;
int fc_conff_old=0, fc_conff_def=0;
int fc_conff_ask = 0;
int fc_unsafe_io = 0;
int fc_badverify = 0;
int fc_badversion = 0;

int errabort = 50;
static const char *admindir = ADMINDIR;
const char *instdir= "";
struct pkg_list *ignoredependss = NULL;

static const char *
forcetype_str(char type)
{
  switch (type) {
  case '\0':
  case ' ':
    return "   ";
  case '*':
    return "[*]";
  case '!':
    return "[!]";
  default:
    internerr("unknown force type '%c'", type);
  }
}

static const struct forceinfo {
  const char *name;
  int *opt;
  char type;
  const char *desc;
} forceinfos[]= {
  { "all",                 NULL,
    '!', N_("Set all force options")},
  { "downgrade",           &fc_downgrade,
    '*', N_("Replace a package with a lower version") },
  { "configure-any",       &fc_configureany,
    ' ', N_("Configure any package which may help this one") },
  { "hold",                &fc_hold,
    ' ', N_("Process incidental packages even when on hold") },
  { "not-root",            &fc_nonroot,
    ' ', N_("Try to (de)install things even when not root") },
  { "bad-path",            &fc_badpath,
    ' ', N_("PATH is missing important programs, problems likely") },
  { "bad-verify",          &fc_badverify,
    ' ', N_("Install a package even if it fails authenticity check") },
  { "bad-version",         &fc_badversion,
    ' ', N_("Process even packages with wrong versions") },
  { "overwrite",           &fc_overwrite,
    ' ', N_("Overwrite a file from one package with another") },
  { "overwrite-diverted",  &fc_overwritediverted,
    ' ', N_("Overwrite a diverted file with an undiverted version") },
  { "overwrite-dir",       &fc_overwritedir,
    '!', N_("Overwrite one package's directory with another's file") },
  { "unsafe-io",           &fc_unsafe_io,
    '!', N_("Do not perform safe I/O operations when unpacking") },
  { "confnew",             &fc_conff_new,
    '!', N_("Always use the new config files, don't prompt") },
  { "confold",             &fc_conff_old,
    '!', N_("Always use the old config files, don't prompt") },
  /* XXX: Handle automatically line wrappings. */
  { "confdef",             &fc_conff_def,
    '!', N_("Use the default option for new config files if one\n"
"                         is available, don't prompt. If no default can be found,\n"
"                         you will be prompted unless one of the confold or\n"
"                         confnew options is also given") },
  { "confmiss",            &fc_conff_miss,
    '!', N_("Always install missing config files") },
  { "confask",             &fc_conff_ask,
    '!', N_("Offer to replace config files with no new versions") },
  { "architecture",        &fc_architecture,
    '!', N_("Process even packages with wrong or no architecture") },
  { "breaks",              &fc_breaks,
    '!', N_("Install even if it would break another package") },
  { "conflicts",           &fc_conflicts,
    '!', N_("Allow installation of conflicting packages") },
  { "depends",             &fc_depends,
    '!', N_("Turn all dependency problems into warnings") },
  { "depends-version",     &fc_dependsversion,
    '!', N_("Turn dependency version problems into warnings") },
  { "remove-reinstreq",    &fc_removereinstreq,
    '!', N_("Remove packages which require installation") },
  { "remove-essential",    &fc_removeessential,
    '!', N_("Remove an essential package") },
  { NULL }
};

#define DBG_DEF(n, d) \
  { .flag = dbg_##n, .name = #n, .desc = d }

static const struct debuginfo {
  int flag;
  const char *name;
  const char *desc;
} debuginfos[] = {
  DBG_DEF(general,         N_("Generally helpful progress information")),
  DBG_DEF(scripts,         N_("Invocation and status of maintainer scripts")),
  DBG_DEF(eachfile,        N_("Output for each file processed")),
  DBG_DEF(eachfiledetail,  N_("Lots of output for each file processed")),
  DBG_DEF(conff,           N_("Output for each configuration file")),
  DBG_DEF(conffdetail,     N_("Lots of output for each configuration file")),
  DBG_DEF(depcon,          N_("Dependencies and conflicts")),
  DBG_DEF(depcondetail,    N_("Lots of dependencies/conflicts output")),
  DBG_DEF(triggers,        N_("Trigger activation and processing")),
  DBG_DEF(triggersdetail,  N_("Lots of output regarding triggers")),
  DBG_DEF(triggersstupid,  N_("Silly amounts of output regarding triggers")),
  DBG_DEF(veryverbose,     N_("Lots of drivel about eg the dpkg/info directory")),
  DBG_DEF(stupidlyverbose, N_("Insane amounts of drivel")),
  { 0, NULL, NULL }
};

static void setdebug(const struct cmdinfo *cpi, const char *value) {
  char *endp;
  long mask;
  const struct debuginfo *dip;

  if (*value == 'h') {
    printf(_(
"%s debugging option, --debug=<octal> or -D<octal>:\n"
"\n"
" Number  Ref. in source   Description\n"), DPKG);

    for (dip = debuginfos; dip->name; dip++)
      printf(" %6o  %-16s %s\n", dip->flag, dip->name, gettext(dip->desc));

    printf(_("\n"
"Debugging options can be mixed using bitwise-or.\n"
"Note that the meanings and values are subject to change.\n"));
    m_output(stdout, _("<standard output>"));
    exit(0);
  }

  errno = 0;
  mask = strtol(value, &endp, 8);
  if (value == endp || *endp || mask < 0 || errno == ERANGE)
    badusage(_("--%s requires a positive octal argument"), cpi->olong);

  debug_set_mask(mask);
}

static void
setfilter(const struct cmdinfo *cip, const char *value)
{
  filter_add(value, cip->arg_int);
}

static void setroot(const struct cmdinfo *cip, const char *value) {
  char *p;
  instdir= value;
  m_asprintf(&p, "%s%s", value, ADMINDIR);
  admindir= p;
}

static void ignoredepends(const struct cmdinfo *cip, const char *value) {
  char *copy, *p;

  copy= m_malloc(strlen(value)+2);
  strcpy(copy,value);
  copy[strlen(value) + 1] = '\0';
  for (p=copy; *p; p++) {
    if (*p != ',') continue;
    *p++ = '\0';
    if (!*p || *p==',' || p==copy+1)
      badusage(_("null package name in --%s comma-separated list '%.250s'"),
               cip->olong, value);
  }
  p= copy;
  while (*p) {
    struct dpkg_error err;
    struct pkginfo *pkg;

    pkg = pkg_spec_parse_pkg(p, &err);
    if (pkg == NULL)
      ohshit(_("--%s needs a valid package name but '%.250s' is not: %s"),
              cip->olong, p, err.str);

    pkg_list_prepend(&ignoredependss, pkg);

    p+= strlen(p)+1;
  }

  free(copy);
}

static void setinteger(const struct cmdinfo *cip, const char *value) {
  long v;
  char *ep;

  errno = 0;
  v = strtol(value, &ep, 0);
  if (value == ep || *ep || v < 0 || v > INT_MAX || errno != 0)
    badusage(_("invalid integer for --%s: `%.250s'"),cip->olong,value);
  *cip->iassignto= v;
}

static void setpipe(const struct cmdinfo *cip, const char *value) {
  long v;
  char *ep;

  errno = 0;
  v = strtol(value, &ep, 0);
  if (value == ep || *ep || v < 0 || v > INT_MAX || errno != 0)
    badusage(_("invalid integer for --%s: `%.250s'"),cip->olong,value);

  statusfd_add(v);
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
struct invoke_hook *status_loggers = NULL;
struct invoke_hook **status_loggers_tail = &status_loggers;

static void
set_invoke_hook(const struct cmdinfo *cip, const char *value)
{
  struct invoke_hook ***hook_tail = cip->arg_ptr;
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

static void
run_status_loggers(struct invoke_hook *hook_head)
{
  struct invoke_hook *hook;

  for (hook = hook_head; hook; hook = hook->next) {
    pid_t pid;
    int p[2];

    m_pipe(p);

    pid = subproc_fork();
    if (pid == 0) {
      /* Setup stdin and stdout. */
      m_dup2(p[0], 0);
      close(1);

      close(p[0]);
      close(p[1]);

      command_shell(hook->command, _("status logger"));
    }
    close(p[0]);

    statusfd_add(p[1]);
  }
}

static int
arch_add(const char *const *argv)
{
  struct dpkg_arch *arch;
  const char *archname = *argv++;

  if (archname == NULL)
    badusage(_("--%s takes one argument"), cipaction->olong);

  dpkg_arch_load_list();

  arch = dpkg_arch_add(archname);
  switch (arch->type) {
  case arch_native:
  case arch_foreign:
    break;
  case arch_illegal:
    ohshit(_("architecture '%s' is illegal: %s"), archname,
           dpkg_arch_name_is_illegal(archname));
  default:
    ohshit(_("architecture '%s' is reserved and cannot be added"), archname);
  }

  dpkg_arch_save_list();

  return 0;
}

static int
arch_remove(const char *const *argv)
{
  const char *archname = *argv++;
  struct dpkg_arch *arch;
  struct pkgiterator *iter;
  struct pkginfo *pkg;

  if (archname == NULL)
    badusage(_("--%s takes one argument"), cipaction->olong);

  modstatdb_open(msdbrw_readonly);

  arch = dpkg_arch_find(archname);
  if (arch->type != arch_foreign) {
    warning(_("cannot remove non-foreign architecture '%s'"), arch->name);
    return 0;
  }

  /* Check if it's safe to remove the architecture from the db. */
  iter = pkg_db_iter_new();
  while ((pkg = pkg_db_iter_next_pkg(iter))) {
    if (pkg->status < stat_halfinstalled)
      continue;
    if (pkg->installed.arch == arch) {
      if (fc_architecture)
        warning(_("removing architecture '%s' currently in use by database"),
                arch->name);
      else
        ohshit(_("cannot remove architecture '%s' currently in use by the database"),
               arch->name);
      break;
    }
  }
  pkg_db_iter_free(iter);

  dpkg_arch_unmark(arch);
  dpkg_arch_save_list();

  modstatdb_shutdown();

  return 0;
}

static void setforce(const struct cmdinfo *cip, const char *value) {
  const char *comma;
  size_t l;
  const struct forceinfo *fip;

  if (strcmp(value, "help") == 0) {
    printf(_(
"%s forcing options - control behaviour when problems found:\n"
"  warn but continue:  --force-<thing>,<thing>,...\n"
"  stop with error:    --refuse-<thing>,<thing>,... | --no-force-<thing>,...\n"
" Forcing things:\n"), DPKG);

    for (fip = forceinfos; fip->name; fip++)
      printf("  %s %-18s %s\n", forcetype_str(fip->type), fip->name,
             gettext(fip->desc));

    printf(_(
"\n"
"WARNING - use of options marked [!] can seriously damage your installation.\n"
"Forcing options marked [*] are enabled by default.\n"));
    m_output(stdout, _("<standard output>"));
    exit(0);
  }

  for (;;) {
    comma= strchr(value,',');
    l = comma ? (size_t)(comma - value) : strlen(value);
    for (fip=forceinfos; fip->name; fip++)
      if (strncmp(fip->name, value, l) == 0 && strlen(fip->name) == l)
        break;

    if (!fip->name) {
      badusage(_("unknown force/refuse option `%.*s'"),
               (int)min(l, 250), value);
    } else if (strcmp(fip->name, "all") == 0) {
      for (fip = forceinfos; fip->name; fip++)
        if (fip->opt)
          *fip->opt = cip->arg_int;
    } else if (fip->opt) {
      *fip->opt = cip->arg_int;
    } else {
      warning(_("obsolete force/refuse option '%s'\n"), fip->name);
    }

    if (!comma) break;
    value= ++comma;
  }
}

int execbackend(const char *const *argv) DPKG_ATTR_NORET;
int commandfd(const char *const *argv);

/* This table has both the action entries in it and the normal options.
 * The action entries are made with the ACTION macro, as they all
 * have a very similar structure. */
static const struct cmdinfo cmdinfos[]= {
#define ACTIONBACKEND(longopt, shortopt, backend) \
 { longopt, shortopt, 0, NULL, NULL, setaction, 0, (void *)backend, execbackend }

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
  ACTION( "assert-multi-arch",               0,  act_assertmultiarch,      assertmultiarch ),
  ACTION( "add-architecture",                0,  act_arch_add,             arch_add        ),
  ACTION( "remove-architecture",             0,  act_arch_remove,          arch_remove     ),
  ACTION( "print-architecture",              0,  act_printarch,            printarch   ),
  ACTION( "print-installation-architecture", 0,  act_printinstarch,        printinstarch  ),
  ACTION( "print-foreign-architectures",     0,  act_printforeignarches,   print_foreign_arches ),
  ACTION( "predep-package",                  0,  act_predeppackage,        predeppackage   ),
  ACTION( "compare-versions",                0,  act_cmpversions,          cmpversions     ),
/*
  ACTION( "command-fd",                   'c', act_commandfd,   commandfd     ),
*/

  { "pre-invoke",        0,   1, NULL,          NULL,      set_invoke_hook, 0, &pre_invoke_hooks_tail },
  { "post-invoke",       0,   1, NULL,          NULL,      set_invoke_hook, 0, &post_invoke_hooks_tail },
  { "path-exclude",      0,   1, NULL,          NULL,      setfilter,     0 },
  { "path-include",      0,   1, NULL,          NULL,      setfilter,     1 },
  { "status-logger",     0,   1, NULL,          NULL,      set_invoke_hook, 0, &status_loggers_tail },
  { "status-fd",         0,   1, NULL,          NULL,      setpipe, 0 },
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
  { "help",              '?', 0, NULL,          NULL,      usage,         0 },
  { "version",           0,   0, NULL,          NULL,      printversion,  0 },
  ACTIONBACKEND( "build",		'b', BACKEND),
  ACTIONBACKEND( "contents",		'c', BACKEND),
  ACTIONBACKEND( "control",		'e', BACKEND),
  ACTIONBACKEND( "info",		'I', BACKEND),
  ACTIONBACKEND( "field",		'f', BACKEND),
  ACTIONBACKEND( "extract",		'x', BACKEND),
  ACTIONBACKEND( "vextract",		'X', BACKEND),
  ACTIONBACKEND( "fsys-tarfile",	0,   BACKEND),
  { NULL,                0,   0, NULL,          NULL,      NULL,          0 }
};

int
execbackend(const char *const *argv)
{
  struct command cmd;
  char *arg;

  command_init(&cmd, cipaction->arg_ptr, NULL);
  command_add_arg(&cmd, cipaction->arg_ptr);

  m_asprintf(&arg, "--%s", cipaction->olong);
  command_add_arg(&cmd, arg);

  /* Exlicitely separate arguments from options as any user-supplied
   * separator got stripped by the option parser */
  command_add_arg(&cmd, "--");
  command_add_argl(&cmd, (const char **)argv);

  command_exec(&cmd);
}

int
commandfd(const char *const *argv)
{
  struct varbuf linevb = VARBUF_INIT;
  const char * pipein;
  const char **newargs = NULL;
  char *ptr, *endptr;
  FILE *in;
  long infd;
  int ret = 0;
  int c, lno, i;
  bool skipchar;

  pipein = *argv++;
  if (pipein == NULL || *argv)
    badusage(_("--%s takes exactly one argument"), cipaction->olong);
  errno = 0;
  infd = strtol(pipein, &endptr, 10);
  if (pipein == endptr || *endptr || infd < 0 || infd > INT_MAX || errno != 0)
    ohshit(_("invalid integer for --%s: `%.250s'"), cipaction->olong, pipein);
  in = fdopen(infd, "r");
  if (in == NULL)
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
    varbuf_reset(&linevb);
    do {
      varbuf_add_char(&linevb, c);
      c= getc(in);
      if (c == '\n') lno++;

      /* This isn't fully accurate, but overestimating can't hurt. */
      if (isspace(c))
        argc++;
    } while (c != EOF && c != '\n');
    if (c == EOF) ohshit(_("unexpected eof before end of line %d"),lno);
    if (!argc) continue;
    varbuf_end_str(&linevb);
    newargs = m_realloc(newargs, sizeof(const char *) * (argc + 1));
    argc= 1;
    ptr= linevb.buf;
    endptr = ptr + linevb.used + 1;
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

    /* We strdup() each argument, but never free it, because the
     * error messages contain references back to these strings.
     * Freeing them, and reusing the memory, would make those
     * error messages confusing, to say the least. */
    for(i=1;i<argc;i++)
      if (newargs[i])
        newargs[i] = m_strdup(newargs[i]);

    setaction(NULL, NULL);
    myopt((const char *const **)&newargs, cmdinfos, printforhelp);
    if (!cipaction) badusage(_("need an action option"));

    ret |= cipaction->action(newargs);

    pop_error_context(ehflag_normaltidy);
  }

  return ret;
}

int main(int argc, const char *const *argv) {
  int ret;

  setlocale(LC_ALL, "");
  bindtextdomain(PACKAGE, LOCALEDIR);
  textdomain(PACKAGE);

  dpkg_set_progname("dpkg");
  standard_startup();
  loadcfgfile(DPKG, cmdinfos);
  myopt(&argv, cmdinfos, printforhelp);

  if (!cipaction) badusage(_("need an action option"));

  admindir = dpkg_db_set_dir(admindir);

  /* Always set environment, to avoid possible security risks. */
  if (setenv("DPKG_ADMINDIR", admindir, 1) < 0)
    ohshite(_("unable to setenv for subprocesses"));

  if (!f_triggers)
    f_triggers = (cipaction->arg_int == act_triggers && *argv) ? -1 : 1;

  setvbuf(stdout, NULL, _IONBF, 0);

  if (is_invoke_action(cipaction->arg_int)) {
    run_invoke_hooks(cipaction->olong, pre_invoke_hooks);
    run_status_loggers(status_loggers);
  }

  filesdbinit();

  ret = cipaction->action(argv);

  if (is_invoke_action(cipaction->arg_int))
    run_invoke_hooks(cipaction->olong, post_invoke_hooks);

  standard_shutdown();

  return reportbroken_retexitstatus(ret);
}
