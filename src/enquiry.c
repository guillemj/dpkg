/*
 * dpkg - main program for package management
 * enquiry.c - status enquiry and listing options
 *
 * Copyright © 1995,1996 Ian Jackson <ian@chiark.greenend.org.uk>
 * Copyright © 2006,2008-2012 Guillem Jover <guillem@debian.org>
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

/* FIXME: per-package audit. */

#include <config.h>
#include <compat.h>

#include <sys/types.h>

#include <assert.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>
#include <dpkg/arch.h>
#include <dpkg/pkg-show.h>
#include <dpkg/string.h>
#include <dpkg/options.h>

#include "filesdb.h"
#include "infodb.h"
#include "main.h"

struct badstatinfo {
  bool (*yesno)(struct pkginfo *, const struct badstatinfo *bsi);
  union {
    int number;
    const char *string;
  } value;
  const char *explanation;
};

static bool
bsyn_reinstreq(struct pkginfo *pkg, const struct badstatinfo *bsi)
{
  return pkg->eflag & eflag_reinstreq;
}

static bool
bsyn_status(struct pkginfo *pkg, const struct badstatinfo *bsi)
{
  if (pkg->eflag & eflag_reinstreq)
    return false;
  return (int)pkg->status == bsi->value.number;
}

static bool
bsyn_infofile(struct pkginfo *pkg, const struct badstatinfo *bsi)
{
  if (pkg->status < stat_halfinstalled)
    return false;
  return !pkg_infodb_has_file(pkg, &pkg->installed, bsi->value.string);
}

static bool
bsyn_arch(struct pkginfo *pkg, const struct badstatinfo *bsi)
{
  if (pkg->status < stat_halfinstalled)
    return false;
  return pkg->installed.arch->type == (enum dpkg_arch_type)bsi->value.number;
}

static const struct badstatinfo badstatinfos[]= {
  {
    .yesno = bsyn_reinstreq,
    .value.number = 0,
    .explanation = N_(
    "The following packages are in a mess due to serious problems during\n"
    "installation.  They must be reinstalled for them (and any packages\n"
    "that depend on them) to function properly:\n")
  }, {
    .yesno = bsyn_status,
    .value.number = stat_unpacked,
    .explanation = N_(
    "The following packages have been unpacked but not yet configured.\n"
    "They must be configured using dpkg --configure or the configure\n"
    "menu option in dselect for them to work:\n")
  }, {
    .yesno = bsyn_status,
    .value.number = stat_halfconfigured,
    .explanation = N_(
    "The following packages are only half configured, probably due to problems\n"
    "configuring them the first time.  The configuration should be retried using\n"
    "dpkg --configure <package> or the configure menu option in dselect:\n")
  }, {
    .yesno = bsyn_status,
    .value.number = stat_halfinstalled,
    .explanation = N_(
    "The following packages are only half installed, due to problems during\n"
    "installation.  The installation can probably be completed by retrying it;\n"
    "the packages can be removed using dselect or dpkg --remove:\n")
  }, {
    .yesno = bsyn_status,
    .value.number = stat_triggersawaited,
    .explanation = N_(
    "The following packages are awaiting processing of triggers that they\n"
    "have activated in other packages.  This processing can be requested using\n"
    "dselect or dpkg --configure --pending (or dpkg --triggers-only):\n")
  }, {
    .yesno = bsyn_status,
    .value.number = stat_triggerspending,
    .explanation = N_(
    "The following packages have been triggered, but the trigger processing\n"
    "has not yet been done.  Trigger processing can be requested using\n"
    "dselect or dpkg --configure --pending (or dpkg --triggers-only):\n")
  }, {
    .yesno = bsyn_infofile,
    .value.string = LISTFILE,
    .explanation = N_(
    "The following packages are missing the list control file in the\n"
    "database, they need to be reinstalled:\n")
  }, {
    .yesno = bsyn_infofile,
    .value.string = HASHFILE,
    .explanation = N_(
    "The following packages are missing the md5sums control file in the\n"
    "database, they need to be reinstalled:\n")
  }, {
    .yesno = bsyn_arch,
    .value.number = arch_none,
    .explanation = N_("The following packages do not have an architecture:\n")
  }, {
    .yesno = bsyn_arch,
    .value.number = arch_illegal,
    .explanation = N_("The following packages have an illegal architecture:\n")
  }, {
    .yesno = bsyn_arch,
    .value.number = arch_unknown,
    .explanation = N_(
    "The following packages have an unknown foreign architecture, which will\n"
    "cause dependency issues on front-ends. This can be fixed by registering\n"
    "the foreign architecture with dpkg --add-architecture:\n")
  }, {
    .yesno = NULL
  }
};

