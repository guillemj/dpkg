/*
 * dpkg - main program for package management
 * depcon.c - dependency and conflict checking
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

#include <assert.h>
#include <errno.h>
#include <unistd.h>

#include <dpkg/i18n.h>
#include <dpkg/dpkg.h>
#include <dpkg/dpkg-db.h>

#include "infodb.h"
#include "main.h"

struct cyclesofarlink {
  struct cyclesofarlink *prev;
  struct pkginfo *pkg;
  struct deppossi *possi;
};

static bool findbreakcyclerecursive(struct pkginfo *pkg,
                                    struct cyclesofarlink *sofar);

static bool
foundcyclebroken(struct cyclesofarlink *thislink, struct cyclesofarlink *sofar,
                 struct pkginfo *dependedon, struct deppossi *possi)
{
  struct cyclesofarlink *sol;

  if(!possi)
    return false;

  /* We're investigating the dependency ‘possi’ to see if it
   * is part of a loop. To this end we look to see whether the
   * depended-on package is already one of the packages whose
   * dependencies we're searching. */
  for (sol = sofar; sol && sol->pkg != dependedon; sol = sol->prev);

  /* If not, we do a recursive search on it to see what we find. */
  if (!sol)
    return findbreakcyclerecursive(dependedon, thislink);

  debug(dbg_depcon,"found cycle");
  /* Right, we now break one of the links. We prefer to break
   * a dependency of a package without a postinst script, as
   * this is a null operation. If this is not possible we break
   * the other link in the recursive calling tree which mentions
   * this package (this being the first package involved in the
   * cycle). It doesn't particularly matter which we pick, but if
   * we break the earliest dependency we came across we may be
   * able to do something straight away when findbreakcycle returns. */
  sofar= thislink;
  for (sol = sofar; !(sol != sofar && sol->pkg == dependedon); sol = sol->prev) {
    if (!pkg_infodb_has_file(sol->pkg, POSTINSTFILE))
      break;
  }

  /* Now we have either a package with no postinst, or the other
   * occurrence of the current package in the list. */
  sol->possi->cyclebreak = true;

  debug(dbg_depcon, "cycle broken at %s -> %s",
        sol->possi->up->up->name, sol->possi->ed->name);

  return true;
}

/**
 * Cycle breaking works recursively down the package dependency tree.
 *
 * ‘sofar’ is the list of packages we've descended down already - if we
 * encounter any of its packages again in a dependency we have found a cycle.
 */
static bool
findbreakcyclerecursive(struct pkginfo *pkg, struct cyclesofarlink *sofar)
{
  struct cyclesofarlink thislink, *sol;
  struct dependency *dep;
  struct deppossi *possi, *providelink;
  struct pkginfo *provider;

  if (pkg->clientdata->color == black)
    return false;
  pkg->clientdata->color = gray;

  if (debug_has_flag(dbg_depcondetail)) {
    struct varbuf str_pkgs = VARBUF_INIT;

    for (sol = sofar; sol; sol = sol->prev) {
      varbuf_add_str(&str_pkgs, " <- ");
      varbuf_add_str(&str_pkgs, sol->pkg->name);
    }
    varbuf_end_str(&str_pkgs);
    debug(dbg_depcondetail, "findbreakcyclerecursive %s %s", pkg->name,
          str_pkgs.buf);
    varbuf_destroy(&str_pkgs);
  }
  thislink.pkg= pkg;
  thislink.prev = sofar;
  thislink.possi = NULL;
  for (dep= pkg->installed.depends; dep; dep= dep->next) {
    if (dep->type != dep_depends && dep->type != dep_predepends) continue;
    for (possi= dep->list; possi; possi= possi->next) {
      /* Don't find the same cycles again. */
      if (possi->cyclebreak) continue;
      thislink.possi= possi;
      if (foundcyclebroken(&thislink, sofar, possi->ed,possi))
        return true;
      /* Right, now we try all the providers ... */
      for (providelink= possi->ed->installed.depended;
           providelink;
           providelink = providelink->rev_next) {
        if (providelink->up->type != dep_provides) continue;
        provider= providelink->up->up;
        if (provider->clientdata->istobe == itb_normal) continue;
        /* We don't break things at ‘provides’ links, so ‘possi’ is
         * still the one we use. */
        if (foundcyclebroken(&thislink, sofar, provider, possi))
          return true;
      }
    }
  }
  /* Nope, we didn't find a cycle to break. */
  pkg->clientdata->color = black;
  return false;
}

bool
findbreakcycle(struct pkginfo *pkg)
{
  struct pkgiterator *iter;
  struct pkginfo *tpkg;

  /* Clear the visited flag of all packages before we traverse them. */
  iter = pkg_db_iter_new();
  while ((tpkg = pkg_db_iter_next(iter))) {
    tpkg->clientdata->color = white;
  }
  pkg_db_iter_free(iter);

  return findbreakcyclerecursive(pkg, NULL);
}