static void describebriefly(struct pkginfo *pkg) {
  int maxl, l;
  const char *pdesc;

  maxl= 57;
  l= strlen(pkg->set->name);
  if (l>20) maxl -= (l-20);

  pdesc = pkg_summary(pkg, &pkg->installed, &l);
  l = min(l, maxl);

  printf(" %-20s %.*s\n", pkg_name(pkg, pnaw_nonambig), l, pdesc);
}

int
audit(const char *const *argv)
{
  const struct badstatinfo *bsi;
  bool head_running = false;

  if (*argv)
    badusage(_("--%s takes no arguments"), cipaction->olong);

  modstatdb_open(msdbrw_readonly);

  for (bsi= badstatinfos; bsi->yesno; bsi++) {
    struct pkgiterator *it;
    struct pkginfo *pkg;
    bool head = false;

    it = pkg_db_iter_new();
    while ((pkg = pkg_db_iter_next_pkg(it))) {
      if (!bsi->yesno(pkg,bsi)) continue;
      if (!head_running) {
        if (modstatdb_is_locked())
          puts(_(
"Another process has locked the database for writing, and might currently be\n"
"modifying it, some of the following problems might just be due to that.\n"));
        head_running = true;
      }
      if (!head) {
        fputs(gettext(bsi->explanation),stdout);
        head = true;
      }
      describebriefly(pkg);
    }
    pkg_db_iter_free(it);
    if (head) putchar('\n');
  }

  m_output(stdout, _("<standard output>"));

  return 0;
}

struct sectionentry {
  struct sectionentry *next;
  const char *name;
  int count;
};

static bool
yettobeunpacked(struct pkginfo *pkg, const char **thissect)
{
  if (pkg->want != want_install)
    return false;

  switch (pkg->status) {
  case stat_unpacked: case stat_installed: case stat_halfconfigured:
  case stat_triggerspending:
  case stat_triggersawaited:
    return false;
  case stat_notinstalled: case stat_halfinstalled: case stat_configfiles:
    if (thissect)
      *thissect = str_is_set(pkg->section) ? pkg->section :
                                             C_("section", "<unknown>");
    return true;
  default:
    internerr("unknown package status '%d'", pkg->status);
  }
  return false;
}

int
unpackchk(const char *const *argv)
{
  int totalcount, sects;
  struct sectionentry *sectionentries, *se, **sep;
  struct pkgiterator *it;
  struct pkginfo *pkg;
  const char *thissect;
  char buf[20];
  int width;

  if (*argv)
    badusage(_("--%s takes no arguments"), cipaction->olong);

  modstatdb_open(msdbrw_readonly);

  totalcount= 0;
  sectionentries = NULL;
  sects= 0;
  it = pkg_db_iter_new();
  while ((pkg = pkg_db_iter_next_pkg(it))) {
    if (!yettobeunpacked(pkg, &thissect)) continue;
    for (se= sectionentries; se && strcasecmp(thissect,se->name); se= se->next);
    if (!se) {
      se= nfmalloc(sizeof(struct sectionentry));
      for (sep= &sectionentries;
           *sep && strcasecmp(thissect,(*sep)->name) > 0;
           sep= &(*sep)->next);
      se->name= thissect;
      se->count= 0;
      se->next= *sep;
      *sep= se;
      sects++;
    }
    se->count++; totalcount++;
  }
  pkg_db_iter_free(it);

  if (totalcount == 0)
    return 0;

  if (totalcount <= 12) {
    it = pkg_db_iter_new();
    while ((pkg = pkg_db_iter_next_pkg(it))) {
      if (!yettobeunpacked(pkg, NULL))
        continue;
      describebriefly(pkg);
    }
    pkg_db_iter_free(it);
  } else if (sects <= 12) {
    for (se= sectionentries; se; se= se->next) {
      sprintf(buf,"%d",se->count);
      printf(_(" %d in %s: "),se->count,se->name);
      width= 70-strlen(se->name)-strlen(buf);
      while (width > 59) { putchar(' '); width--; }
      it = pkg_db_iter_new();
      while ((pkg = pkg_db_iter_next_pkg(it))) {
        const char *pkgname;

        if (!yettobeunpacked(pkg,&thissect)) continue;
        if (strcasecmp(thissect,se->name)) continue;
        pkgname = pkg_name(pkg, pnaw_nonambig);
        width -= strlen(pkgname);
        width--;
        if (width < 4) { printf(" ..."); break; }
        printf(" %s", pkgname);
      }
      pkg_db_iter_free(it);
      putchar('\n');
    }
  } else {
    printf(P_(" %d package, from the following section:",
              " %d packages, from the following sections:", totalcount),
           totalcount);
    width= 0;
    for (se= sectionentries; se; se= se->next) {
      sprintf(buf,"%d",se->count);
      width -= (6 + strlen(se->name) + strlen(buf));
      if (width < 0) { putchar('\n'); width= 73 - strlen(se->name) - strlen(buf); }
      printf("   %s (%d)",se->name,se->count);
    }
    putchar('\n');
  }

  m_output(stdout, _("<standard output>"));

  return 0;
}

static int
assert_version_support(const char *const *argv,
                       struct dpkg_version *version,
                       const char *feature_name)
{
  struct pkginfo *pkg;

  if (*argv)
    badusage(_("--%s takes no arguments"), cipaction->olong);

  modstatdb_open(msdbrw_readonly);

  pkg = pkg_db_find_singleton("dpkg");
  switch (pkg->status) {
  case stat_installed:
  case stat_triggerspending:
    return 0;
  case stat_unpacked: case stat_halfconfigured: case stat_halfinstalled:
  case stat_triggersawaited:
    if (dpkg_version_relate(&pkg->configversion, dpkg_relation_ge, version))
      return 0;
    printf(_("Version of dpkg with working %s support not yet configured.\n"
             " Please use 'dpkg --configure dpkg', and then try again.\n"),
           feature_name);
    return 1;
  default:
    printf(_("dpkg not recorded as installed, cannot check for %s support!\n"),
           feature_name);
    return 1;
  }
}

int
assertpredep(const char *const *argv)
{
  struct dpkg_version version = { 0, "1.1.0", NULL };

  return assert_version_support(argv, &version, _("Pre-Depends field"));
}

int
assertepoch(const char *const *argv)
{
  struct dpkg_version version = { 0, "1.4.0.7", NULL };

  return assert_version_support(argv, &version, _("epoch"));
}

int
assertlongfilenames(const char *const *argv)
{
  struct dpkg_version version = { 0, "1.4.1.17", NULL };

  return assert_version_support(argv, &version, _("long filenames"));
}

int
assertmulticonrep(const char *const *argv)
{
  struct dpkg_version version = { 0, "1.4.1.19", NULL };

  return assert_version_support(argv, &version,
                                _("multiple Conflicts and Replaces"));
}

int
assertmultiarch(const char *const *argv)
{
  struct dpkg_version version = { 0, "1.16.2", NULL };

  return assert_version_support(argv, &version, _("multi-arch"));
}

/**
 * Print a single package which:
 *  (a) is the target of one or more relevant predependencies.
 *  (b) has itself no unsatisfied pre-dependencies.
 *
 * If such a package is present output is the Packages file entry,
 * which can be massaged as appropriate.
 *
 * Exit status:
 *  0 = a package printed, OK
 *  1 = no suitable package available
 *  2 = error
 */