void describedepcon(struct varbuf *addto, struct dependency *dep) {
  const char *fmt;
  struct varbuf depstr = VARBUF_INIT;

  switch (dep->type) {
  case dep_depends:
    fmt = _("%s depends on %s");
    break;
  case dep_predepends:
    fmt = _("%s pre-depends on %s");
    break;
  case dep_recommends:
    fmt = _("%s recommends %s");
    break;
  case dep_suggests:
    fmt = _("%s suggests %s");
    break;
  case dep_breaks:
    fmt = _("%s breaks %s");
    break;
  case dep_conflicts:
    fmt = _("%s conflicts with %s");
    break;
  case dep_enhances:
    fmt = _("%s enhances %s");
    break;
  default:
    internerr("unknown deptype '%d'", dep->type);
  }

  varbufdependency(&depstr, dep);
  varbuf_end_str(&depstr);

  varbuf_printf(addto, fmt, dep->up->name, depstr.buf);
  varbuf_destroy(&depstr);
}

/*
 * *whynot must already have been initialized; it need not be
 * empty though - it will be reset before use.
 *
 * If depisok returns false for ‘not OK’ it will contain a description,
 * newline-terminated BUT NOT NUL-TERMINATED, of the reason.
 *
 * If depisok returns true it will contain garbage.
 * allowunconfigd should be non-zero during the ‘Pre-Depends’ checking
 * before a package is unpacked, when it is sufficient for the package
 * to be unpacked provided that both the unpacked and previously-configured
 * versions are acceptable.
 *
 * On false return (‘not OK’), *canfixbyremove refers to a package which
 * if removed (dep_conflicts) or deconfigured (dep_breaks) will fix
 * the problem. Caller may pass NULL for canfixbyremove and need not
 * initialize *canfixbyremove.
 *
 * On false return (‘not OK’), *canfixbytrigaw refers to a package which
 * can fix the problem if all the packages listed in Triggers-Awaited have
 * their triggers processed. Caller may pass NULL for canfixbytrigaw and
 * need not initialize *canfixbytrigaw.
 */