int
predeppackage(const char *const *argv)
{
  static struct varbuf vb;

  struct pkgiterator *it;
  struct pkginfo *pkg = NULL, *startpkg, *trypkg;
  struct dependency *dep;
  struct deppossi *possi, *provider;

  if (*argv)
    badusage(_("--%s takes no arguments"), cipaction->olong);

  modstatdb_open(msdbrw_readonly | msdbrw_available_readonly);
  /* We use clientdata->istobe to detect loops. */
  clear_istobes();

  dep = NULL;
  it = pkg_db_iter_new();
  while (!dep && (pkg = pkg_db_iter_next_pkg(it))) {
    /* Ignore packages user doesn't want. */
    if (pkg->want != want_install)
      continue;
    /* Ignore packages not available. */
    if (!pkg->files)
      continue;
    pkg->clientdata->istobe= itb_preinstall;
    for (dep= pkg->available.depends; dep; dep= dep->next) {
      if (dep->type != dep_predepends) continue;
      if (depisok(dep, &vb, NULL, NULL, true))
        continue;
      /* This will leave dep non-NULL, and so exit the loop. */
      break;
    }
    pkg->clientdata->istobe= itb_normal;
    /* If dep is NULL we go and get the next package. */
  }
  pkg_db_iter_free(it);

  if (!dep)
    return 1; /* Not found. */
  assert(pkg);
  startpkg= pkg;
  pkg->clientdata->istobe= itb_preinstall;

  /* OK, we have found an unsatisfied predependency.
   * Now go and find the first thing we need to install, as a first step
   * towards satisfying it. */
  do {
    /* We search for a package which would satisfy dep, and put it in pkg. */
    for (possi = dep->list, pkg = NULL;
         !pkg && possi;
         possi=possi->next) {
      struct deppossi_pkg_iterator *possi_iter;

      possi_iter = deppossi_pkg_iter_new(possi, wpb_available);
      while (!pkg && (trypkg = deppossi_pkg_iter_next(possi_iter))) {
        if (trypkg->files && trypkg->clientdata->istobe == itb_normal &&
            versionsatisfied(&trypkg->available, possi)) {
          pkg = trypkg;
          break;
        }
        if (possi->verrel != dpkg_relation_none)
          continue;
        for (provider = possi->ed->depended.available;
             !pkg && provider;
             provider = provider->next) {
          if (provider->up->type != dep_provides)
            continue;
          trypkg = provider->up->up;
          if (!trypkg->files)
            continue;
          if (trypkg->clientdata->istobe == itb_normal) {
            pkg = trypkg;
            break;
          }
        }
      }
      deppossi_pkg_iter_free(possi_iter);
    }
    if (!pkg) {
      varbuf_reset(&vb);
      describedepcon(&vb,dep);
      varbuf_end_str(&vb);
      notice(_("cannot see how to satisfy pre-dependency:\n %s"), vb.buf);
      ohshit(_("cannot satisfy pre-dependencies for %.250s (wanted due to %.250s)"),
             pkgbin_name(dep->up, &dep->up->available, pnaw_nonambig),
             pkgbin_name(startpkg, &startpkg->available, pnaw_nonambig));
    }
    pkg->clientdata->istobe= itb_preinstall;
    for (dep= pkg->available.depends; dep; dep= dep->next) {
      if (dep->type != dep_predepends) continue;
      if (depisok(dep, &vb, NULL, NULL, true))
        continue;
      /* This will leave dep non-NULL, and so exit the loop. */
      break;
    }
  } while (dep);

  /* OK, we've found it - pkg has no unsatisfied pre-dependencies! */
  writerecord(stdout, _("<standard output>"), pkg, &pkg->available);

  m_output(stdout, _("<standard output>"));

  return 0;
}

int
printarch(const char *const *argv)
{
  if (*argv)
    badusage(_("--%s takes no arguments"), cipaction->olong);

  printf("%s\n", dpkg_arch_get(arch_native)->name);

  m_output(stdout, _("<standard output>"));

  return 0;
}

int
printinstarch(const char *const *argv)
{
  warning(_("obsolete option '--%s'; please use '--%s' instead"),
          "print-installation-architecture", "print-architecture");
  return printarch(argv);
}

int
print_foreign_arches(const char *const *argv)
{
  struct dpkg_arch *arch;

  if (*argv)
    badusage(_("--%s takes no arguments"), cipaction->olong);

  dpkg_arch_load_list();

  for (arch = dpkg_arch_get_list(); arch; arch = arch->next) {
    if (arch->type != arch_foreign)
      continue;

    printf("%s\n", arch->name);
  }

  m_output(stdout, _("<standard output>"));

  return 0;
}

int
cmpversions(const char *const *argv)
{
  struct relationinfo {
    const char *string;
    /* These values are exit status codes, so 0 = true, 1 = false. */
    int if_lesser, if_equal, if_greater;
    int if_none_a, if_none_both, if_none_b;
  };

  static const struct relationinfo relationinfos[]= {
    /*             < = > !a!2!b  */
    { "le",        0,0,1, 0,0,1  },
    { "lt",        0,1,1, 0,1,1  },
    { "eq",        1,0,1, 1,0,1  },
    { "ne",        0,1,0, 0,1,0  },
    { "ge",        1,0,0, 1,0,0  },
    { "gt",        1,1,0, 1,1,0  },

    /* These treat an empty version as later than any version. */
    { "le-nl",     0,0,1, 1,0,0  },
    { "lt-nl",     0,1,1, 1,1,0  },
    { "ge-nl",     1,0,0, 0,0,1  },
    { "gt-nl",     1,1,0, 0,1,1  },

    /* For compatibility with dpkg control file syntax. */
    { "<",         0,0,1, 0,0,1  },
    { "<=",        0,0,1, 0,0,1  },
    { "<<",        0,1,1, 0,1,1  },
    { "=",         1,0,1, 1,0,1  },
    { ">",         1,0,0, 1,0,0  },
    { ">=",        1,0,0, 1,0,0  },
    { ">>",        1,1,0, 1,1,0  },
    { NULL                       }
  };

  const struct relationinfo *rip;
  struct dpkg_version a, b;
  struct dpkg_error err;
  int r;

  if (!argv[0] || !argv[1] || !argv[2] || argv[3])
    badusage(_("--compare-versions takes three arguments:"
             " <version> <relation> <version>"));

  for (rip=relationinfos; rip->string && strcmp(rip->string,argv[1]); rip++);

  if (!rip->string) badusage(_("--compare-versions bad relation"));

  if (*argv[0] && strcmp(argv[0],"<unknown>")) {
    if (parseversion(&a, argv[0], &err) < 0) {
      if (err.type == DPKG_MSG_WARN)
        warning(_("version '%s' has bad syntax: %s"), argv[0], err.str);
      else
        ohshit(_("version '%s' has bad syntax: %s"), argv[0], err.str);
      dpkg_error_destroy(&err);
    }
  } else {
    dpkg_version_blank(&a);
  }
  if (*argv[2] && strcmp(argv[2],"<unknown>")) {
    if (parseversion(&b, argv[2], &err) < 0) {
      if (err.type == DPKG_MSG_WARN)
        warning(_("version '%s' has bad syntax: %s"), argv[2], err.str);
      else
        ohshit(_("version '%s' has bad syntax: %s"), argv[2], err.str);
      dpkg_error_destroy(&err);
    }
  } else {
    dpkg_version_blank(&b);
  }
  if (!dpkg_version_is_informative(&a)) {
    if (dpkg_version_is_informative(&b))
      return rip->if_none_a;
    else
      return rip->if_none_both;
  } else if (!dpkg_version_is_informative(&b)) {
    return rip->if_none_b;
  }
  r = dpkg_version_compare(&a, &b);
  debug(dbg_general, "cmpversions a='%s' b='%s' r=%d",
        versiondescribe(&a,vdew_always),
        versiondescribe(&b,vdew_always),
        r);
  if (r > 0)
    return rip->if_greater;
  else if (r < 0)
    return rip->if_lesser;
  else
    return rip->if_equal;
}