bool
depisok(struct dependency *dep, struct varbuf *whynot,
        struct pkginfo **canfixbyremove, struct pkginfo **canfixbytrigaw,
        bool allowunconfigd)
{
  struct deppossi *possi;
  struct deppossi *provider;
  int nconflicts;

  /* Use this buffer so that when internationalisation comes along we
   * don't have to rewrite the code completely, only redo the sprintf strings
   * (assuming we have the fancy argument-number-specifiers).
   * Allow 250x3 for package names, versions, &c, + 250 for ourselves. */
  char linebuf[1024];

  assert(dep->type == dep_depends || dep->type == dep_predepends ||
	 dep->type == dep_breaks || dep->type == dep_conflicts ||
	 dep->type == dep_recommends || dep->type == dep_suggests ||
	 dep->type == dep_enhances);

  if (canfixbyremove)
    *canfixbyremove = NULL;
  if (canfixbytrigaw)
    *canfixbytrigaw = NULL;

  /* The dependency is always OK if we're trying to remove the depend*ing*
   * package. */
  switch (dep->up->clientdata->istobe) {
  case itb_remove: case itb_deconfigure:
    return true;
  case itb_normal:
    /* Only installed packages can be make dependency problems. */
    switch (dep->up->status) {
    case stat_installed:
    case stat_triggerspending:
    case stat_triggersawaited:
      break;
    case stat_notinstalled: case stat_configfiles: case stat_halfinstalled:
    case stat_halfconfigured: case stat_unpacked:
      return true;
    default:
      internerr("unknown status depending '%d'", dep->up->status);
    }
    break;
  case itb_installnew: case itb_preinstall:
    break;
  default:
    internerr("unknown istobe depending '%d'", dep->up->clientdata->istobe);
  }

  /* Describe the dependency, in case we have to moan about it. */
  varbuf_reset(whynot);
  varbuf_add_char(whynot, ' ');
  describedepcon(whynot, dep);
  varbuf_add_char(whynot, '\n');

  /* TODO: Check dep_enhances as well. */
  if (dep->type == dep_depends || dep->type == dep_predepends ||
      dep->type == dep_recommends || dep->type == dep_suggests ) {
    /* Go through the alternatives. As soon as we find one that
     * we like, we return ‘true’ straight away. Otherwise, when we get to
     * the end we'll have accumulated all the reasons in whynot and
     * can return ‘false’. */

    for (possi= dep->list; possi; possi= possi->next) {
      switch (possi->ed->clientdata->istobe) {
      case itb_remove:
        sprintf(linebuf,_("  %.250s is to be removed.\n"),possi->ed->name);
        break;
      case itb_deconfigure:
        sprintf(linebuf,_("  %.250s is to be deconfigured.\n"),possi->ed->name);
        break;
      case itb_installnew:
        if (versionsatisfied(&possi->ed->available, possi))
          return true;
        sprintf(linebuf,_("  %.250s is to be installed, but is version %.250s.\n"),
                possi->ed->name,
                versiondescribe(&possi->ed->available.version,vdew_nonambig));
        break;
      case itb_normal: case itb_preinstall:
        switch (possi->ed->status) {
        case stat_installed:
        case stat_triggerspending:
          if (versionsatisfied(&possi->ed->installed, possi))
            return true;
          sprintf(linebuf,_("  %.250s is installed, but is version %.250s.\n"),
                  possi->ed->name,
                  versiondescribe(&possi->ed->installed.version,vdew_nonambig));
          break;
        case stat_notinstalled:
          /* Don't say anything about this yet - it might be a virtual package.
           * Later on, if nothing has put anything in linebuf, we know that it
           * isn't and issue a diagnostic then. */
          *linebuf = '\0';
          break;
        case stat_triggersawaited:
            if (canfixbytrigaw && versionsatisfied(&possi->ed->installed, possi))
              *canfixbytrigaw = possi->ed;
            /* Fall through to have a chance to return OK due to
             * allowunconfigd and to fill the explanation */
        case stat_unpacked:
        case stat_halfconfigured:
          if (allowunconfigd) {
            if (!informativeversion(&possi->ed->configversion)) {
              sprintf(linebuf, _("  %.250s is unpacked, but has never been configured.\n"),
                      possi->ed->name);
              break;
            } else if (!versionsatisfied(&possi->ed->installed, possi)) {
              sprintf(linebuf, _("  %.250s is unpacked, but is version %.250s.\n"),
                      possi->ed->name,
                      versiondescribe(&possi->ed->installed.version, vdew_nonambig));
              break;
            } else if (!versionsatisfied3(&possi->ed->configversion,
                                          &possi->version,possi->verrel)) {
              sprintf(linebuf, _("  %.250s latest configured version is %.250s.\n"),
                      possi->ed->name,
                      versiondescribe(&possi->ed->configversion,vdew_nonambig));
              break;
            } else {
              return true;
            }
          }
          /* Fall through. */
        default:
          sprintf(linebuf, _("  %.250s is %s.\n"),
                  possi->ed->name, gettext(statusstrings[possi->ed->status]));
          break;
        }
        break;
      default:
        internerr("unknown istobe depended '%d'", possi->ed->clientdata->istobe);
      }
      varbuf_add_str(whynot, linebuf);

      /* If there was no version specified we try looking for Providers. */
      if (possi->verrel == dvr_none) {
        /* See if the package we're about to install Provides it. */
        for (provider= possi->ed->available.depended;
             provider;
             provider = provider->rev_next) {
          if (provider->up->type != dep_provides) continue;
          if (provider->up->up->clientdata->istobe == itb_installnew)
            return true;
        }

        /* Now look at the packages already on the system. */
        for (provider= possi->ed->installed.depended;
             provider;
             provider = provider->rev_next) {
          if (provider->up->type != dep_provides) continue;

          switch (provider->up->up->clientdata->istobe) {
          case itb_installnew:
            /* Don't pay any attention to the Provides field of the
             * currently-installed version of the package we're trying
             * to install. We dealt with that by using the available
             * information above. */
            continue;
          case itb_remove:
            sprintf(linebuf, _("  %.250s provides %.250s but is to be removed.\n"),
                    provider->up->up->name, possi->ed->name);
            break;
          case itb_deconfigure:
            sprintf(linebuf, _("  %.250s provides %.250s but is to be deconfigured.\n"),
                    provider->up->up->name, possi->ed->name);
            break;
          case itb_normal: case itb_preinstall:
            if (provider->up->up->status == stat_installed ||
                provider->up->up->status == stat_triggerspending)
              return true;
            if (provider->up->up->status == stat_triggersawaited)
              *canfixbytrigaw = provider->up->up;
            sprintf(linebuf, _("  %.250s provides %.250s but is %s.\n"),
                    provider->up->up->name, possi->ed->name,
                    gettext(statusstrings[provider->up->up->status]));
            break;
          default:
            internerr("unknown istobe provider '%d'",
                      provider->up->up->clientdata->istobe);
          }
          varbuf_add_str(whynot, linebuf);
        }

        if (!*linebuf) {
          /* If the package wasn't installed at all, and we haven't said
           * yet why this isn't satisfied, we should say so now. */
          sprintf(linebuf, _("  %.250s is not installed.\n"), possi->ed->name);
          varbuf_add_str(whynot, linebuf);
        }
      }
    }

    return false;
  } else {
    /* It's conflicts or breaks. There's only one main alternative,
     * but we also have to consider Providers. We return ‘false’ as soon
     * as we find something that matches the conflict, and only describe
     * it then. If we get to the end without finding anything we return
     * ‘true’. */

    possi= dep->list;
    nconflicts= 0;

    if (possi->ed != possi->up->up) {
      /* If the package conflicts with or breaks itself it must mean
       * other packages which provide the same virtual name. We
       * therefore don't look at the real package and go on to the
       * virtual ones. */

      switch (possi->ed->clientdata->istobe) {
      case itb_remove:
        break;
      case itb_installnew:
        if (!versionsatisfied(&possi->ed->available, possi)) break;
        sprintf(linebuf, _("  %.250s (version %.250s) is to be installed.\n"),
                possi->ed->name,
                versiondescribe(&possi->ed->available.version,vdew_nonambig));
        varbuf_add_str(whynot, linebuf);
        if (!canfixbyremove)
          return false;
        nconflicts++;
        *canfixbyremove= possi->ed;
        break;
      case itb_deconfigure:
        if (dep->type == dep_breaks)
          break; /* Already deconfiguring this. */
        /* Fall through. */
      case itb_normal: case itb_preinstall:
        switch (possi->ed->status) {
        case stat_notinstalled: case stat_configfiles:
          break;
        case stat_halfinstalled: case stat_unpacked:
        case stat_halfconfigured:
          if (dep->type == dep_breaks)
            break; /* No problem. */
        case stat_installed:
        case stat_triggerspending:
        case stat_triggersawaited:
          if (!versionsatisfied(&possi->ed->installed, possi)) break;
          sprintf(linebuf, _("  %.250s (version %.250s) is present and %s.\n"),
                  possi->ed->name,
                  versiondescribe(&possi->ed->installed.version,vdew_nonambig),
                  gettext(statusstrings[possi->ed->status]));
          varbuf_add_str(whynot, linebuf);
          if (!canfixbyremove)
            return false;
          nconflicts++;
          *canfixbyremove= possi->ed;
        }
        break;
      default:
        internerr("unknown istobe conflict '%d'",
                  possi->ed->clientdata->istobe);
      }
    }

    /* If there was no version specified we try looking for Providers. */
    if (possi->verrel == dvr_none) {
      /* See if the package we're about to install Provides it. */
      for (provider= possi->ed->available.depended;
           provider;
           provider = provider->rev_next) {
        if (provider->up->type != dep_provides) continue;
        if (provider->up->up->clientdata->istobe != itb_installnew) continue;
        if (provider->up->up == dep->up)
          continue; /* Conflicts and provides the same. */
        sprintf(linebuf, _("  %.250s provides %.250s and is to be installed.\n"),
                provider->up->up->name, possi->ed->name);
        varbuf_add_str(whynot, linebuf);
        /* We can't remove the one we're about to install: */
        if (canfixbyremove)
          *canfixbyremove = NULL;
        return false;
      }

      /* Now look at the packages already on the system. */
      for (provider= possi->ed->installed.depended;
           provider;
           provider = provider->rev_next) {
        if (provider->up->type != dep_provides) continue;

        if (provider->up->up == dep->up)
          continue; /* Conflicts and provides the same. */

        switch (provider->up->up->clientdata->istobe) {
        case itb_installnew:
          /* Don't pay any attention to the Provides field of the
           * currently-installed version of the package we're trying
           * to install. We dealt with that package by using the
           * available information above. */
          continue;
        case itb_remove:
          continue;
        case itb_deconfigure:
          if (dep->type == dep_breaks)
            continue; /* Already deconfiguring. */
        case itb_normal: case itb_preinstall:
          switch (provider->up->up->status) {
          case stat_notinstalled: case stat_configfiles:
            continue;
          case stat_halfinstalled: case stat_unpacked:
          case stat_halfconfigured:
            if (dep->type == dep_breaks)
              break; /* No problem. */
          case stat_installed:
          case stat_triggerspending:
          case stat_triggersawaited:
            sprintf(linebuf,
                    _("  %.250s provides %.250s and is present and %s.\n"),
                    provider->up->up->name, possi->ed->name,
                    gettext(statusstrings[provider->up->up->status]));
            varbuf_add_str(whynot, linebuf);
            if (!canfixbyremove)
              return false;
            nconflicts++;
            *canfixbyremove= provider->up->up;
            break;
          }
          break;
        default:
          internerr("unknown istobe conflict provider '%d'",
                    provider->up->up->clientdata->istobe);
        }
      }
    }

    if (!nconflicts)
      return true;
    if (nconflicts > 1)
      *canfixbyremove = NULL;
    return false;

  } /* if (dependency) {...} else {...} */
}
